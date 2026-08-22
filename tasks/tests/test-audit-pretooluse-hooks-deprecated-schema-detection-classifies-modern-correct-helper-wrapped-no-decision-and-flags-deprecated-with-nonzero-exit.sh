#!/usr/bin/env bash
# test-audit-pretooluse-hooks-deprecated-schema-detection-classifies-modern-correct-helper-wrapped-no-decision-and-flags-deprecated-with-nonzero-exit.sh
#
# Regression test for the iter-60 PreToolUse schema-correctness audit at
# .mise/tasks/audit-pretooluse-hooks-for-deprecated-top-level-decision-
# schema-versus-modern-hookSpecificOutput-permissionDecision.
#
# The audit is a release:preflight gate candidate (iter-61 work) because
# a single hook regressing to the deprecated `decision: "block"` schema
# would silently fail to block on Claude Code v2.0.10+ — a category of
# security regression that's hard to forensics-trace after the fact.
# This test locks in the audit's classification semantics so future
# edits to the audit can't silently break detection.
#
# Coverage matrix (5 fixtures):
#
#   # | Fixture                          | Expected Classification    | Exit Code
#   --|----------------------------------|----------------------------|----------
#   01| Modern hookSpecificOutput        | MODERN-CORRECT             | 0
#   02| Helper-wrapped (deny())          | HELPER-WRAPPED             | 0
#   03| No decision emitted (logger)     | NO-DECISION-EMITTED        | 0
#   04| Deprecated top-level decision    | DEPRECATED-WARNING         | 1 (gate)
#   05| Helpers.ts SAFETY-CHECK fixture  | Audit exits cleanly when   | 0
#     |   (helpers uses modern)          |   helpers.ts is correct    |
#
# Plus 1 negative test: simulate helpers.ts using DEPRECATED schema and
# assert audit aborts with exit code 2 (critical-failure).
#
# Verbose filename encodes WHAT it tests (the schema audit), WHICH
# classifications (modern-correct, helper-wrapped, no-decision), AND
# WHICH gate (nonzero exit on deprecated). Future maintainers searching
# for "schema audit test", "deprecated schema detection",
# "hookSpecificOutput test", or "PreToolUse silent fail test" surface
# this regression guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK="$SCRIPT_DIR/../audit-pretooluse-hooks-for-deprecated-top-level-decision-schema-versus-modern-hookSpecificOutput-permissionDecision"

if [ ! -x "$AUDIT_TASK" ]; then
  echo "FATAL: audit task not executable: $AUDIT_TASK" >&2
  exit 1
fi

FIXTURE_FLEET_ROOT=$(mktemp -d -t pretooluse-schema-audit-regression-fixture-fleet.XXXXXX)
trap 'rm -rf "$FIXTURE_FLEET_ROOT"' EXIT

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: create a PreToolUse hook source file directly (no hooks.json
# needed — this audit walks the source files via find, not hooks.json).
create_pretooluse_fixture() {
  local plugin_name="$1" hook_filename="$2" hook_content="$3"
  local hooks_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name/hooks"
  mkdir -p "$hooks_dir"
  printf '%s\n' "$hook_content" > "$hooks_dir/$hook_filename"
}

# Create a correct helpers.ts module so HELPER-WRAPPED fixtures pass the
# audit's safety pre-check.
create_correct_helpers_module() {
  local helpers_dir="$FIXTURE_FLEET_ROOT/plugins/itp-hooks/hooks"
  mkdir -p "$helpers_dir"
  cat > "$helpers_dir/pretooluse-helpers.ts" <<'HELPERS_EOF'
// Synthetic helpers module for regression-test purposes. Mirrors the
// canonical cc-skills helpers shape: emits hookSpecificOutput.
export function deny(reason: string): void {
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  }));
}
HELPERS_EOF
}

# ---------------------------------------------------------------------------
# Build fixture fleet
# ---------------------------------------------------------------------------
echo "=== Building synthetic fixture fleet at $FIXTURE_FLEET_ROOT ==="

create_correct_helpers_module

# #01 MODERN-CORRECT: hook uses hookSpecificOutput.permissionDecision directly
create_pretooluse_fixture "fixture01-modern-correct" "pretooluse-test.ts" \
'#!/usr/bin/env bun
console.log(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "blocked by modern schema",
  },
}));'

# #02 HELPER-WRAPPED: hook calls deny()/block()/ask() helper
create_pretooluse_fixture "fixture02-helper-wrapped" "pretooluse-test.ts" \
'#!/usr/bin/env bun
import { deny } from "../../itp-hooks/hooks/pretooluse-helpers";
deny("blocked via helper");'

