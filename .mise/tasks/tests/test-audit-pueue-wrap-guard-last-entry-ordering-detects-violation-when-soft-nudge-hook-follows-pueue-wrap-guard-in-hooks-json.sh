#!/usr/bin/env bash
# test-audit-pueue-wrap-guard-last-entry-ordering-detects-violation-when-soft-nudge-hook-follows-pueue-wrap-guard-in-hooks-json.sh
#
# Regression test for the iter-61 pueue-wrap-guard ordering audit at
# .mise/tasks/audit-pretooluse-pueue-wrap-guard-is-last-pretooluse-
# entry-in-hooks-json-to-mitigate-github-15897-multi-hook-
# updatedInput-aggregation-last-writer-wins-bug.
#
# WHY this is load-bearing:
#
#   Iter-61 forensic check found the documented invariant violated in
#   the live cc-skills repo: pretooluse-parquet-duckdb-nudge.ts was
#   ordered AFTER pretooluse-pueue-wrap-guard.ts in itp-hooks/hooks/
#   hooks.json. Per GitHub #15897 (multi-hook updatedInput aggregation
#   last-writer-wins bug), this would silently clobber the OP_SERVICE_
#   ACCOUNT_TOKEN injection and pueue command-wrapping mutations on
#   EVERY Bash tool invocation — a security-sensitive silent failure.
#
#   The audit is now release:preflight Check 4g (iter-61 wire-up).
#   Without regression coverage, a future ordering change could
#   silently break detection or the audit itself could regress.
#
# Coverage matrix (4 fixtures):
#
#   # | Fixture                                  | Expected Classification    | Exit Code
#   --|------------------------------------------|----------------------------|----------
#   01| pueue-wrap-guard IS last entry           | ORDERING-OK                | 0
#   02| Soft-nudge hook AFTER pueue-wrap-guard   | ORDERING-VIOLATION         | 1 (gate)
#   03| No pueue-wrap-guard registered           | Skip (informational only)  | 0
#   04| Multi-command hook-group, last cmd is    | ORDERING-OK                | 0
#     |   pueue-wrap-guard                       |                            |
#
# Plus exit-code assertions and diagnostic-message-content assertions.
#
# Verbose filename encodes WHAT it tests (ordering audit), WHICH
# specific failure mode (soft-nudge-after-wrap-guard), and WHERE the
# regression would manifest (hooks.json). Future maintainers searching
# for "pueue-wrap-guard ordering test", "GitHub 15897 test",
# "multi-hook aggregation test", or "PreToolUse last-entry test"
# surface this regression guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK="$SCRIPT_DIR/../audit-pretooluse-pueue-wrap-guard-is-last-pretooluse-entry-in-hooks-json-to-mitigate-github-15897-multi-hook-updatedInput-aggregation-last-writer-wins-bug.sh"

if [ ! -x "$AUDIT_TASK" ]; then
  echo "FATAL: audit task not executable: $AUDIT_TASK" >&2
  exit 1
fi

FIXTURE_FLEET_ROOT=$(mktemp -d -t pueue-wrap-guard-ordering-audit-regression-fixture-fleet.XXXXXX)
trap 'rm -rf "$FIXTURE_FLEET_ROOT"' EXIT

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: create a fixture plugin with a specific hooks.json layout.
create_fixture_with_hooks_json() {
  local plugin_name="$1" hooks_json_content="$2"
  local hooks_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name/hooks"
  mkdir -p "$hooks_dir"
  printf '%s\n' "$hooks_json_content" > "$hooks_dir/hooks.json"
  # Also create the referenced source files so the audit's grep -l
  # (which checks if the file mentions pueue-wrap-guard) works correctly.
  touch "$hooks_dir/pretooluse-pueue-wrap-guard.ts"
  touch "$hooks_dir/pretooluse-parquet-duckdb-nudge.ts"
  touch "$hooks_dir/pretooluse-subprocess-stdin-inlet-guard.ts"
}

