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
GMAIL_DRAFT_BUILDER="${HOME}/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts"
GMAIL_DRAFT_TEST_FILE="${HOME}/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.test.ts"
GMAIL_DRAFT_TEST_CACHE="${HOME}/.claude/.cache/gmail-draft-builder-test.cache"  # JSON: { mtime, result }

function verify_builder_health() {
  local current_mtime
  current_mtime=$(stat -f%m "$GMAIL_DRAFT_BUILDER" 2>/dev/null || echo "0")

  # Check cache: if builder is unchanged and cache passed, skip re-test.
  if [[ -f "$GMAIL_DRAFT_TEST_CACHE" ]]; then
    local cached
    cached=$(cat "$GMAIL_DRAFT_TEST_CACHE" 2>/dev/null || echo "{}")
    local cached_mtime
    local cached_result
    cached_mtime=$(printf '%s' "$cached" | grep -o '"mtime":[0-9]*' | cut -d: -f2 || echo "0")
    cached_result=$(printf '%s' "$cached" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

    if [[ "$cached_mtime" == "$current_mtime" && "$cached_result" == "pass" ]]; then
      return 0  # cache hit, tests passed
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
    # Update cache with failure so we don't re-run on every invocation.
    mkdir -p "$(dirname "$GMAIL_DRAFT_TEST_CACHE")"
    printf '{"mtime":%s,"result":"fail"}' "$current_mtime" > "$GMAIL_DRAFT_TEST_CACHE"
    return 1
  fi

  # Tests passed; cache the result.
  mkdir -p "$(dirname "$GMAIL_DRAFT_TEST_CACHE")"
  printf '{"mtime":%s,"result":"pass"}' "$current_mtime" > "$GMAIL_DRAFT_TEST_CACHE"
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