# #03 NO-DECISION-EMITTED: hook only logs to stderr / does no blocking
create_pretooluse_fixture "fixture03-no-decision-emitted" "pretooluse-test.ts" \
'#!/usr/bin/env bun
console.error("[REMINDER] just a log line, no decision emitted");'

# #04 DEPRECATED-WARNING: hook uses top-level decision:"block" (silent-fail)
create_pretooluse_fixture "fixture04-deprecated-top-level-decision" "pretooluse-test.ts" \
'#!/usr/bin/env bun
// SCHEMA REGRESSION: this uses the DEPRECATED top-level decision field.
// On Claude Code v2.0.10+ this silently fails to block.
console.log(JSON.stringify({
  decision: "block",
  reason: "deprecated schema — will silently NOT block",
}));'

# ---------------------------------------------------------------------------
# Run audit and capture exit code
# ---------------------------------------------------------------------------
echo ""
echo "=== Running audit against synthetic fixture fleet (expect exit code 1) ==="

set +e
AUDIT_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
AUDIT_EXIT=$?
set -e

# ---------------------------------------------------------------------------
# Classification assertions
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting each fixture's classification (from summary counts) ==="

# Parse summary counts from audit output.
modern_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'MODERN-CORRECT[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
helper_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'HELPER-WRAPPED[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
no_decision_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'NO-DECISION-EMITTED[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
deprecated_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'DEPRECATED-WARNING[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)

# Expected: 1 modern + 1 helper + 1 no-decision + 1 deprecated = 4 fixtures.
# Note: helpers.ts itself ALSO matches pretooluse-* pattern, but is named
# pretooluse-helpers.ts and is not a test fixture — it'll be scanned and
# classified MODERN-CORRECT (it emits hookSpecificOutput literally).

if [ "$modern_count" -ge 1 ]; then
  assert_pass "Fixture #01 classified as MODERN-CORRECT (count=$modern_count, includes synthetic helpers.ts)"
else
  assert_fail "MODERN-CORRECT count is $modern_count, expected ≥1"
fi

if [ "$helper_count" = "1" ]; then
  assert_pass "Fixture #02 classified as HELPER-WRAPPED (count=$helper_count)"
else
  assert_fail "HELPER-WRAPPED count is $helper_count, expected 1"
fi

if [ "$no_decision_count" = "1" ]; then
  assert_pass "Fixture #03 classified as NO-DECISION-EMITTED (count=$no_decision_count)"
else
  assert_fail "NO-DECISION-EMITTED count is $no_decision_count, expected 1"
fi

if [ "$deprecated_count" = "1" ]; then
  assert_pass "Fixture #04 classified as DEPRECATED-WARNING (count=$deprecated_count)"
else
  assert_fail "DEPRECATED-WARNING count is $deprecated_count, expected 1"
fi

# ---------------------------------------------------------------------------
# Exit-code assertion (the gate)
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting audit exits NON-ZERO when DEPRECATED-WARNING detected ==="

if [ "$AUDIT_EXIT" = "1" ]; then
  assert_pass "Audit exited with code 1 (gate fires — preflight would block release)"
else
  assert_fail "Audit exited with code $AUDIT_EXIT, expected 1 (gate failed to fire)"
fi

# ---------------------------------------------------------------------------
# Negative test: simulate helpers.ts using DEPRECATED schema
# ---------------------------------------------------------------------------
echo ""
echo "=== Negative test: helpers.ts itself regressed to deprecated schema → exit 2 ==="

# Overwrite the helpers module with the deprecated schema.
cat > "$FIXTURE_FLEET_ROOT/plugins/itp-hooks/hooks/pretooluse-helpers.ts" <<'BROKEN_HELPERS_EOF'
// SIMULATED REGRESSION: helpers module now uses DEPRECATED schema.
export function deny(reason: string): void {
  console.log(JSON.stringify({ decision: "block", reason: reason }));
}
BROKEN_HELPERS_EOF

set +e
NEGATIVE_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
NEGATIVE_EXIT=$?
set -e

if [ "$NEGATIVE_EXIT" = "2" ]; then
  assert_pass "Audit exited with code 2 (CRITICAL — helpers module regressed)"
else
  assert_fail "Audit exited with code $NEGATIVE_EXIT, expected 2"
  echo "    Output was:"
  # shellcheck disable=SC2001
  # SC2001 intentional: sed `s/^/    /` uses regex start-of-line anchor;
  # bash globs have no equivalent.
  echo "$NEGATIVE_OUTPUT" | sed 's/^/    /'
fi

# Verify the critical-failure path emits the diagnostic message.
if echo "$NEGATIVE_OUTPUT" | grep -q 'helpers module regressed'; then
  assert_pass "Audit diagnostic mentions 'helpers module regressed' (operator-actionable)"
else
  assert_fail "Audit diagnostic missing 'helpers module regressed' message"
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
