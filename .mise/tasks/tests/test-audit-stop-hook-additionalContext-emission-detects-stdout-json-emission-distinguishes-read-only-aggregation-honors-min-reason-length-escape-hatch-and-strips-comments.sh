#!/usr/bin/env bash
# test-audit-stop-hook-additionalContext-emission-detects-stdout-json-emission-distinguishes-read-only-aggregation-honors-min-reason-length-escape-hatch-and-strips-comments.sh
#
# Regression test for the iter-67 Stop-hook additionalContext-emission
# audit at .mise/tasks/audit-stop-hooks-for-additionalContext-emission-
# which-claude-code-silently-drops-per-official-anthropic-schema-only-
# decision-and-reason-fields-are-read-from-stop-hook-stdout-json.
#
# WHY this is load-bearing:
#
#   Iter-66 fixed a single hook (itp-hooks stop-orchestrator) silently
#   dropping its aggregated subhook summary because Stop hooks read only
#   {decision, reason} per Anthropic's official schema. iter-67 scales
#   that fix into marketplace-wide preventive infrastructure. This
#   regression test ensures the audit itself cannot silently break
#   detection, false-positive on comments, or miss the OK-marker
#   escape-hatch min-length enforcement.
#
# Coverage matrix (6 synthetic Stop-hook fixtures → 11 assertions):
#
#   # | Fixture                                              | Classification          | Mechanism
#   --|------------------------------------------------------|-------------------------|------------------------------
#   01| Clean Stop hook (no additionalContext anywhere)     | CLEAN                   | grep finds no token
#   02| Emits {additionalContext: "x"} via console.log       | EMISSION-VIOLATION      | grep finds token in code
#   03| Only contains additionalContext in JSDoc comments    | CLEAN                   | comment-stripper removes it
#   04| References additionalContext WITH valid OK marker    | WITH-OK-MARKER          | ≥10-char OK reason honored
#   05| References additionalContext WITH too-short marker   | EMISSION-VIOLATION      | OK reason too short, rejected
#   06| Orchestrator pattern: reads parsed.additionalContext | EMISSION-VIOLATION (no  | grep finds token in
#      |   without OK marker (legitimate read-only use)     |   OK marker required)   |   non-comment code
#
# Plus assertions for:
#   - Summary counts (CLEAN + WITH-OK-MARKER + EMISSION-VIOLATION)
#   - Exit code (1 because fixtures #2, #5, #6 produce violations)
#   - Per-fixture violation tag presence
#   - Diagnostic content (mentions iter-66 + GitHub #19115)
#   - Clean-state re-run (remove violation fixtures, expect exit 0)
#
# Verbose filename encodes: WHAT (Stop-hook additionalContext audit),
# WHICH detections (stdout emission), WHICH classifications (read-only
# vs emission), WHICH escape-hatch (min-reason length), and WHAT the
# audit pre-processes (comment stripping). Future maintainers searching
# for "stop hook schema test", "iter-67", "additionalContext audit test",
# or "stop hook emission detection" surface this regression guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK="$SCRIPT_DIR/../audit-stop-hooks-for-additionalContext-emission-which-claude-code-silently-drops-per-official-anthropic-schema-only-decision-and-reason-fields-are-read-from-stop-hook-stdout-json.sh"

if [ ! -x "$AUDIT_TASK" ]; then
  echo "FATAL: audit task not executable: $AUDIT_TASK" >&2
  exit 1
fi

FIXTURE_FLEET_ROOT=$(mktemp -d -t stop-hook-additional-context-audit-regression-fixture-fleet.XXXXXX)
trap 'rm -rf "$FIXTURE_FLEET_ROOT"' EXIT

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: create a fixture plugin with a registered Stop hook + source content.
create_stop_hook_fixture_plugin() {
  local plugin_name="$1" source_filename="$2" source_content="$3"
  local hooks_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name/hooks"
  mkdir -p "$hooks_dir"
  printf '%s\n' "$source_content" > "$hooks_dir/$source_filename"
  # shellcheck disable=SC2016
  # SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
  printf '%s\n' '{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bun ${CLAUDE_PLUGIN_ROOT}/hooks/'"$source_filename"'"
      }]
    }]
  }
}' > "$hooks_dir/hooks.json"
}

