#!/usr/bin/env bash
# test-audit-wildcard-matcher-detects-star-and-null-matchers-classifies-with-and-without-ok-marker-escape-hatch-with-min-reason-length-and-exits-nonzero-on-violation.sh
#
# Regression test for the iter-65 wildcard-matcher audit at
# .mise/tasks/audit-pretooluse-and-posttooluse-hooks-for-wildcard-
# matcher-star-or-null-which-cold-starts-bun-on-every-tool-call-
# causing-12-17ms-cpu-or-latency-waste-per-non-meaningful-invocation.
#
# WHY this is load-bearing:
#
#   Iter-63 and iter-64 each fixed a single wildcard-matcher case
#   (PreToolUse stdin-inlet-guard + PostToolUse orphan-cleanup) that
#   wasted ~1360ms per session in bun cold-starts on non-meaningful
#   invocations. The iter-65 audit scales those fixes into preventive
#   infrastructure — blocks future regressions from reintroducing the
#   wildcard-matcher anti-pattern.
#
#   At iter-65 build time the marketplace has ZERO wildcard matchers
#   (iter-63 and iter-64 fixed both known cases). The audit is pure
#   preventive infrastructure. The regression test ensures the audit
#   itself can't silently break detection if a future commit edits
#   the classification logic, escape-hatch parsing, or jq pipeline.
#
# Coverage matrix (5 synthetic-fixture plugins → 11 assertions):
#
#   # | Fixture                                          | Event       | Matcher       | OK marker?    | Expected
#   --|--------------------------------------------------|-------------|---------------|---------------|---------------------
#   01| Scoped 'Bash' matcher (PreToolUse)              | PreToolUse  | "Bash"        | n/a           | SCOPED-MATCHER
#   02| Wildcard '*' matcher with NO OK marker          | PreToolUse  | "*"           | absent        | WILDCARD-VIOLATION
#   03| Wildcard '*' matcher WITH valid OK marker       | PostToolUse | "*"           | valid (12 ch) | WILDCARD-WITH-OK-MARKER
#   04| NULL matcher (JSON null) with NO OK marker      | PostToolUse | <null>        | absent        | WILDCARD-VIOLATION
#   05| Wildcard '*' with INVALID short OK marker (<10) | PreToolUse  | "*"           | short (3 ch)  | WILDCARD-VIOLATION
#
# Plus assertions for:
#   - Summary counts (3: scoped + with-ok + violation)
#   - Exit code (1 because fixtures #2/#4/#5 produce violations)
#   - Diagnostic content (mentions iter-63 + iter-64 + the cost)
#   - Clean-state re-run (remove violation fixtures, expect exit 0)
#
# Verbose filename encodes: WHAT (wildcard-matcher audit), WHICH
# detections (star + null), WHICH classifications (with + without
# OK marker), WHICH gate (min reason length, nonzero exit). Future
# maintainers searching for "wildcard matcher test", "iter-65",
# "WILDCARD-MATCHER-OK escape hatch test", or "matcher null detection"
# surface this regression guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK="$SCRIPT_DIR/../audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null-which-cold-starts-bun-on-every-tool-call-causing-12-17ms-cpu-or-latency-waste-per-non-meaningful-invocation.sh"

if [ ! -x "$AUDIT_TASK" ]; then
  echo "FATAL: audit task not executable: $AUDIT_TASK" >&2
  exit 1
fi

FIXTURE_FLEET_ROOT=$(mktemp -d -t wildcard-matcher-audit-regression-fixture-fleet.XXXXXX)
trap 'rm -rf "$FIXTURE_FLEET_ROOT"' EXIT

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: create a fixture plugin with a specific hooks.json + optional
# source-file content for the WILDCARD-MATCHER-OK marker check.
create_fixture_plugin_with_hooks_json_and_optional_source_marker() {
  local plugin_name="$1" hooks_json_content="$2" source_filename="$3" source_content="$4"
  local hooks_dir="$FIXTURE_FLEET_ROOT/plugins/$plugin_name/hooks"
  mkdir -p "$hooks_dir"
  printf '%s\n' "$hooks_json_content" > "$hooks_dir/hooks.json"
  if [ -n "$source_filename" ]; then
    printf '%s\n' "$source_content" > "$hooks_dir/$source_filename"
  fi
}

# ---------------------------------------------------------------------------
# Build fixture fleet
# ---------------------------------------------------------------------------
echo "=== Building synthetic fixture fleet at $FIXTURE_FLEET_ROOT ==="

# #01 SCOPED-MATCHER: matcher="Bash" — correctly narrow, no violation
# shellcheck disable=SC2016
# SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
create_fixture_plugin_with_hooks_json_and_optional_source_marker \
  "fixture01-scoped-matcher-bash-pretooluse" \
  '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-scoped-guard.ts"}]}]}}' \
  "pretooluse-scoped-guard.ts" \
  '#!/usr/bin/env bun
// Just a scoped hook; matcher narrows it to Bash so no WILDCARD-MATCHER-OK needed.
console.log(JSON.stringify({hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}));'

# #02 WILDCARD-VIOLATION: matcher="*" with NO OK marker
# shellcheck disable=SC2016
# SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
create_fixture_plugin_with_hooks_json_and_optional_source_marker \
  "fixture02-wildcard-star-no-ok-marker-pretooluse-violation" \
  '{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-wildcard-violation.ts"}]}]}}' \
  "pretooluse-wildcard-violation.ts" \
  '#!/usr/bin/env bun
// No WILDCARD-MATCHER-OK marker — audit should flag this.
console.log(JSON.stringify({hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}));'

