#!/usr/bin/env bash
# gmail-draft-guard — global PreToolUse(Bash) hook: block AD-HOC Gmail drafts-API calls + verify builder health.
#
# THREE INDEPENDENT LAYERS:
#
# LAYER 1 (original, 2026-07-23): Block ad-hoc Gmail drafts-API calls. The canonical builder
# (../scripts/gmail-draft.ts) produces multipart/alternative with text/html (wrap-immune), while
# ad-hoc text/plain drafts get hard-folded by Gmail's ingestion (~72 cols), causing mid-paragraph
# line breaks in the compose window.
#
# LAYER 3 (new, 2026-07-29): Before permitting a draft write via the canonical tool, run the
# builder's test suite and REFUSE if it fails. This prevents shipping a builder whose functions
# have no test coverage (as happened on 2026-07-29 when Subject encoding was never validated).
# Caches the result keyed on builder file mtime so batch operations do not re-run tests each time.
#
# LAYER 1 Fail-open on parse errors (advisory infrastructure must never wedge the session).
# LAYER 3 Fail-closed on test failure or missing test runner (a broken builder is worse than
#         blocking mail, and a missing test runner is likely a misconfiguration worth surfacing).
#
set -euo pipefail

# ── LAYER 3: Test-gate cache and runner ──
#
# Fail-closed on test failure or runner-missing: a builder without passing tests is not to be trusted.
# Cache keyed on mtime so batch operations scale (a typical batch does not rerun tests per draft).
#
GMAIL_DRAFT_SCRIPTS_DIR="${HOME}/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts"
GMAIL_DRAFT_TEST_FILE="${GMAIL_DRAFT_SCRIPTS_DIR}/gmail-draft.test.ts"
GMAIL_DRAFT_TEST_CACHE="${HOME}/.claude/.cache/gmail-draft-builder-test.cache"  # JSON: { fingerprint, result }

# Fingerprint EVERY input that can change the test outcome, not just the builder.
#
# WHY (bug found 2026-07-29 by exercising the gate in both directions): the cache was keyed on
# `gmail-draft.ts`'s mtime alone. Appending a deliberately failing test to gmail-draft.test.ts left
# the builder's mtime untouched, so the gate took a stale "pass" cache hit and PERMITTED the draft
# write. A gate that green-lights a builder whose tests are red is worse than no gate, because it
# reports safety it never checked. The test file, the builder, and every sibling module the suite
# imports are all inputs — so all of them are in the key.
function compute_builder_test_input_fingerprint() {
  # Sorted for determinism; path+size+mtime per file. Any add/remove/edit changes the digest.
  find "$GMAIL_DRAFT_SCRIPTS_DIR" -type f -name '*.ts' 2>/dev/null \
    | LC_ALL=C sort \
    | while IFS= read -r ts_file; do
        stat -f '%N %z %m' "$ts_file" 2>/dev/null || true
      done \
    | shasum -a 256 | cut -d' ' -f1
}

