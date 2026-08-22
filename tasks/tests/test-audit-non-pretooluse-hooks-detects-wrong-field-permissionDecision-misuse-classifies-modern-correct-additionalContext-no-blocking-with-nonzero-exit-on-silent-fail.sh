#!/usr/bin/env bash
# test-audit-non-pretooluse-hooks-detects-wrong-field-permissionDecision-misuse-classifies-modern-correct-additionalContext-no-blocking-with-nonzero-exit-on-silent-fail.sh
#
# Regression test for the iter-62 INVERSE-schema audit at
# .mise/tasks/audit-non-pretooluse-hooks-for-accidental-use-of-
# pretooluse-only-hookSpecificOutput-permissionDecision-field-which-
# silently-fails-to-block-on-posttooluse-stop-userpromptsubmit-
# sessionstart-sessionend-events.
#
# WHY this is load-bearing:
#
#   Iter-60 audits the FORWARD silent-fail (PreToolUse hooks
#   accidentally using the deprecated top-level decision:"block"
#   schema). This iter-62 audit covers the INVERSE silent-fail
#   (non-PreToolUse hooks accidentally using the PreToolUse-only
#   hookSpecificOutput.permissionDecision field).
#
#   Both directions are SILENT because Claude Code reads only the
#   canonical field for each event. A wrong-field hook's blocking
#   decision goes to /dev/null and the tool/turn proceeds as if the
#   hook had returned `allow`/`null`. Forensics on a "PostToolUse
#   didn't block" or "Stop hook didn't prevent stopping" incident are
#   hard to trace because the hook AUTHOR sees their JSON being
#   emitted to stdout normally.
#
#   At iter-62 build time the marketplace has ZERO instances of this
#   silent-fail — pure preventive infrastructure. The regression
#   test ensures the audit itself can't silently break detection if
#   a future commit edits the classification logic.
#
# Coverage matrix (7 fixtures across 5 event categories):
#
#   # | Fixture                                          | Event              | Expected Class           | Exit
#   --|--------------------------------------------------|--------------------|--------------------------|-----
#   01| PostToolUse using top-level decision:block       | PostToolUse        | SCHEMA-CORRECT-FOR-EVENT | 0
#   02| PostToolUse using permissionDecision (WRONG)     | PostToolUse        | WRONG-FIELD-SILENT-FAIL  | 1
#   03| Stop using top-level decision:block + reason     | Stop               | SCHEMA-CORRECT-FOR-EVENT | 0
#   04| Stop using permissionDecision (WRONG)            | Stop               | WRONG-FIELD-SILENT-FAIL  | 1
#   05| UserPromptSubmit using permissionDecision (WRONG)| UserPromptSubmit   | WRONG-FIELD-SILENT-FAIL  | 1
#   06| PostToolUse using hookSpecificOutput.additionalContext (CORRECT, non-blocking) | PostToolUse | SCHEMA-CORRECT-FOR-EVENT | 0
#   07| Stop hook with pure console.error (no decision) — reminder only | Stop | NO-BLOCKING-EMITTED | 0
#
# Plus exit-code, diagnostic-content, and per-fixture marker assertions.
#
# Verbose filename encodes WHAT it tests (the inverse schema audit),
# WHICH classifications (wrong-field, modern-correct, additionalContext,
# no-blocking), and WHICH gate (nonzero exit on silent-fail). Future
# maintainers searching for "inverse schema audit test",
# "PostToolUse permissionDecision wrong field test", "Stop hook block
# field test", or "non-PreToolUse schema test" surface this regression
# guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK="$SCRIPT_DIR/../audit-non-pretooluse-hooks-for-accidental-use-of-pretooluse-only-hookSpecificOutput-permissionDecision-field-which-silently-fails-to-block-on-posttooluse-stop-userpromptsubmit-sessionstart-sessionend-events.sh"

if [ ! -x "$AUDIT_TASK" ]; then
  echo "FATAL: audit task not executable: $AUDIT_TASK" >&2
  exit 1
fi

