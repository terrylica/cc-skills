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
# Coverage matrix (10 synthetic pentad-member-hook fixtures → 22 assertions):
#
#   # | Fixture                                                   | Event type     | Classification          | Mechanism
#   --|-----------------------------------------------------------|----------------|-------------------------|------------------------------
#   01| Clean Stop hook (no additionalContext anywhere)          | Stop           | CLEAN                   | grep finds no token
#   02| Emits {additionalContext: "x"} via console.log            | Stop           | EMISSION-VIOLATION      | grep finds token in code
#   03| Only contains additionalContext in JSDoc comments         | Stop           | CLEAN                   | comment-stripper removes it
#   04| References additionalContext WITH valid OK marker         | Stop           | WITH-OK-MARKER          | ≥10-char OK reason honored
#   05| References additionalContext WITH too-short marker        | Stop           | EMISSION-VIOLATION      | OK reason too short, rejected
#   06| Orchestrator pattern: reads parsed.additionalContext      | Stop           | EMISSION-VIOLATION      | grep finds token in
#      |   without OK marker (legitimate read-only use)          |                | (no OK marker required) | non-comment code
#   07| SubagentStop emits {additionalContext: "x"}               | SubagentStop   | EMISSION-VIOLATION      | iter-68 scope expansion catches
#      |   (iter-68 expansion)                                    |                |                         | same-schema-as-Stop violation
#   08| SessionEnd emits {additionalContext: "x"}                 | SessionEnd     | EMISSION-VIOLATION      | iter-68 scope expansion catches
#      |   (iter-68 expansion — different schema rule:           |                |                         | empty-output-schema violation;
#      |    SessionEndOK returns EMPTY output, no fields read)   |                |                         | diagnostic differentiated
#   09| PreCompact emits {additionalContext: "x"}                 | PreCompact     | EMISSION-VIOLATION      | iter-69 pentad expansion catches
#      |   (iter-69 expansion — same schema rule as Stop:        |                |                         | Stop-family schema violation;
#      |    {decision:'block', reason} only)                     |                |                         | case-statement Stop|SubagentStop|PreCompact branch
#   10| Notification emits {additionalContext: "x"}               | Notification   | EMISSION-VIOLATION      | iter-69 pentad expansion catches
#      |   (iter-69 expansion — DIFFERENT schema rule:           |                |                         | no-decision-capability violation;
#      |    purely informational, no decision/blocking; only     |                |                         | dedicated case-statement
#      |    stderr on exit 2 reaches user)                       |                |                         | Notification branch
#
# Plus assertions for:
#   - Summary counts (CLEAN=2 + WITH-OK-MARKER=1 + EMISSION-VIOLATION=7; Total=10)
#   - Per-event-type breakdown (iter-68 feature: Stop 6/3 + SubagentStop 1/1
#     + SessionEnd 1/1 + PreCompact 1/1 + Notification 1/1 — verifies the
#     audit attributes scans+violations correctly per event type)
#   - SessionEnd-specific schema diagnostic mentions "SessionEndOK returns
#     EMPTY output" (NOT the {decision, reason} rule that applies to
#     Stop/SubagentStop/PreCompact) — verifies the case-statement schema
#     branch works
#   - PreCompact-specific schema diagnostic mentions "Per official Anthropic
#     PreCompact-hook schema" — verifies case-statement Stop-family branch
#     emits the correct event-type interpolation
#   - Notification-specific schema diagnostic mentions "Exit Code 2 Behavior:
#     N/A" — verifies dedicated case-statement Notification branch emits the
#     no-decision-capability rule
#   - Exit code (1 because fixtures #2, #5, #6, #7, #8, #9, #10 produce violations)
#   - Per-fixture violation tag presence (#02, #04, #05, #06, #07, #08, #09, #10)
#   - Diagnostic content (mentions iter-66 + GitHub #19115)
#   - Clean-state re-run (remove all 7 violation fixtures, expect exit 0)
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

# Helper: create a fixture plugin with a registered event-terminal hook
# + source content. Event type defaults to "Stop" for backward compat with
# iter-67 fixtures (#01-#06); iter-68 fixtures (#07-#08) pass "SubagentStop"
# or "SessionEnd" to exercise the expanded scope.
create_event_terminal_hook_fixture_plugin() {
  local plugin_name="$1" source_filename="$2" source_content="$3" event_type="${4:-Stop}"
  local hooks_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name/hooks"
  mkdir -p "$hooks_dir"
  printf '%s\n' "$source_content" > "$hooks_dir/$source_filename"
  # shellcheck disable=SC2016
  # SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
  printf '%s\n' '{
  "hooks": {
    "'"$event_type"'": [{
      "hooks": [{
        "type": "command",
        "command": "bun ${CLAUDE_PLUGIN_ROOT}/hooks/'"$source_filename"'"
      }]
    }]
  }
}' > "$hooks_dir/hooks.json"
}

