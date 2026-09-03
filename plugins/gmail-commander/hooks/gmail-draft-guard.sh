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


# The ONE copy of the builder that is supported: the installed marketplace build.
#
# Matched on the SUFFIX, not the absolute path. Callers legitimately write the same file three ways —
# `~/.claude/...`, `$HOME/.claude/...`, `/Users/me/.claude/...` — and a literal comparison against the
# expanded form rejected the first two. It rejected the very command this guard's own error message
# tells you to run, which is how a guard trains people to bypass it. The suffix cannot collide with a
# source checkout, because only the installed tree contains `.claude/plugins/marketplaces/`.
CANONICAL_SUFFIX=".claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts"
CANONICAL_TOOL="$HOME/$CANONICAL_SUFFIX"

INPUT=$(cat 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null || true)

[ -z "$CMD" ] && exit 0
case "$CMD" in
  *GMAIL_DRAFT_ADHOC_OK=1*) exit 0 ;;                      # explicit, auditable escape hatch
  *"$CANONICAL_SUFFIX"*)
    # LAYER 3: Canonical tool invoked — verify builder health before allowing the draft write.
    if [[ "${GMAIL_DRAFT_TEST_GATE_SKIP:-}" != "1" ]]; then
      verify_builder_health || exit $?
    fi
    exit 0
    ;;
  *scripts/gmail-draft.ts*)
    # Only an INVOCATION is interesting. Reading, grepping, type-checking or `bun test`-ing the file
    # is not staging a draft, and blocking those made plugin development itself require the escape
    # hatch on every command — which is precisely how a hatch stops meaning anything. The builder's
    # own required flags are the discriminator: nothing else passes --account/--body/--from.
    if ! grep -qE -- '--(account|body|from)([[:space:]]|=)' <<<"$CMD"; then
      exit 0
    fi
    # LAYER 4 (2026-07-30): the right TOOL from the WRONG COPY.
    #
    # This rule used to allow any path ending in `scripts/gmail-draft.ts`. On 2026-07-29 the builder
    # was hardened — RFC 2047 headers, list preservation, MIME validation — and those nine commits
    # lived ONLY in the installed marketplace clone. A client email was then staged the next day by
    # invoking `~/eon/cc-skills/.../gmail-draft.ts`, a source checkout nine commits behind, and it
    # re-introduced BOTH fixed bugs: three evidence bullets welded into one run-on paragraph, and an
    # em dash in the subject line delivered as "â€”". The guard permitted every step of it.
    #
    # Naming the right tool is not enough when two copies of it exist.
    cat >&2 <<MSG
BLOCKED: gmail-draft.ts invoked from a copy that is not the installed marketplace build.

  invoked : (a path other than the canonical one)
  expected: $CANONICAL_TOOL

A source checkout can be many commits behind the installed plugin. On 2026-07-30 one was nine behind
and re-introduced two already-fixed bugs into an email to a client — welded lists and a
mojibake subject line.

If you are deliberately testing a local build, prefix the command with GMAIL_DRAFT_ADHOC_OK=1.
MSG
    exit 2
    ;;
esac

# HTTP-write detection, defined once and used by BOTH the command-string layers and LAYER 5.
#
# Two shapes exist and a file can contain either: a curl invocation (`-X POST`, or implicit via a
# body flag) or code (`method: "POST"`). The first LAYER 5 draft only matched the quoted/code form,
# so a shell script running `curl -X POST .../drafts` was ALLOWED — caught by the probe, which is
# the entire reason the probe asserts both directions.
METHOD_RE='(-X|--request)[[:space:]]*=?[[:space:]]*"?'"'"'?(POST|PUT|PATCH|DELETE)|"method"[[:space:]]*:[[:space:]]*"?(POST|PUT|PATCH|DELETE)|method[[:space:]]*[:=][[:space:]]*"?(POST|PUT|PATCH|DELETE)|"(POST|PUT|PATCH|DELETE)"|'"'"'(POST|PUT|PATCH|DELETE)'"'"''
# curl POSTs implicitly when handed a body, with no method token anywhere.
IMPLICIT_POST_RE='(^|[[:space:]])(-d|--data|--data-raw|--data-binary|--data-urlencode|-F|--form|-T|--upload-file)([[:space:]]|=)'
ENDPOINT_RE='users/me/drafts|gmail\.googleapis\.com[^ ]*draft'

