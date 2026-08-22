#!/usr/bin/env bash
# test-audit-hooks-for-async-true-eligibility-classifies-each-of-the-eight-detection-layers-correctly-against-synthetic-fixtures.sh
#
# Regression test for the iter-57/58/59 async-eligibility audit task at
# .mise/tasks/audit-hooks-for-async-true-eligibility-via-blocking-decision-
# emission-detection.
#
# This audit is now LOAD-BEARING for safety: iter-58 demonstrated it
# catches production-critical false positives (pretooluse-pueue-wrap-
# guard.ts → OP_SERVICE_ACCOUNT_TOKEN injection would silently break
# under async). Without regression coverage, any future edit could
# silently break a detection layer and ship breakage.
#
# Approach: construct a synthetic-fixture plugin fleet in a temp dir,
# one fixture per detection layer + edge case (12 fixtures total),
# point the audit at it via AUDIT_REPO_ROOT_OVERRIDE, then assert each
# fixture lands in the correct classification bucket.
#
# Coverage matrix (12 fixtures):
#
#   #  | Detection Layer                   | Fixture Stub Pattern                        | Expected Classification
#   ---|-----------------------------------|---------------------------------------------|-------------------------------
#   01 | Layer 1: permissionDecision deny  | jq -n '{"permissionDecision":"deny"}'       | MUST-STAY-SYNC
#   02 | Layer 2: deny() helper            | import {deny}; deny('reason')               | MUST-STAY-SYNC
#   03 | Layer 3: decision:block (PreTU)   | jq -n '{"decision":"block"}'                | MUST-STAY-SYNC
#   04 | Layer 4: process.exit(2)          | process.exit(2)                             | MUST-STAY-SYNC
#   05 | Layer 5: bash exit 2              | exit 2  (in PostToolUse, intentional block) | MUST-STAY-SYNC
#   06 | Layer 6: input-rewriter           | jq -n '{"hookSpecificOutput":{"updatedInput | MUST-STAY-SYNC-INPUT-REWRITER
#      |                                   |   ":{...}}}'                                |
#   07 | Layer 7: additionalContext        | additionalContext: "hint text"              | ASYNC-CANDIDATE-WITH-CAVEAT
#   08 | Layer 8: console.log (PostTU)     | console.log("[REMINDER] ...")               | ASYNC-CANDIDATE-WITH-CAVEAT
#   09 | Layer 8: console.info (iter-59)   | console.info("[INFO] ...")                  | ASYNC-CANDIDATE-WITH-CAVEAT
#   10 | EDGE: pure side-effect            | (no detection patterns at all)              | ASYNC-ELIGIBLE
#   11 | EDGE: ALREADY-ASYNC               | hooks.json has "async": true                | ALREADY-ASYNC
#   12 | EDGE: UserPromptSubmit            | (any content)                               | ASYNC-EVENT-INCOMPATIBLE
#
# Verbose filename encodes WHAT it tests (the audit task), WHICH
# behavior (the 8 detection layers + edge cases), and HOW (synthetic-
# fixture fleet). Future maintainers searching for "audit task test",
# "async eligibility test", or any layer name surface this regression
# guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK="$SCRIPT_DIR/../audit-hooks-for-async-true-eligibility-via-blocking-decision-emission-detection"

if [ ! -x "$AUDIT_TASK" ]; then
  echo "FATAL: audit task not executable: $AUDIT_TASK" >&2
  exit 1
fi

# Create a fresh temp dir for the synthetic fixture fleet. Use mktemp -d
# with a descriptive prefix so debug forensics on failure are obvious.
FIXTURE_FLEET_ROOT=$(mktemp -d -t audit-task-regression-fixture-fleet.XXXXXX)
trap 'rm -rf "$FIXTURE_FLEET_ROOT"' EXIT

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Fixture-builder helpers
# ---------------------------------------------------------------------------

