#!/usr/bin/env bash
# test-code-correctness-guard-bash-branch-early-exit-zero-skips-stderr-and-command-jq-spawns.sh
#
# Regression test for iter-56 Bash-branch early-exit jq-batching
# optimization on code-correctness-guard.sh. The optimization:
#
#   Pre-iter-56 (line 71-74): the Bash branch spawned 3 separate jq
#   processes unconditionally to extract EXIT_CODE + STDERR + COMMAND
#   BEFORE the early-exit-on-EXIT_CODE-0 check (line 77). Since most
#   Bash commands exit 0, 2 of those 3 jq spawns (STDERR + COMMAND)
#   were pure waste on the dominant code path.
#
#   Iter-56: extract EXIT_CODE alone first (1 jq); if it's 0, exit
#   immediately; only on non-zero exit, spawn ONE BATCHED jq that
#   emits STDERR + COMMAND via @tsv. Net 3 jq → 1 jq on hot path.
#
# This test pins four invariants:
#
#   (A1) STRUCTURAL — within the `if [[ "$TOOL_NAME" == "Bash" ]]`
#        branch, EXIT_CODE extraction (cheap, single field) appears
#        BEFORE any STDERR extraction. This is the iter-56 ordering
#        contract — if anyone reverses it, the hot-path waste returns.
#
#   (A2) STRUCTURAL — the iter-56 batched-jq @tsv pattern is present
#        in the source (proves we didn't accidentally fall back to
#        3 separate jq spawns).
#
#   (B) BEHAVIORAL FAST PATH — a Bash payload with exit_code=0 exits
#       silently (no JSON output, no BASH-FAILURE block).
#
#   (C) BEHAVIORAL SLOW PATH — a Bash payload with exit_code=2 and
#       non-empty stderr emits the BASH-FAILURE decision:block JSON
#       AND the STDERR content is preserved through the @tsv round-trip
#       (including any embedded newlines).
#
# Verbose filename per the user directive — encodes the exact code
# path being tested ("bash-branch-early-exit-zero-skips-stderr-and-
# command-jq-spawns"). Future maintainers searching for "code-
# correctness early exit", "jq batching bash branch", or "iter-56"
# will surface this regression guard.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_UNDER_TEST="$SCRIPT_DIR/../code-correctness-guard.sh"

if [ ! -x "$HOOK_UNDER_TEST" ]; then
  echo "FATAL: hook not executable: $HOOK_UNDER_TEST" >&2
  exit 1
fi

PASS=0
FAIL=0

assert_pass() {
  echo "  ✓ PASS: $1"
  PASS=$((PASS+1))
}

assert_fail() {
  echo "  ✗ FAIL: $1"
  FAIL=$((FAIL+1))
}

# ---------------------------------------------------------------------------
# INVARIANT A1: structural — EXIT_CODE extraction precedes STDERR extraction
# inside the Bash branch.
# ---------------------------------------------------------------------------
echo "=== INVARIANT A1: source structure — EXIT_CODE jq precedes STDERR jq in Bash branch ==="

# Strip comment lines before grepping so the iter-56 documentation block
# (which references the pre-iter-56 STDERR jq verbatim) doesn't trigger
# false positives. Same defensive technique as iter-55's A1 check.
# shellcheck disable=SC2016
# SC2016 intentional: awk pattern uses $0 as field, not shell expansion.
exit_code_line=$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print NR":"$0 }' "$HOOK_UNDER_TEST" \
                  | grep -E '^[0-9]+:[[:space:]]*EXIT_CODE=' | head -1 | cut -d: -f1)
# shellcheck disable=SC2016
stderr_line=$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print NR":"$0 }' "$HOOK_UNDER_TEST" \
                | grep -E '^[0-9]+:[[:space:]]*STDERR=' | head -1 | cut -d: -f1)

if [ -z "$exit_code_line" ]; then
  assert_fail "no EXIT_CODE= assignment found in hook source"
elif [ -z "$stderr_line" ]; then
  assert_pass "no STDERR= assignment in hook (degenerate but valid — early exit trivially holds)"