function verify_builder_health() {
  local current_fingerprint
  current_fingerprint=$(compute_builder_test_input_fingerprint)

  # Check cache: if NO test input changed and the cached run passed, skip re-testing.
  if [[ -f "$GMAIL_DRAFT_TEST_CACHE" ]]; then
    local cached
    cached=$(cat "$GMAIL_DRAFT_TEST_CACHE" 2>/dev/null || echo "{}")
    local cached_fingerprint
    local cached_result
    cached_fingerprint=$(printf '%s' "$cached" | grep -o '"fingerprint":"[^"]*"' | cut -d'"' -f4 || echo "")
    cached_result=$(printf '%s' "$cached" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

    if [[ -n "$current_fingerprint" && "$cached_fingerprint" == "$current_fingerprint" && "$cached_result" == "pass" ]]; then
      return 0  # cache hit, tests passed against exactly these inputs
    fi
  fi

  # Cache miss or stale: run tests.
  # If bun is missing or tests file is missing, fail-closed (do not allow draft).
  if ! command -v bun >/dev/null 2>&1; then
    cat >&2 <<'MSG'
LAYER 3 GATE: bun test runner not found. Cannot verify gmail-draft builder health.
Escape hatch: GMAIL_DRAFT_TEST_GATE_SKIP=1 (use only if you know the builder is healthy).
MSG
    return 2
  fi

  if [[ ! -f "$GMAIL_DRAFT_TEST_FILE" ]]; then
    cat >&2 <<MSG
LAYER 3 GATE: test file missing: $GMAIL_DRAFT_TEST_FILE
Cannot verify gmail-draft builder health. Escape hatch: GMAIL_DRAFT_TEST_GATE_SKIP=1
MSG
    return 2
  fi

  # Run tests. Capture output and check exit code separately.
  # We need to capture the exit code of bun test, so temporarily disable error-on-nonzero.
  local test_output
  local test_exit
  set +e
  test_output=$(bun test "$GMAIL_DRAFT_TEST_FILE" 2>&1)
  test_exit=$?
  set -e

  if [[ $test_exit -ne 0 ]]; then
    cat >&2 <<MSG
LAYER 3 GATE FAILED: gmail-draft builder tests did not pass.

${test_output}

Until the builder tests pass, no Gmail drafts can be sent. Escape hatch:
GMAIL_DRAFT_TEST_GATE_SKIP=1 (use only for debugging; most uses indicate a real bug).
MSG
    # Deliberately DO NOT cache the failure. Only a passing run is cacheable: a red suite must be
    # re-run every time so that the moment it goes green the gate opens on evidence, not on an
    # expiring record. (The previous code wrote a "fail" entry the read path never honoured.)
    return 1
  fi

  # Tests passed against exactly these inputs; cache that fact.
  mkdir -p "$(dirname "$GMAIL_DRAFT_TEST_CACHE")"
  printf '{"fingerprint":"%s","result":"pass"}' "$current_fingerprint" > "$GMAIL_DRAFT_TEST_CACHE"
  return 0
}


INPUT=$(cat 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null || true)

[ -z "$CMD" ] && exit 0
case "$CMD" in
  *GMAIL_DRAFT_ADHOC_OK=1*) exit 0 ;;                      # explicit, auditable escape hatch
  *scripts/gmail-draft.ts*)
    # LAYER 3: Canonical tool invoked — verify builder health before allowing the draft write.
    if [[ "${GMAIL_DRAFT_TEST_GATE_SKIP:-}" != "1" ]]; then
      verify_builder_health || exit $?
    fi
    exit 0
    ;;
esac

if printf '%s' "$CMD" | grep -qE 'users/me/drafts|gmail\.googleapis\.com[^ ]*draft'; then
  # Write detection is deliberately COARSE (quote-escaping variants defeated a precise regex):
  # any POST/PUT/PATCH token in a drafts-API command blocks. Read-only GET fetches pass; a rare
  # false positive is a loud pointer to the canonical tool, not damage — and the escape hatch exists.
  if printf '%s' "$CMD" | grep -qE '(POST|PUT|PATCH)'; then
    cat >&2 <<'MSG'
BLOCKED: ad-hoc Gmail drafts-API write. Use the canonical builder instead:

  bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --account <tokenbase> --body <file.md> \
    --from 'Name <addr>' [--reply-to <msgId>] [--to ...] [--cc ...] [--subject ...] [--replace <draftId>]

Why: Gmail re-encodes ingested text/plain and HARD-FOLDS long lines (~72 cols) — ad-hoc drafts show
forced mid-paragraph line breaks in the compose window (regression 2026-07-23). The tool builds
multipart/alternative with a text/html part (wrap-immune) and unwraps formatter-wrapped sources.
Escape hatch (deliberate ad-hoc use): prefix the command with GMAIL_DRAFT_ADHOC_OK=1.
MSG
    exit 2
  fi
fi
exit 0