# Construct one fixture: $1=plugin_name, $2=event, $3=matcher (or empty),
# $4=script_filename, $5=script_content, $6=async_value (true/omit).
create_fixture_plugin() {
  local plugin_name="$1" event="$2" matcher="$3" script_filename="$4"
  local script_content="$5" async_value="${6:-}"

  local plugin_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name"
  local hooks_dir="$plugin_dir/hooks"
  mkdir -p "$hooks_dir"

  # Write the script. Use the explicit filename (might be .sh, .ts, .mjs).
  printf '%s\n' "$script_content" > "$hooks_dir/$script_filename"
  chmod +x "$hooks_dir/$script_filename"

  # Choose runner prefix by extension.
  local runner=""
  case "$script_filename" in
    *.ts|*.mjs|*.js) runner="bun " ;;
    *.py)            runner="python3 " ;;
    *.sh)            runner="" ;;  # bash hooks invoke directly
  esac

  # Construct the matcher-or-empty fragment.
  local matcher_fragment=""
  if [ -n "$matcher" ]; then
    matcher_fragment='"matcher": "'"$matcher"'",'
  fi

  # Construct the async-or-empty fragment.
  local async_fragment=""
  if [ "$async_value" = "true" ]; then
    async_fragment=',
            "async": true'
  fi

  cat > "$hooks_dir/hooks.json" <<HOOKS_JSON_EOF
{
  "hooks": {
    "$event": [
      {
        $matcher_fragment
        "hooks": [
          {
            "type": "command",
            "command": "${runner}\${CLAUDE_PLUGIN_ROOT}/hooks/$script_filename"$async_fragment
          }
        ]
      }
    ]
  }
}
HOOKS_JSON_EOF
}

# ---------------------------------------------------------------------------
# Build the 12 synthetic fixtures
# ---------------------------------------------------------------------------
echo "=== Building synthetic fixture fleet at $FIXTURE_FLEET_ROOT ==="

# #01 Layer 1: permissionDecision deny (PreToolUse, bash + jq)
create_fixture_plugin "fixture01-layer1-permissionDecision-deny" "PreToolUse" "Bash" "guard.sh" \
  '#!/usr/bin/env bash
exec jq -n '\''{"permissionDecision":"deny","reason":"test fixture"}'\'''

# #02 Layer 2: deny() helper call (PreToolUse, TS)
create_fixture_plugin "fixture02-layer2-deny-helper-call" "PreToolUse" "Bash" "guard.ts" \
  '#!/usr/bin/env bun
import {deny} from "./helpers";
deny("test fixture");'

# #03 Layer 3: decision:block literal (PreToolUse, bash + jq)
create_fixture_plugin "fixture03-layer3-decision-block-pretooluse" "PreToolUse" "Bash" "guard.sh" \
  '#!/usr/bin/env bash
exec jq -n '\''{"decision":"block","reason":"test fixture"}'\'''

# #04 Layer 4: process.exit(2) (PreToolUse, TS)
create_fixture_plugin "fixture04-layer4-process-exit-two" "PreToolUse" "Bash" "guard.ts" \
  '#!/usr/bin/env bun
console.error("blocking via exit code 2");
process.exit(2);'

# #05 Layer 5: bash exit 2 (PostToolUse — intentionally blocking).
# Use PostToolUse so it does NOT trip Layer 8 (Layer 8 fires only when
# console.log/info appears, which this fixture doesn't have).
create_fixture_plugin "fixture05-layer5-bash-exit-two" "PostToolUse" "Bash" "guard.sh" \
  '#!/usr/bin/env bash
echo "blocking via exit code 2" >&2
exit 2'

# #06 Layer 6: input-rewriter via hookSpecificOutput.updatedInput (PreToolUse, bash)
create_fixture_plugin "fixture06-layer6-input-rewriter-via-hookSpecificOutput" "PreToolUse" "Bash" "rewriter.sh" \
  '#!/usr/bin/env bash
exec jq -n '\''{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"rewritten"}}}'\'''

# #07 Layer 7: additionalContext (PostToolUse, TS)
create_fixture_plugin "fixture07-layer7-additionalContext-injection" "PostToolUse" "Write" "context-injector.ts" \
  '#!/usr/bin/env bun
console.log(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"hint text"}}));'

# #08 Layer 8: console.log (PostToolUse, TS) — legacy stdout-as-context
create_fixture_plugin "fixture08-layer8-console-log-stdout-context" "PostToolUse" "Write" "reminder.ts" \
  '#!/usr/bin/env bun
console.log("[REMINDER] legacy raw-stdout context-injection pattern");'

# #09 Layer 8 extended (iter-59): console.info (PostToolUse, TS) — same fd 1 as console.log
create_fixture_plugin "fixture09-layer8-extended-console-info-iter59" "PostToolUse" "Write" "reminder.ts" \
  '#!/usr/bin/env bun
console.info("[INFO] console.info also writes to stdout fd 1 — caught by iter-59 Layer 8 extension");'