elif [ "$exit_code_line" -lt "$stderr_line" ]; then
  assert_pass "EXIT_CODE= at line $exit_code_line precedes STDERR= at line $stderr_line"
else
  assert_fail "EXIT_CODE= at line $exit_code_line is AFTER STDERR= at line $stderr_line — iter-56 ordering regressed"
fi

# ---------------------------------------------------------------------------
# INVARIANT A2: structural — batched @tsv pattern is present
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT A2: source structure — batched @tsv pattern is present ==="

# Look for the iter-56 batched jq invocation that emits stderr+command via @tsv.
# Pattern: jq -r '[(.tool_output.stderr ...), (.tool_input.command ...)] | @tsv'
if grep -qE 'jq -r .*tool_output\.stderr.*tool_input\.command.*@tsv' "$HOOK_UNDER_TEST"; then
  assert_pass "batched @tsv pattern combining stderr+command is present (iter-56 pattern intact)"
else
  assert_fail "batched @tsv pattern missing — iter-56 may have regressed to 3 separate jq spawns"
fi

# ---------------------------------------------------------------------------
# INVARIANT B: behavioral — exit_code=0 produces empty output (fast path)
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT B: behavioral — Bash exit-0 bails silently (fast path) ==="

exit_zero_payload=$(jq -n '{
  tool_name: "Bash",
  tool_input: {command: "echo hello"},
  tool_output: {exit_code: 0, stderr: "", stdout: "hello"}
}')

fast_path_output=$(printf '%s' "$exit_zero_payload" | "$HOOK_UNDER_TEST" 2>&1 || true)

if [ -z "$fast_path_output" ]; then
  assert_pass "Bash exit-0 produced empty output (correct fast-path bail)"
else
  assert_fail "Bash exit-0 produced unexpected output: $fast_path_output"
fi

# ---------------------------------------------------------------------------
# INVARIANT C: behavioral — exit_code≠0 with stderr emits decision:block JSON
# AND the STDERR content survives the @tsv round-trip (no truncation/loss).
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT C: behavioral — Bash non-zero exit emits BASH-FAILURE JSON ==="

# Use a multi-line stderr to verify @tsv newline encoding round-trips.
slow_path_payload=$(jq -n '{
  tool_name: "Bash",
  tool_input: {command: "false-binary --foo"},
  tool_output: {
    exit_code: 127,
    stderr: "command not found: false-binary\nadditional context line",
    stdout: ""
  }
}')

slow_path_output=$(printf '%s' "$slow_path_payload" | "$HOOK_UNDER_TEST" 2>&1 || true)

# Must be valid JSON with decision: "block"
if echo "$slow_path_output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  assert_pass "non-zero exit emits decision: block JSON"
else
  assert_fail "non-zero exit did NOT emit expected decision:block JSON. Got: $slow_path_output"
fi

# The category must be BASH-FAILURE
if echo "$slow_path_output" | jq -e '.reason | startswith("[BASH-FAILURE]")' >/dev/null 2>&1; then
  assert_pass "reason starts with [BASH-FAILURE] category tag"
else
  assert_fail "reason category mismatch. Got: $slow_path_output"
fi

# The reason field must contain the stderr content (proves @tsv round-trip
# didn't lose the data). We check for a UNIQUE substring of the stderr.
if echo "$slow_path_output" | jq -e '.reason | contains("command not found: false-binary")' >/dev/null 2>&1; then
  assert_pass "STDERR content preserved through @tsv round-trip in BASH-FAILURE reason"
else
  assert_fail "STDERR content lost through @tsv round-trip. Got: $slow_path_output"
fi

# The reason field must contain the SECOND stderr line too (proves embedded
# newline round-trip works — jq @tsv encodes "\n" as literal 2-char "\n",
# our printf %b decoder must restore it).
if echo "$slow_path_output" | jq -e '.reason | contains("additional context line")' >/dev/null 2>&1; then
  assert_pass "STDERR second-line (after embedded newline) preserved through @tsv round-trip"
else
  assert_fail "STDERR embedded-newline round-trip failed — second line lost. Got: $slow_path_output"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