FIXTURE_FLEET_ROOT=$(mktemp -d -t inverse-pretooluse-schema-audit-regression-fixture-fleet.XXXXXX)
trap 'rm -rf "$FIXTURE_FLEET_ROOT"' EXIT

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: create a hook source file in a synthetic plugin.
create_non_pretooluse_hook_fixture() {
  local plugin_name="$1" hook_filename="$2" hook_content="$3"
  local hooks_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name/hooks"
  mkdir -p "$hooks_dir"
  printf '%s\n' "$hook_content" > "$hooks_dir/$hook_filename"
}

# ---------------------------------------------------------------------------
# Build fixture fleet
# ---------------------------------------------------------------------------
echo "=== Building synthetic fixture fleet at $FIXTURE_FLEET_ROOT ==="

# #01 PostToolUse with CORRECT schema (top-level decision:"block" + reason)
create_non_pretooluse_hook_fixture "fixture01-posttooluse-correct-toplevel-decision" "posttooluse-blocker.ts" \
'#!/usr/bin/env bun
console.log(JSON.stringify({
  decision: "block",
  reason: "tool output failed validation",
}));'

# #02 PostToolUse with WRONG schema (permissionDecision is PreToolUse-only)
create_non_pretooluse_hook_fixture "fixture02-posttooluse-wrong-field-permissionDecision" "posttooluse-broken-blocker.ts" \
'#!/usr/bin/env bun
// SCHEMA REGRESSION: permissionDecision is PreToolUse-only.
// This hook silently fails to block because PostToolUse reads top-level decision.
console.log(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "this will never block — silent fail",
  },
}));'

# #03 Stop with CORRECT schema
create_non_pretooluse_hook_fixture "fixture03-stop-correct-toplevel-decision" "stop-prevent-stop.ts" \
'#!/usr/bin/env bun
console.log(JSON.stringify({
  decision: "block",
  reason: "you have unfinished tasks — continue",
}));'

# #04 Stop with WRONG schema (permissionDecision is PreToolUse-only)
create_non_pretooluse_hook_fixture "fixture04-stop-wrong-field-permissionDecision" "stop-broken-blocker.ts" \
'#!/usr/bin/env bun
// SCHEMA REGRESSION: permissionDecision is PreToolUse-only.
// Stop hooks read top-level decision; this silently fails.
console.log(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "Stop",
    permissionDecision: "deny",
  },
}));'

# #05 UserPromptSubmit with WRONG schema
create_non_pretooluse_hook_fixture "fixture05-userpromptsubmit-wrong-field-permissionDecision" "userpromptsubmit-broken-blocker.ts" \
'#!/usr/bin/env bun
// SCHEMA REGRESSION: UserPromptSubmit uses top-level decision:"block",
// NOT hookSpecificOutput.permissionDecision. This silently fails.
console.log(JSON.stringify({
  hookSpecificOutput: {
    permissionDecision: "deny",
  },
}));'

# #06 PostToolUse with CORRECT additionalContext (non-blocking informational)
create_non_pretooluse_hook_fixture "fixture06-posttooluse-correct-additionalContext" "posttooluse-informational.ts" \
'#!/usr/bin/env bun
console.log(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "tool ran fine; here is a soft reminder",
  },
}));'

# #07 Stop hook with no decision emitted (pure reminder/side-effect)
create_non_pretooluse_hook_fixture "fixture07-stop-no-blocking-emitted-reminder-only" "stop-reminder.ts" \
'#!/usr/bin/env bun
console.error("[STOP-REMINDER] session ending — log line, no decision emitted");'

# ---------------------------------------------------------------------------
# Run audit and capture exit code
# ---------------------------------------------------------------------------
echo ""
echo "=== Running audit against synthetic fixture fleet (expect exit 1 due to fixtures #2, #4, #5) ==="

set +e
AUDIT_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
AUDIT_EXIT=$?
set -e

# ---------------------------------------------------------------------------
# Classification assertions
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting summary counts ==="