# ---------------------------------------------------------------------------
# Build fixture fleet
# ---------------------------------------------------------------------------
echo "=== Building synthetic fixture fleet at $FIXTURE_FLEET_ROOT ==="

# #01 ORDERING-OK: pueue-wrap-guard IS the last PreToolUse entry
# shellcheck disable=SC2016
# SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must be LITERAL in the JSON
# payload — Claude Code substitutes it at hook-invocation time. Single
# quotes prevent bash expansion so the literal token reaches hooks.json.
create_fixture_with_hooks_json "fixture01-ordering-ok-pueue-wrap-guard-is-last" '{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-subprocess-stdin-inlet-guard.ts"}]
      },
      {
        "matcher": "Bash",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-pueue-wrap-guard.ts"}]
      }
    ]
  }
}'

# #02 ORDERING-VIOLATION: parquet-duckdb-nudge AFTER pueue-wrap-guard (the
# real bug iter-61 found in production)
# shellcheck disable=SC2016
# SC2016 intentional (see fixture #01 comment): ${CLAUDE_PLUGIN_ROOT} is
# the runtime placeholder Claude Code substitutes; must reach hooks.json
# unexpanded.
create_fixture_with_hooks_json "fixture02-ordering-violation-soft-nudge-follows-wrap-guard" '{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-subprocess-stdin-inlet-guard.ts"}]
      },
      {
        "matcher": "Bash",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-pueue-wrap-guard.ts"}]
      },
      {
        "matcher": "Bash",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-parquet-duckdb-nudge.ts"}]
      }
    ]
  }
}'

# #03 Skip case: no pueue-wrap-guard at all (audit should ignore this plugin)
mkdir -p "$FIXTURE_FLEET_ROOT/plugins/fixture03-no-pueue-wrap-guard-registered/hooks"
cat > "$FIXTURE_FLEET_ROOT/plugins/fixture03-no-pueue-wrap-guard-registered/hooks/hooks.json" <<'JSON_EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-some-other-guard.ts"}]
      }
    ]
  }
}
JSON_EOF

# #04 ORDERING-OK with multi-command hook-group — defensive coverage of
# the edge where a single hook-group has multiple commands and the LAST
# command of the LAST group must be pueue-wrap-guard.
# shellcheck disable=SC2016
# SC2016 intentional (see fixture #01 comment): ${CLAUDE_PLUGIN_ROOT} is
# the runtime placeholder Claude Code substitutes; must reach hooks.json
# unexpanded.
create_fixture_with_hooks_json "fixture04-ordering-ok-multi-cmd-group-last-cmd-is-wrap-guard" '{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-subprocess-stdin-inlet-guard.ts"}]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-some-other-bash-guard.ts"},
          {"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-pueue-wrap-guard.ts"}
        ]
      }
    ]
  }
}'

# ---------------------------------------------------------------------------
# Run audit (expect exit 1 due to fixture #2)
# ---------------------------------------------------------------------------
echo ""
echo "=== Running audit against synthetic fixture fleet (expect exit 1) ==="

set +e
AUDIT_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
AUDIT_EXIT=$?
set -e

# ---------------------------------------------------------------------------
# Classification assertions (from summary counts + per-line markers)
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting each fixture lands in correct classification ==="