# #03 WILDCARD-WITH-OK-MARKER: matcher="*" WITH valid OK marker (≥10 chars)
# shellcheck disable=SC2016
# SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
create_fixture_plugin_with_hooks_json_and_optional_source_marker \
  "fixture03-wildcard-star-with-valid-ok-marker-posttooluse" \
  '{"hooks":{"PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/posttooluse-legit-broad-scope.ts"}]}]}}' \
  "posttooluse-legit-broad-scope.ts" \
  '#!/usr/bin/env bun
// WILDCARD-MATCHER-OK: session-once reminder that needs ANY tool to fire
console.log(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse"}}));'

# #04 WILDCARD-VIOLATION via NULL matcher (JSON null)
# shellcheck disable=SC2016
# SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
create_fixture_plugin_with_hooks_json_and_optional_source_marker \
  "fixture04-null-matcher-posttooluse-violation" \
  '{"hooks":{"PostToolUse":[{"matcher":null,"hooks":[{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/posttooluse-null-matcher.ts"}]}]}}' \
  "posttooluse-null-matcher.ts" \
  '#!/usr/bin/env bun
// No WILDCARD-MATCHER-OK marker, and matcher is null (same semantic as wildcard).
console.log(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse"}}));'

# #05 WILDCARD-VIOLATION with INVALID short OK marker (<10 chars reason)
# shellcheck disable=SC2016
# SC2016 intentional: ${CLAUDE_PLUGIN_ROOT} must reach hooks.json literally.
create_fixture_plugin_with_hooks_json_and_optional_source_marker \
  "fixture05-wildcard-with-too-short-ok-marker-violation" \
  '{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"bun ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-short-marker.ts"}]}]}}' \
  "pretooluse-short-marker.ts" \
  '#!/usr/bin/env bun
// WILDCARD-MATCHER-OK: ok
// ↑ reason "ok" is only 2 chars — below the 10-char minimum.
console.log(JSON.stringify({hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}));'

# ---------------------------------------------------------------------------
# Run audit (expect exit 1 due to fixtures #2, #4, #5)
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

scoped_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'SCOPED-MATCHER[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
with_ok_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'WILDCARD-WITH-OK-MARKER[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
violation_count=$(echo "$AUDIT_OUTPUT" | grep -oE 'WILDCARD-VIOLATION[^:]*:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
total_scanned=$(echo "$AUDIT_OUTPUT" | grep -oE 'Total PreToolUse/PostToolUse hook entries scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)

# Expected: 5 total, 1 scoped (#1), 1 with-ok (#3), 3 violations (#2, #4, #5)
if [ "$total_scanned" = "5" ]; then
  assert_pass "Total scanned = 5 (one fixture per scenario)"
else
  assert_fail "Total scanned = $total_scanned, expected 5"
fi

if [ "$scoped_count" = "1" ]; then
  assert_pass "SCOPED-MATCHER count = 1 (fixture #01)"
else
  assert_fail "SCOPED-MATCHER count = $scoped_count, expected 1"
fi

if [ "$with_ok_count" = "1" ]; then
  assert_pass "WILDCARD-WITH-OK-MARKER count = 1 (fixture #03)"
else
  assert_fail "WILDCARD-WITH-OK-MARKER count = $with_ok_count, expected 1"
fi

if [ "$violation_count" = "3" ]; then
  assert_pass "WILDCARD-VIOLATION count = 3 (fixtures #02, #04, #05)"
else
  assert_fail "WILDCARD-VIOLATION count = $violation_count, expected 3"
fi

# Per-fixture marker assertions
if echo "$AUDIT_OUTPUT" | grep -q 'fixture02-wildcard-star-no-ok-marker-pretooluse-violation'; then
  assert_pass "Fixture #02 (wildcard '*' no OK) reported in violation diagnostic"
else
  assert_fail "Fixture #02 missing from violation diagnostic"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture04-null-matcher-posttooluse-violation'; then
  if echo "$AUDIT_OUTPUT" | grep -q '<null/missing>'; then
    assert_pass "Fixture #04 (null matcher) reported with '<null/missing>' display label"
  else
    assert_fail "Fixture #04 missing '<null/missing>' label"
  fi
else
  assert_fail "Fixture #04 missing from violation diagnostic"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'fixture05-wildcard-with-too-short-ok-marker-violation'; then
  assert_pass "Fixture #05 (too-short OK marker, <10 chars) reported in violation diagnostic"
else
  assert_fail "Fixture #05 missing — short-reason escape hatch failed to enforce min-length"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'WILDCARD-WITH-OK-MARKER.*fixture03-wildcard-star-with-valid-ok-marker-posttooluse'; then
  assert_pass "Fixture #03 (valid 12-char OK marker) correctly classified as WILDCARD-WITH-OK-MARKER"
else
  assert_fail "Fixture #03 misclassified — valid OK marker not honored"
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

if echo "$AUDIT_OUTPUT" | grep -q 'iter-63'; then
  assert_pass "Diagnostic references iter-63 (forensic provenance)"
else
  assert_fail "Diagnostic missing iter-63 reference"
fi

# ---------------------------------------------------------------------------
# Clean-state re-run (remove violation fixtures; expect exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "=== Removing violation fixtures and re-running (expect exit 0) ==="

rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture02-wildcard-star-no-ok-marker-pretooluse-violation"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture04-null-matcher-posttooluse-violation"
rm -rf "$FIXTURE_FLEET_ROOT/plugins/fixture05-wildcard-with-too-short-ok-marker-violation"

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