scanned=$(echo "$AUDIT_OUTPUT" | grep -oE 'Total non-PreToolUse hook source files scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
correct=$(echo "$AUDIT_OUTPUT" | grep -oE 'SCHEMA-CORRECT-FOR-EVENT:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
no_blocking=$(echo "$AUDIT_OUTPUT" | grep -oE 'NO-BLOCKING-EMITTED \(reminder-only\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
wrong=$(echo "$AUDIT_OUTPUT" | grep -oE 'WRONG-FIELD-SILENT-FAIL \(permissionDecision\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)

# Expected: 7 total scanned, 3 correct (#1, #3, #6), 1 no-blocking (#7),
# 3 wrong-field (#2, #4, #5).
if [ "$scanned" = "7" ]; then
  assert_pass "Total scanned = 7 (one fixture per scenario)"
else
  assert_fail "Total scanned = $scanned, expected 7"
fi

if [ "$correct" = "3" ]; then
  assert_pass "SCHEMA-CORRECT-FOR-EVENT count = 3 (fixtures #1, #3, #6)"
else
  assert_fail "SCHEMA-CORRECT-FOR-EVENT count = $correct, expected 3"
fi

if [ "$no_blocking" = "1" ]; then
  assert_pass "NO-BLOCKING-EMITTED count = 1 (fixture #7)"
else
  assert_fail "NO-BLOCKING-EMITTED count = $no_blocking, expected 1"
fi

if [ "$wrong" = "3" ]; then
  assert_pass "WRONG-FIELD-SILENT-FAIL count = 3 (fixtures #2, #4, #5)"
else
  assert_fail "WRONG-FIELD-SILENT-FAIL count = $wrong, expected 3"
fi

# Per-fixture marker assertions (each WRONG-FIELD fixture should
# appear in the violation diagnostic section with its event name).
if echo "$AUDIT_OUTPUT" | grep -q 'fixture02-posttooluse-wrong-field-permissionDecision.*event: PostToolUse'; then
  assert_pass "Fixture #02 reported under PostToolUse event"
else
  assert_fail "Fixture #02 PostToolUse event tag missing"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture04-stop-wrong-field-permissionDecision.*event: Stop'; then
  assert_pass "Fixture #04 reported under Stop event"
else
  assert_fail "Fixture #04 Stop event tag missing"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture05-userpromptsubmit-wrong-field-permissionDecision.*event: UserPromptSubmit'; then
  assert_pass "Fixture #05 reported under UserPromptSubmit event"
else
  assert_fail "Fixture #05 UserPromptSubmit event tag missing"
fi

# ---------------------------------------------------------------------------
# Exit-code assertion (the gate)
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting audit exits NON-ZERO when WRONG-FIELD-SILENT-FAIL detected ==="

if [ "$AUDIT_EXIT" = "1" ]; then
  assert_pass "Audit exited with code 1 (gate fires — preflight would block release)"
else
  assert_fail "Audit exited with code $AUDIT_EXIT, expected 1"
fi

# ---------------------------------------------------------------------------
# Diagnostic message content (operator-actionable guidance)
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting diagnostic guidance content ==="

if echo "$AUDIT_OUTPUT" | grep -q 'PreToolUse-only field'; then
  assert_pass "Diagnostic mentions PreToolUse-only field (root cause)"
else
  assert_fail "Diagnostic missing 'PreToolUse-only field' explanation"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'top-level decision'; then
  assert_pass "Diagnostic mentions top-level decision (the fix)"
else
  assert_fail "Diagnostic missing 'top-level decision' fix guidance"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'silently does not fire'; then
  assert_pass "Diagnostic describes the silent-fail behavior"
else
  assert_fail "Diagnostic missing silent-fail behavior description"
fi

# ---------------------------------------------------------------------------
# Positive-only run (remove silent-fail fixtures; expect exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "=== Removing all WRONG-FIELD fixtures and re-running (expect exit 0) ==="

rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture02-posttooluse-wrong-field-permissionDecision"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture04-stop-wrong-field-permissionDecision"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture05-userpromptsubmit-wrong-field-permissionDecision"

set +e
CLEAN_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
CLEAN_EXIT=$?
set -e

if [ "$CLEAN_EXIT" = "0" ]; then
  assert_pass "Audit exited 0 after wrong-field fixtures removed (clean state)"
else
  assert_fail "Audit exited $CLEAN_EXIT after fixtures removed, expected 0"
  echo "    Output was:"
  # shellcheck disable=SC2001
  # SC2001 intentional: sed `s/^/    /` uses regex start-of-line anchor;
  # bash globs have no equivalent.
  echo "$CLEAN_OUTPUT" | sed 's/^/    /'
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
  trap - EXIT
  exit 1
fi