# Parse summary counts.
scanned=$(echo "$AUDIT_OUTPUT" | grep -oE 'Total hooks.json files scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
with_wrap_guard=$(echo "$AUDIT_OUTPUT" | grep -oE 'Files registering pueue-wrap-guard.ts:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
ok_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'ORDERING-OK \(pueue-wrap-guard is LAST\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
violation_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'ORDERING-VIOLATION \(pueue-wrap-guard NOT LAST\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)

# Expected: 4 total scanned (one hooks.json per fixture), 3 register
# wrap-guard (fixtures 1, 2, 4), 2 ok (fixtures 1, 4), 1 violation (#2).
if [ "$scanned" = "4" ]; then
  assert_pass "Total scanned = 4 (one hooks.json per fixture)"
else
  assert_fail "Total scanned = $scanned, expected 4"
fi

if [ "$with_wrap_guard" = "3" ]; then
  assert_pass "Files registering wrap-guard = 3 (fixtures #1, #2, #4 — #3 is skipped)"
else
  assert_fail "Files registering wrap-guard = $with_wrap_guard, expected 3"
fi

if [ "$ok_count" = "2" ]; then
  assert_pass "ORDERING-OK count = 2 (fixtures #1 and #4)"
else
  assert_fail "ORDERING-OK count = $ok_count, expected 2"
fi

if [ "$violation_count" = "1" ]; then
  assert_pass "ORDERING-VIOLATION count = 1 (fixture #2)"
else
  assert_fail "ORDERING-VIOLATION count = $violation_count, expected 1"
fi

# Per-fixture marker assertions.
if echo "$AUDIT_OUTPUT" | grep -q 'fixture01-ordering-ok-pueue-wrap-guard-is-last.*LAST PreToolUse entry'; then
  assert_pass "Fixture #01 marked as ORDERING-OK (LAST PreToolUse entry)"
else
  assert_fail "Fixture #01 not marked as ORDERING-OK"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture02-ordering-violation-soft-nudge-follows-wrap-guard'; then
  if echo "$AUDIT_OUTPUT" | grep -q 'parquet-duckdb-nudge'; then
    assert_pass "Fixture #02 violation diagnostic mentions parquet-duckdb-nudge (the offending hook)"
  else
    assert_fail "Fixture #02 violation diagnostic missing 'parquet-duckdb-nudge' offender name"
  fi
else
  assert_fail "Fixture #02 missing from violation diagnostic section"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture04-ordering-ok-multi-cmd-group-last-cmd-is-wrap-guard.*LAST PreToolUse entry'; then
  assert_pass "Fixture #04 (multi-cmd group) marked as ORDERING-OK"
else
  assert_fail "Fixture #04 (multi-cmd group) not marked as ORDERING-OK"
fi

# ---------------------------------------------------------------------------
# Exit-code assertion (the gate)
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting audit exits NON-ZERO when ORDERING-VIOLATION detected ==="

if [ "$AUDIT_EXIT" = "1" ]; then
  assert_pass "Audit exited with code 1 (gate fires — preflight would block release)"
else
  assert_fail "Audit exited with code $AUDIT_EXIT, expected 1"
fi

# ---------------------------------------------------------------------------
# Diagnostic message content (operator-actionable guidance)
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting violation diagnostic contains operator-actionable guidance ==="

if echo "$AUDIT_OUTPUT" | grep -q 'GitHub #15897'; then
  assert_pass "Diagnostic references GitHub #15897 (the underlying bug)"
else
  assert_fail "Diagnostic missing GitHub #15897 reference"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'Full PreToolUse ordering'; then
  assert_pass "Diagnostic includes 'Full PreToolUse ordering' table for forensics"
else
  assert_fail "Diagnostic missing 'Full PreToolUse ordering' table"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'OP token injection'; then
  assert_pass "Diagnostic mentions OP token injection (load-bearing mutation #1)"
else
  assert_fail "Diagnostic missing OP token injection mention"
fi

# ---------------------------------------------------------------------------
# Positive-only run (rebuild fleet without violation fixture; expect exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "=== Removing violation fixture and re-running (expect exit 0) ==="

rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture02-ordering-violation-soft-nudge-follows-wrap-guard"

set +e
CLEAN_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
CLEAN_EXIT=$?
set -e

if [ "$CLEAN_EXIT" = "0" ]; then
  assert_pass "Audit exited with code 0 after violation fixture removed (clean state)"
else
  assert_fail "Audit exited with code $CLEAN_EXIT after violation removed, expected 0"
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