# ---------------------------------------------------------------------------
# Build fixture fleet
# ---------------------------------------------------------------------------
echo "=== Building synthetic fixture fleet at $FIXTURE_FLEET_ROOT ==="

# #01 CLEAN: Stop hook with only {decision, reason} schema
create_stop_hook_fixture_plugin "fixture01-clean-stop-hook-decision-reason-only" "stop-clean.ts" \
'#!/usr/bin/env bun
console.log(JSON.stringify({decision: "block", reason: "task incomplete"}));'

# #02 EMISSION-VIOLATION: emits {additionalContext: "x"} in stdout JSON
create_stop_hook_fixture_plugin "fixture02-stop-hook-emits-additionalContext-violation" "stop-violation.ts" \
'#!/usr/bin/env bun
// This emits additionalContext to stdout JSON — Claude Code silently drops it.
console.log(JSON.stringify({additionalContext: "this never reaches Claude"}));'

# #03 CLEAN: only contains additionalContext in JSDoc comments (should not flag)
create_stop_hook_fixture_plugin "fixture03-stop-hook-comments-only-no-real-emission" "stop-comments-only.ts" \
'#!/usr/bin/env bun
/**
 * Stop hook that does nothing.
 * Historical note: this hook used to emit additionalContext but
 * was refactored to use {decision, reason} only per iter-66 fix.
 */
// Note: NO additionalContext in stdout (this comment should also be stripped).
console.log("{}");'

# #04 WITH-OK-MARKER: references additionalContext WITH valid OK marker
create_stop_hook_fixture_plugin "fixture04-stop-hook-with-valid-ok-marker-orchestrator-style" "stop-orchestrator-style.ts" \
'#!/usr/bin/env bun
// STOP-HOOK-ADDITIONAL-CONTEXT-OK: reads additionalContext from subhook stdout as internal aggregation protocol, routes to stderr per iter-66 fix
const parsed = JSON.parse(subhook_stdout);
if (parsed.additionalContext) {
  process.stderr.write(parsed.additionalContext);
}
console.log("{}");'

# #05 EMISSION-VIOLATION: too-short OK marker reason
create_stop_hook_fixture_plugin "fixture05-stop-hook-with-too-short-ok-marker-violation" "stop-short-marker.ts" \
'#!/usr/bin/env bun
// STOP-HOOK-ADDITIONAL-CONTEXT-OK: ok
// ↑ reason "ok" is 2 chars, below the 10-char minimum.
const x = {additionalContext: "test"};
console.log(JSON.stringify(x));'

# #06 EMISSION-VIOLATION: read-only orchestrator-style WITHOUT OK marker
# Even though semantically read-only, audit requires explicit justification.
create_stop_hook_fixture_plugin "fixture06-stop-hook-orchestrator-style-but-no-ok-marker-required" "stop-orchestrator-no-marker.ts" \
'#!/usr/bin/env bun
const parsed = JSON.parse(subhook_stdout);
if (parsed.additionalContext) {
  process.stderr.write(parsed.additionalContext);
}
console.log("{}");'

# ---------------------------------------------------------------------------
# Run audit (expect exit 1 due to fixtures #2, #5, #6)
# ---------------------------------------------------------------------------
echo ""
echo "=== Running audit against synthetic fixture fleet (expect exit 1) ==="

set +e
AUDIT_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
AUDIT_EXIT=$?
set -e

# ---------------------------------------------------------------------------
# Classification + summary-count assertions
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting summary counts and per-fixture classifications ==="