# #10 EDGE: pure side-effect (Stop, TS, no patterns at all)
create_fixture_plugin "fixture10-edge-pure-side-effect" "Stop" "" "cleanup.ts" \
  '#!/usr/bin/env bun
import {writeFileSync} from "fs";
writeFileSync("/tmp/test-fixture-10-cleanup.marker", String(Date.now()));'

# #11 EDGE: ALREADY-ASYNC (Stop, TS, has async:true in hooks.json)
create_fixture_plugin "fixture11-edge-already-async" "Stop" "" "notify.ts" \
  '#!/usr/bin/env bun
import {writeFileSync} from "fs";
writeFileSync("/tmp/test-fixture-11-notify.marker", "");' \
  "true"

# #12 EDGE: UserPromptSubmit (event-incompatible regardless of content)
create_fixture_plugin "fixture12-edge-userpromptsubmit-event-incompatible" "UserPromptSubmit" "" "context-injector.sh" \
  '#!/usr/bin/env bash
echo "I would inject context here but UserPromptSubmit can never be async"'

# ---------------------------------------------------------------------------
# Run the audit against the fixture fleet
# ---------------------------------------------------------------------------
echo ""
echo "=== Running audit against synthetic fixture fleet ==="

AUDIT_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1) || true

# Helper: assert a fixture plugin appears in the named classification section
# of the audit output. We pattern-match on the unique plugin name; if it
# appears anywhere in the section between the bucket-header line and the
# next "─── " section divider, the assertion passes.
assert_fixture_in_bucket() {
  local fixture_name="$1" bucket_label="$2" description="$3"

  # Extract just the section for this bucket using sed range addressing.
  # Section starts at "─── $bucket_label" and ends at the next "─── "
  # divider (or end of input).
  local section
  section=$(echo "$AUDIT_OUTPUT" | sed -n "/^─── ${bucket_label}/,/^─── /p")

  if echo "$section" | grep -q "$fixture_name"; then
    assert_pass "$description"
  else
    assert_fail "$description (fixture=$fixture_name, expected-bucket=$bucket_label)"
    echo "    --- bucket section seen: ---"
    # shellcheck disable=SC2001
    # SC2001 intentional: sed `s/^/    /` uses regex start-of-line anchor
    # to prepend indentation to every line. Bash's ${var//pat/repl} uses
    # glob substitution which has no equivalent for ^ — the suggested
    # replacement would need awk or a per-line loop, both more complex
    # than the sed one-liner.
    echo "$section" | sed 's/^/    /'
  fi
}

echo ""
echo "=== Asserting each fixture lands in correct classification bucket ==="

assert_fixture_in_bucket "fixture01-layer1-permissionDecision-deny" \
  "MUST-STAY-SYNC" \
  "Layer 1: permissionDecision:deny → MUST-STAY-SYNC"

assert_fixture_in_bucket "fixture02-layer2-deny-helper-call" \
  "MUST-STAY-SYNC" \
  "Layer 2: deny() helper call → MUST-STAY-SYNC"

assert_fixture_in_bucket "fixture03-layer3-decision-block-pretooluse" \
  "MUST-STAY-SYNC" \
  "Layer 3: decision:block on PreToolUse → MUST-STAY-SYNC"

assert_fixture_in_bucket "fixture04-layer4-process-exit-two" \
  "MUST-STAY-SYNC" \
  "Layer 4: process.exit(2) → MUST-STAY-SYNC"

assert_fixture_in_bucket "fixture05-layer5-bash-exit-two" \
  "MUST-STAY-SYNC" \
  "Layer 5: bash exit 2 → MUST-STAY-SYNC (audit is unconditionally cautious for exit-2 — even on PostToolUse where the tool already ran; safe over-classification — iter-60 candidate to refine if needed)"

assert_fixture_in_bucket "fixture06-layer6-input-rewriter-via-hookSpecificOutput" \
  "MUST-STAY-SYNC-INPUT-REWRITER" \
  "Layer 6: hookSpecificOutput.updatedInput → MUST-STAY-SYNC-INPUT-REWRITER (iter-58 critical-safety layer)"

assert_fixture_in_bucket "fixture07-layer7-additionalContext-injection" \
  "ASYNC-CANDIDATE-WITH-CAVEAT" \
  "Layer 7: additionalContext literal → ASYNC-CANDIDATE-WITH-CAVEAT"

assert_fixture_in_bucket "fixture08-layer8-console-log-stdout-context" \
  "ASYNC-CANDIDATE-WITH-CAVEAT" \
  "Layer 8: console.log on PostToolUse → ASYNC-CANDIDATE-WITH-CAVEAT"