# Backward-compatible alias for iter-67 fixtures (#01-#06) — they all use
# event_type "Stop" implicitly. Keeping the historical name avoids touching
# every existing fixture call site.
create_stop_hook_fixture_plugin() {
  create_event_terminal_hook_fixture_plugin "$1" "$2" "$3" "Stop"
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
# Iter-68 expansion fixtures: SubagentStop + SessionEnd silent-drop coverage
# ---------------------------------------------------------------------------
# Iter-67 scanned only Stop hooks. Iter-68 extended scope to the full
# "additionalContext-silently-dropped" event-type trinity. Fixtures #07-#08
# prove the expansion actually catches violations on the new event types
# AND that the per-event-type breakdown attributes each violation correctly.

# #07 EMISSION-VIOLATION (SubagentStop): SubagentStop hook emitting
# additionalContext. Schema rule is the same as Stop (only {decision,
# reason} read), so this should be flagged with a Stop-family diagnostic.
create_event_terminal_hook_fixture_plugin "fixture07-subagentstop-hook-emits-additionalContext-violation" "subagentstop-violation.ts" \
'#!/usr/bin/env bun
// SubagentStop schema is same as Stop — additionalContext silently dropped.
console.log(JSON.stringify({additionalContext: "subagent summary never reaches Claude"}));' \
"SubagentStop"

# #08 EMISSION-VIOLATION (SessionEnd): SessionEnd hook emitting
# additionalContext. Schema rule is DIFFERENT — SessionEnd has empty
# output (per Go type defs in CorridorSecurity/hookshot). Audit should
# emit a SessionEnd-specific diagnostic mentioning the empty-output rule.
create_event_terminal_hook_fixture_plugin "fixture08-sessionend-hook-emits-additionalContext-violation" "sessionend-violation.ts" \
'#!/usr/bin/env bun
// SessionEnd schema reads NOTHING — session is terminating, nothing
// can be injected. Any output field, including additionalContext, is
// silently dropped.
console.log(JSON.stringify({additionalContext: "end-of-session summary never reaches anyone"}));' \
"SessionEnd"

# ---------------------------------------------------------------------------
# Iter-69 pentad-completion fixtures: PreCompact + Notification coverage
# ---------------------------------------------------------------------------
# Iter-68 trinity covered Stop/SubagentStop/SessionEnd. Iter-69 completes
# the additionalContext-silently-dropped pentad by adding PreCompact and
# Notification. Fixtures #09-#10 prove the pentad expansion catches
# violations on the two new event types AND that the case-statement
# diagnostic emits the schema-rule-specific text per event family
# (PreCompact: Stop-family rule; Notification: no-decision rule).

# #09 EMISSION-VIOLATION (PreCompact): PreCompact hook emitting
# additionalContext. Schema rule is the SAME as Stop (only {decision:'block',
# reason} read per official Anthropic docs). Audit should emit Stop-family
# diagnostic ("uses the same decision-control format as Stop").
create_event_terminal_hook_fixture_plugin "fixture09-precompact-hook-emits-additionalContext-violation" "precompact-violation.ts" \
'#!/usr/bin/env bun
// PreCompact schema = {decision:"block", reason} only — additionalContext
// silently dropped (PreCompact fires just before conversation compaction).
console.log(JSON.stringify({additionalContext: "pre-compaction summary never reaches Claude"}));' \
"PreCompact"

# #10 EMISSION-VIOLATION (Notification): Notification hook emitting
# additionalContext. Schema rule is DIFFERENT from all others — Notification
# has NO decision capability at all (purely informational, exit-2 stderr
# only per official Anthropic docs). Audit should emit Notification-specific
# diagnostic mentioning "Exit Code 2 Behavior: N/A".
create_event_terminal_hook_fixture_plugin "fixture10-notification-hook-emits-additionalContext-violation" "notification-violation.ts" \
'#!/usr/bin/env bun
// Notification schema: purely informational, no decision capability.
// Subtypes: permission_prompt, idle_prompt, auth_success. Any output
// field including additionalContext silently dropped — only stderr on
// exit 2 reaches user.
console.log(JSON.stringify({additionalContext: "notification context never injected anywhere"}));' \
"Notification"

# ---------------------------------------------------------------------------
# Run audit (expect exit 1 due to fixtures #02 #05 #06 #07 #08 #09 #10 = 7)
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

# Loose-coupled grep for "Total registered ... hooks scanned:" — the
# audit's summary header phrasing has evolved across iterations (iter-67
# "Stop hooks", iter-68 "Stop hooks" preserved during scope expansion to
# trinity, iter-69 renamed to "pentad-member hooks"). Using a wildcard
# between "registered" and "scanned" insulates the test from future
# phrasing changes that don't alter the count semantics.
total_scanned=$(echo "$AUDIT_OUTPUT" | grep -oE 'Total registered [a-zA-Z -]+ scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
clean_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'CLEAN \(no additionalContext in code\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
with_ok_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'WITH-OK-MARKER \(justified internal usage\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
violation_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'EMISSION-VIOLATION \(silent-drop risk\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)

# Expected (iter-67 fixtures #01-#06 + iter-68 fixtures #07-#08 + iter-69 fixtures #09-#10):
#   - Total scanned: 10  (6 Stop + 1 SubagentStop + 1 SessionEnd + 1 PreCompact + 1 Notification)
#   - CLEAN:         2  (Stop fixtures #01, #03)
#   - WITH-OK-MARKER: 1  (Stop fixture #04)
#   - EMISSION-VIOLATION: 7  (Stop #02 #05 #06 + SubagentStop #07 + SessionEnd #08 + PreCompact #09 + Notification #10)
if [ "$total_scanned" = "10" ]; then
  assert_pass "Total scanned = 10 (6 Stop + 1 SubagentStop + 1 SessionEnd + 1 PreCompact + 1 Notification — full pentad)"
else
  assert_fail "Total scanned = $total_scanned, expected 10"
fi

if [ "$clean_count" = "2" ]; then
  assert_pass "CLEAN count = 2 (Stop fixtures #01 + #03)"
else
  assert_fail "CLEAN count = $clean_count, expected 2"
fi

if [ "$with_ok_count" = "1" ]; then
  assert_pass "WITH-OK-MARKER count = 1 (Stop fixture #04)"
else
  assert_fail "WITH-OK-MARKER count = $with_ok_count, expected 1"
fi

if [ "$violation_count" = "7" ]; then
  assert_pass "EMISSION-VIOLATION count = 7 (Stop #02 #05 #06 + SubagentStop #07 + SessionEnd #08 + PreCompact #09 + Notification #10)"
else
  assert_fail "EMISSION-VIOLATION count = $violation_count, expected 7"
fi

# Per-fixture marker assertions (iter-67 set)
if echo "$AUDIT_OUTPUT" | grep -q 'fixture02-stop-hook-emits-additionalContext-violation'; then
  assert_pass "Fixture #02 (literal Stop emission) reported in violation diagnostic"
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

# Iter-68 expansion assertions: SubagentStop + SessionEnd coverage
if echo "$AUDIT_OUTPUT" | grep -q '(SubagentStop).*fixture07-subagentstop-hook-emits-additionalContext-violation'; then
  assert_pass "Fixture #07 (SubagentStop emission) reported WITH SubagentStop event-type tag — iter-68 scope expansion working"
else
  assert_fail "Fixture #07 missing or missing (SubagentStop) tag — iter-68 scope expansion to SubagentStop FAILED"
fi

if echo "$AUDIT_OUTPUT" | grep -q '(SessionEnd).*fixture08-sessionend-hook-emits-additionalContext-violation'; then
  assert_pass "Fixture #08 (SessionEnd emission) reported WITH SessionEnd event-type tag — iter-68 scope expansion working"
else
  assert_fail "Fixture #08 missing or missing (SessionEnd) tag — iter-68 scope expansion to SessionEnd FAILED"
fi

# Per-event-type breakdown assertions (iter-68 summary feature)
if echo "$AUDIT_OUTPUT" | grep -qE 'Stop:[[:space:]]+6 scanned / 3 violations'; then
  assert_pass "Per-event-type breakdown shows Stop: 6 scanned / 3 violations"
else
  assert_fail "Per-event-type breakdown for Stop missing or wrong counts"
fi

if echo "$AUDIT_OUTPUT" | grep -qE 'SubagentStop:[[:space:]]+1 scanned / 1 violations'; then
  assert_pass "Per-event-type breakdown shows SubagentStop: 1 scanned / 1 violations"
else
  assert_fail "Per-event-type breakdown for SubagentStop missing or wrong counts"
fi

if echo "$AUDIT_OUTPUT" | grep -qE 'SessionEnd:[[:space:]]+1 scanned / 1 violations'; then
  assert_pass "Per-event-type breakdown shows SessionEnd: 1 scanned / 1 violations"
else
  assert_fail "Per-event-type breakdown for SessionEnd missing or wrong counts"
fi

# SessionEnd-specific schema diagnostic — verifies the case statement
# in the violation accumulator emits the empty-output rule (NOT the
# {decision, reason} rule which applies to Stop/SubagentStop only).
if echo "$AUDIT_OUTPUT" | grep -q 'SessionEndOK returns EMPTY output'; then
  assert_pass "SessionEnd violation diagnostic mentions empty-output schema rule (NOT {decision, reason}) — iter-68 per-event-type diagnostic correctly differentiates"
else
  assert_fail "SessionEnd diagnostic missing 'SessionEndOK returns EMPTY output' phrase — case-statement schema differentiation failed"
fi

# Iter-69 pentad completion assertions: PreCompact + Notification coverage
if echo "$AUDIT_OUTPUT" | grep -q '(PreCompact).*fixture09-precompact-hook-emits-additionalContext-violation'; then
  assert_pass "Fixture #09 (PreCompact emission) reported WITH PreCompact event-type tag — iter-69 pentad expansion working"
else
  assert_fail "Fixture #09 missing or missing (PreCompact) tag — iter-69 pentad expansion to PreCompact FAILED"
fi

if echo "$AUDIT_OUTPUT" | grep -q '(Notification).*fixture10-notification-hook-emits-additionalContext-violation'; then
  assert_pass "Fixture #10 (Notification emission) reported WITH Notification event-type tag — iter-69 pentad expansion working"
else
  assert_fail "Fixture #10 missing or missing (Notification) tag — iter-69 pentad expansion to Notification FAILED"
fi

# Per-event-type breakdown assertions for the two new pentad members
if echo "$AUDIT_OUTPUT" | grep -qE 'PreCompact:[[:space:]]+1 scanned / 1 violations'; then
  assert_pass "Per-event-type breakdown shows PreCompact: 1 scanned / 1 violations"
else
  assert_fail "Per-event-type breakdown for PreCompact missing or wrong counts"
fi

if echo "$AUDIT_OUTPUT" | grep -qE 'Notification:[[:space:]]+1 scanned / 1 violations'; then
  assert_pass "Per-event-type breakdown shows Notification: 1 scanned / 1 violations"
else
  assert_fail "Per-event-type breakdown for Notification missing or wrong counts"
fi

# PreCompact-specific schema diagnostic — verifies PreCompact violation
# message cites the same {decision:'block', reason} rule as Stop (case
# statement Stop|SubagentStop|PreCompact branch).
if echo "$AUDIT_OUTPUT" | grep -q "Per official Anthropic PreCompact-hook schema"; then
  assert_pass "PreCompact violation diagnostic cites Stop-family schema rule ({decision:'block', reason}) — iter-69 case-statement branch working"
else
  assert_fail "PreCompact diagnostic missing 'Per official Anthropic PreCompact-hook schema' phrase — case-statement Stop-family branch failed"
fi

# Notification-specific schema diagnostic — verifies Notification violation
# message cites the no-decision-capability rule (NOT Stop-family rule;
# Notification has its own case-statement branch).
if echo "$AUDIT_OUTPUT" | grep -q 'Exit Code 2 Behavior: N/A'; then
  assert_pass "Notification violation diagnostic mentions no-decision-capability schema rule ('Exit Code 2 Behavior: N/A') — iter-69 case-statement Notification branch working"
else
  assert_fail "Notification diagnostic missing 'Exit Code 2 Behavior: N/A' phrase — case-statement Notification branch failed"
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
# iter-68 violation fixtures (SubagentStop + SessionEnd):
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture07-subagentstop-hook-emits-additionalContext-violation"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture08-sessionend-hook-emits-additionalContext-violation"
# iter-69 violation fixtures (PreCompact + Notification):
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture09-precompact-hook-emits-additionalContext-violation"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture10-notification-hook-emits-additionalContext-violation"

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