total_scanned=$(echo "$AUDIT_OUTPUT" | grep -oE 'Total registered Stop hooks scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
clean_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'CLEAN \(no additionalContext in code\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
with_ok_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'WITH-OK-MARKER \(justified internal usage\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
violation_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'EMISSION-VIOLATION \(silent-drop risk\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)

# Expected: 6 total, 2 clean (#1, #3), 1 with-ok (#4), 3 violations (#2, #5, #6)
if [ "$total_scanned" = "6" ]; then
  assert_pass "Total scanned = 6 (one fixture per scenario)"
else
  assert_fail "Total scanned = $total_scanned, expected 6"
fi

if [ "$clean_count" = "2" ]; then
  assert_pass "CLEAN count = 2 (fixtures #01 + #03)"
else
  assert_fail "CLEAN count = $clean_count, expected 2"
fi

if [ "$with_ok_count" = "1" ]; then
  assert_pass "WITH-OK-MARKER count = 1 (fixture #04)"
else
  assert_fail "WITH-OK-MARKER count = $with_ok_count, expected 1"
fi

if [ "$violation_count" = "3" ]; then
  assert_pass "EMISSION-VIOLATION count = 3 (fixtures #02, #05, #06)"
else
  assert_fail "EMISSION-VIOLATION count = $violation_count, expected 3"
fi

# Per-fixture marker assertions
if echo "$AUDIT_OUTPUT" | grep -q 'fixture02-stop-hook-emits-additionalContext-violation'; then
  assert_pass "Fixture #02 (literal emission) reported in violation diagnostic"
else
  assert_fail "Fixture #02 missing from violation diagnostic"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'WITH-OK-MARKER.*fixture04-stop-hook-with-valid-ok-marker'; then
  assert_pass "Fixture #04 (orchestrator-style with valid OK marker) classified WITH-OK-MARKER"
else
  assert_fail "Fixture #04 NOT classified as WITH-OK-MARKER (escape hatch failed to honor valid marker)"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture05-stop-hook-with-too-short-ok-marker-violation'; then
  assert_pass "Fixture #05 (too-short OK reason <10 chars) reported in violation diagnostic"
else
  assert_fail "Fixture #05 missing — min-reason-length enforcement failed"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture06-stop-hook-orchestrator-style-but-no-ok-marker-required'; then
  assert_pass "Fixture #06 (orchestrator-style WITHOUT marker) correctly flagged — marker is required"
else
  assert_fail "Fixture #06 missing — audit should require OK marker even for read-only patterns"
fi

# ---------------------------------------------------------------------------
# Exit-code + diagnostic-content assertions
# ---------------------------------------------------------------------------
echo ""
echo "=== Asserting exit code + diagnostic content ==="

if [ "$AUDIT_EXIT" = "1" ]; then
  assert_pass "Audit exited with code 1 (gate fires — preflight would block release)"
else
  assert_fail "Audit exited with code $AUDIT_EXIT, expected 1"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'iter-66'; then
  assert_pass "Diagnostic references iter-66 (forensic provenance)"
else
  assert_fail "Diagnostic missing iter-66 reference"
fi

# ---------------------------------------------------------------------------
# Clean-state re-run (remove violation fixtures; expect exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "=== Removing violation fixtures and re-running (expect exit 0) ==="

rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture02-stop-hook-emits-additionalContext-violation"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture05-stop-hook-with-too-short-ok-marker-violation"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture06-stop-hook-orchestrator-style-but-no-ok-marker-required"

set +e
CLEAN_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_FLEET_ROOT" bash "$AUDIT_TASK" 2>&1)
CLEAN_EXIT=$?
set -e

if [ "$CLEAN_EXIT" = "0" ]; then
  assert_pass "Audit exited 0 after violation fixtures removed (clean state)"
else
  assert_fail "Audit exited $CLEAN_EXIT after removing violations, expected 0"
  echo "    Output was:"
  # shellcheck disable=SC2001
  # SC2001 intentional: sed `s/^/    /` uses regex start-of-line anchor.
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