assert_fixture_in_bucket "fixture09-layer8-extended-console-info-iter59" \
  "ASYNC-CANDIDATE-WITH-CAVEAT" \
  "Layer 8 iter-59 extension: console.info on PostToolUse → ASYNC-CANDIDATE-WITH-CAVEAT"

assert_fixture_in_bucket "fixture10-edge-pure-side-effect" \
  "ASYNC-ELIGIBLE" \
  "Edge: pure side-effect (no patterns) → ASYNC-ELIGIBLE"

assert_fixture_in_bucket "fixture11-edge-already-async" \
  "ALREADY-ASYNC" \
  "Edge: async:true in hooks.json → ALREADY-ASYNC"

assert_fixture_in_bucket "fixture12-edge-userpromptsubmit-event-incompatible" \
  "ASYNC-EVENT-INCOMPATIBLE" \
  "Edge: UserPromptSubmit event → ASYNC-EVENT-INCOMPATIBLE"

# ---------------------------------------------------------------------------
# IFS-tab sentinel handling — verify Stop hooks (no matcher) resolve correctly
# ---------------------------------------------------------------------------
echo ""
echo "=== IFS-tab sentinel: Stop hooks (matcher-less) display <any> not 'false' ==="

# Stop hooks have no matcher field. Pre-iter-57 the bash IFS=$'\t' read
# collapsed consecutive tabs and shifted is_async into matcher's slot.
# The ANYMATCHER_SENTINEL fix preserves correct field order. Verify by
# checking that fixture10 (Stop) and fixture11 (Stop) display "<any>"
# in their rendered line, not literal "false".
fixture10_render=$(echo "$AUDIT_OUTPUT" | grep "fixture10-edge-pure-side-effect" || true)
fixture11_render=$(echo "$AUDIT_OUTPUT" | grep "fixture11-edge-already-async" || true)

if echo "$fixture10_render" | grep -q 'matcher=<any>'; then
  assert_pass "Stop hook fixture10 displays matcher=<any> (IFS-tab sentinel works)"
else
  assert_fail "Stop hook fixture10 missing matcher=<any>. Got: $fixture10_render"
fi

if echo "$fixture11_render" | grep -q 'matcher=<any>'; then
  assert_pass "Stop hook fixture11 displays matcher=<any> (IFS-tab sentinel works)"
else
  assert_fail "Stop hook fixture11 missing matcher=<any>. Got: $fixture11_render"
fi

# ---------------------------------------------------------------------------
# Path resolution — verify the audit resolves \${CLAUDE_PLUGIN_ROOT} correctly
# ---------------------------------------------------------------------------
echo ""
echo "=== Path resolution: no SCRIPT_MISSING errors in audit output ==="

if echo "$AUDIT_OUTPUT" | grep -q 'SCRIPT_MISSING'; then
  assert_fail "Audit reported SCRIPT_MISSING — path resolution regressed"
  echo "    Lines reporting SCRIPT_MISSING:"
  # shellcheck disable=SC2001
  # SC2001 intentional: regex start-of-line anchor `^` for indentation
  # prepend; bash globs have no equivalent. See line ~227 for same pattern.
  echo "$AUDIT_OUTPUT" | grep 'SCRIPT_MISSING' | sed 's/^/    /'
else
  assert_pass "No SCRIPT_MISSING errors — \${CLAUDE_PLUGIN_ROOT} resolution + bun-prefix-strip works for all 12 fixtures"
fi

# ---------------------------------------------------------------------------
# Total-hooks count sanity check
# ---------------------------------------------------------------------------
echo ""
echo "=== Sanity check: audit scanned exactly 12 fixtures ==="

scanned_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'Total registered hooks scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' || echo "0")

if [ "$scanned_count" = "12" ]; then
  assert_pass "Audit scanned exactly 12 fixtures (matches the synthetic-fleet size)"
else
  assert_fail "Audit scanned $scanned_count hooks but the fixture fleet has 12. Possible jq-emit-per-entry regression or fixture-builder bug."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Synthetic fixture fleet preserved for debugging at:"
  echo "  $FIXTURE_FLEET_ROOT"
  echo "(Will NOT be auto-cleaned because the test failed — inspect, then 'rm -rf' manually.)"
  # Override the EXIT trap so the fixture fleet survives for debugging.
  trap - EXIT
  exit 1
fi