emit_adhoc_block_message() {
  cat >&2 <<'MSG'
BLOCKED: ad-hoc Gmail drafts-API write. Use the canonical builder instead:

  bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --account <tokenbase> --body <file.md> \
    --from 'Name <addr>' [--reply-to <msgId>] [--to ...] [--cc ...] [--subject ...] [--replace <draftId>]

Why: Gmail re-encodes ingested text/plain and HARD-FOLDS long lines (~72 cols) — ad-hoc drafts show
forced mid-paragraph line breaks in the compose window (regression 2026-07-23). The tool builds
multipart/alternative with a text/html part (wrap-immune) and unwraps formatter-wrapped sources.
Escape hatch (deliberate ad-hoc use): prefix the command with GMAIL_DRAFT_ADHOC_OK=1.
MSG
}

# ── LAYER 5 (2026-08-07): the write is INSIDE a script file, where the command string cannot see it.
#
# Layers 1–4 all pattern-match $CMD. That surface is blind to the most ordinary shape a caller takes:
#
#     bun correspondence/replace-gmail-drafts.ts --execute
#
# — which contains no endpoint, no method, and no curl flag, because the fetch() lives in the file.
# Verified ALLOW by every prior layer. This is not hypothetical and not new: it has now happened
# three times against the same client mailbox — `bash /tmp/example-client-make-draft.sh` earlier the same day,
# and a Bun script that evening. Both shipped the exact defect Layer 1 exists to prevent (a body
# carrying a formatter's ~100-col hard wrapping, delivered as text/plain and hard-folded again by
# Gmail into forced mid-sentence breaks), and one also shipped a mojibaked Subject.
#
# The guard was never weak at what it inspected. It inspected the wrong surface for this caller.
# So: when the command EXECUTES a script, read that script and apply the same test to its contents.
#
# Fail-open throughout (unreadable file, weird quoting, no match) — advisory infrastructure must
# never wedge a session. A missed detection costs one bad draft; a wedged shell costs the day.
INTERPRETER_RE='(^|[[:space:];&|(])(bun|bunx|node|deno|tsx|ts-node|python|python3|ruby|perl|bash|sh|zsh)([[:space:]]|$)'
DIRECT_EXEC_RE='(^|[[:space:];&|(])\./[^[:space:]]+'

if grep -qE "$INTERPRETER_RE" <<<"$CMD" || grep -qE "$DIRECT_EXEC_RE" <<<"$CMD"; then
  # `bun test` / `bun build` / `deno check` operate ON a file without running it as a program.
  # Blocking those would make working on any mailer require the escape hatch, which is how a hatch
  # stops meaning anything (the same reasoning as the LAYER 1 read-vs-invoke discriminator above).
  if ! grep -qE '(^|[[:space:]])(bun[[:space:]]+(test|build|x|install|add|pm)|deno[[:space:]]+(check|lint|fmt|test))([[:space:]]|$)' <<<"$CMD"; then
    for tok in $CMD; do
      # Strip quoting/redirection noise a naive word-split leaves attached.
      tok="${tok#[\"\']}"; tok="${tok%[\"\']}"; tok="${tok#./}"
      case "$tok" in
        *.ts|*.js|*.mjs|*.cjs|*.py|*.sh|*.zsh|*.rb|*.pl) ;;
        *) continue ;;
      esac
      [ -f "$tok" ] || continue
      # Endpoint AND a write verb in the same file. Inside a script a bare "POST" is a method, not
      # prose, so the looser test that was wrong for one-liners is right here.
      if grep -qE "$ENDPOINT_RE" "$tok" 2>/dev/null \
         && { grep -qiE "$METHOD_RE" "$tok" 2>/dev/null || grep -qE "$IMPLICIT_POST_RE" "$tok" 2>/dev/null; }; then
        printf 'BLOCKED: %s writes to the Gmail drafts API directly.\n\n' "$tok" >&2
        emit_adhoc_block_message
        cat >&2 <<'MSG'

(Detected by reading the script, not the command line — LAYER 5. The command you ran named no
endpoint and no HTTP method, which is exactly why the earlier layers passed it.)
MSG
        exit 2
      fi
    done
  fi
fi

if grep -qE "$ENDPOINT_RE" <<<"$CMD"; then
  # Detect a WRITE by finding an actual HTTP METHOD, not the mere presence of the word.
  #
  # The old test was `grep -qE '(POST|PUT|PATCH)'` anywhere in the command, and it was wrong in both
  # directions at once. It is case-SENSITIVE, so `curl -X put .../drafts` sailed straight through. And
  # it matched the substring in ordinary prose, so on 2026-07-30 a read-only GET was blocked because
  # the operator had written `echo "still intact after the failed PUT?"` earlier in the same line.
  # A guard that blocks reads while permitting writes is worse than no guard: it teaches people to
  # reach for the escape hatch by reflex, and then it is not there when it matters.
  if grep -qiE "$METHOD_RE" <<<"$CMD" || grep -qE "$IMPLICIT_POST_RE" <<<"$CMD"; then
    emit_adhoc_block_message
    exit 2
  fi
fi
exit 0
