#!/usr/bin/env bash
# Iter-187 regression test proving a FAILING test file always NAMES ITSELF in the marketplace hook regression suite's output, through three independent carriers, so a log that has been piped through a filter can never again report a failure nobody can identify. Hermetic: copies the real runner into a mktemp sandbox holding one synthetic passing and one synthetic failing test, so it asserts against the actual runner source with zero dependence on the marketplace's real 100+ test corpus, zero wall-clock sensitivity and zero recursion. Covers (1) the count line that empirically survived the filter now carrying the names, (2) the FAILED-TEST-FILE roster token, (3) the stderr mirror surviving total stdout suppression, plus the two NON-INFLATION invariants that make the change safe: bare 'grep -c FILE-FAIL' / 'FILE-PASS' tallies (iter-75 parity test, triage task) are unchanged, and the release preflight's 'grep -oE Test files FAILED:' extractor still parses.

# ─── WHY THIS TEST EXISTS ────────────────────────────────────────────────────
# One `moon run repo:check` reported 113 discovered / 112 passed / 1 FAILED. The
# runs on either side were 113/113 and ten standalone re-runs of the suite were
# all green. The failing file's NAME was never captured: the operator's log had
# been piped through a filter that kept the three count lines and dropped
# everything else, and at that time the name appeared in exactly two places —
# an inline `✗ FILE-FAIL:` line about a hundred tests up the log, and a roster
# line reading `    - <path>` whose prefix matched no plausible grep. So a real
# failure became permanently unidentifiable.
#
# Iter-187's fix is redundancy: three carriers, no single filter can erase all
# three. This test locks that in. It deliberately also pins the invariants that
# keep the fix from breaking its neighbours, because the obvious implementation
# (reuse the existing FILE-FAIL token in the summary) would silently inflate the
# `grep -c` tallies that the iter-75 parity test and the triage task depend on.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MARKETPLACE_HOOK_REGRESSION_SUITE_RUNNER_ABSOLUTE_PATH="$REPO_ROOT/tasks/test-marketplace-hook-regression-suite"

ITER187_ASSERTIONS_PASSED=0
ITER187_ASSERTIONS_FAILED=0

assert_substring_present() {
    local assertion_label="$1"
    local haystack="$2"
    local expected_substring="$3"
    if [[ "$haystack" == *"$expected_substring"* ]]; then
        ITER187_ASSERTIONS_PASSED=$((ITER187_ASSERTIONS_PASSED + 1))
        echo "  ✓ PASS: $assertion_label"
    else
        ITER187_ASSERTIONS_FAILED=$((ITER187_ASSERTIONS_FAILED + 1))
        echo "  ✗ FAIL: $assertion_label"
        echo "    expected substring: $expected_substring"
        echo "    haystack (first 400 chars): ${haystack:0:400}"
    fi
}

assert_substring_absent() {
    local assertion_label="$1"
    local haystack="$2"
    local forbidden_substring="$3"
    if [[ "$haystack" != *"$forbidden_substring"* ]]; then
        ITER187_ASSERTIONS_PASSED=$((ITER187_ASSERTIONS_PASSED + 1))
        echo "  ✓ PASS: $assertion_label"
    else
        ITER187_ASSERTIONS_FAILED=$((ITER187_ASSERTIONS_FAILED + 1))
        echo "  ✗ FAIL: $assertion_label"
        echo "    forbidden substring was present: $forbidden_substring"
    fi
}

assert_numbers_equal() {
    local assertion_label="$1"
    local actual_value="$2"
    local expected_value="$3"
    if [[ "$actual_value" == "$expected_value" ]]; then
        ITER187_ASSERTIONS_PASSED=$((ITER187_ASSERTIONS_PASSED + 1))
        echo "  ✓ PASS: $assertion_label (= $actual_value)"
    else
        ITER187_ASSERTIONS_FAILED=$((ITER187_ASSERTIONS_FAILED + 1))
        echo "  ✗ FAIL: $assertion_label"
        echo "    expected: $expected_value"
        echo "    actual:   $actual_value"
    fi
}

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-187 regression test — a failing test file must name itself"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

if [[ ! -f "$MARKETPLACE_HOOK_REGRESSION_SUITE_RUNNER_ABSOLUTE_PATH" ]]; then
    echo "  ✗ FAIL: runner not found at $MARKETPLACE_HOOK_REGRESSION_SUITE_RUNNER_ABSOLUTE_PATH"
    exit 1
fi

# ─── SANDBOX ─────────────────────────────────────────────────────────────────
# A private mktemp repo root with its own plugins/<p>/hooks/tests/ tree holding
# exactly two synthetic tests. The runner derives REPO_ROOT from its own
# BASH_SOURCE, so copying it here scopes discovery to the sandbox: this test
# never runs the marketplace's real corpus, and never recurses into itself.
# mktemp (not a fixed /tmp path) because this test runs inside a parallel suite
# and may be running concurrently with another checkout of this repo.
ITER187_SANDBOX_REPO_ROOT="$(mktemp -d -t iter187-failing-test-names-itself.XXXXXX)"
trap 'rm -rf "$ITER187_SANDBOX_REPO_ROOT"' EXIT

mkdir -p "$ITER187_SANDBOX_REPO_ROOT/tasks/tests" \
         "$ITER187_SANDBOX_REPO_ROOT/plugins/iter187demo/hooks/tests"
cp "$MARKETPLACE_HOOK_REGRESSION_SUITE_RUNNER_ABSOLUTE_PATH" \
   "$ITER187_SANDBOX_REPO_ROOT/tasks/test-marketplace-hook-regression-suite"

ITER187_SANDBOX_RUNNER="$ITER187_SANDBOX_REPO_ROOT/tasks/test-marketplace-hook-regression-suite"
ITER187_SYNTHETIC_PASSING_TEST_BASENAME="test-iter187-synthetic-always-passes.sh"
ITER187_SYNTHETIC_FAILING_TEST_BASENAME="test-iter187-synthetic-always-fails-with-exit-code-seven.sh"
ITER187_SANDBOX_TESTS_DIR="$ITER187_SANDBOX_REPO_ROOT/plugins/iter187demo/hooks/tests"

printf '#!/usr/bin/env bash\necho "iter187 synthetic pass"\nexit 0\n' \
    > "$ITER187_SANDBOX_TESTS_DIR/$ITER187_SYNTHETIC_PASSING_TEST_BASENAME"
printf '#!/usr/bin/env bash\necho "iter187 synthetic failure body"\nexit 7\n' \
    > "$ITER187_SANDBOX_TESTS_DIR/$ITER187_SYNTHETIC_FAILING_TEST_BASENAME"

ITER187_EXPECTED_FAILING_RELATIVE_PATH="plugins/iter187demo/hooks/tests/$ITER187_SYNTHETIC_FAILING_TEST_BASENAME"

# ─── SCENARIO 1: one test fails ──────────────────────────────────────────────
ITER187_STDOUT_ONLY_CAPTURE="$ITER187_SANDBOX_REPO_ROOT/red.stdout"
ITER187_STDERR_ONLY_CAPTURE="$ITER187_SANDBOX_REPO_ROOT/red.stderr"

# Split streams so each carrier can be judged on its own. Do NOT let a non-zero
# runner exit (which is the POINT of this scenario) abort the test.
ITER187_RED_RUN_EXIT_CODE=0
bash "$ITER187_SANDBOX_RUNNER" \
    > "$ITER187_STDOUT_ONLY_CAPTURE" 2> "$ITER187_STDERR_ONLY_CAPTURE" \
    || ITER187_RED_RUN_EXIT_CODE=$?

ITER187_RED_STDERR_TEXT="$(cat "$ITER187_STDERR_ONLY_CAPTURE")"

echo "── Scenario 1: a failing test file, three independent name carriers ──"

assert_numbers_equal \
    "S1.0: runner exits non-zero when a test file fails" \
    "$ITER187_RED_RUN_EXIT_CODE" \
    "1"

# CARRIER 1 — the count line. This is the line empirically PROVEN to have
# survived the filter that lost the name, so it must carry the name itself.
# Simulate that exact filter rather than trusting the whole-log haystack.
ITER187_COUNT_LINES_SURVIVING_A_COUNT_ONLY_GREP="$(
    grep -E 'Test files (discovered|PASSED|FAILED)' "$ITER187_STDOUT_ONLY_CAPTURE" || true
)"
assert_substring_present \
    "S1.1 CARRIER 1: failing filename survives a count-only 'grep -E Test files (discovered|PASSED|FAILED)'" \
    "$ITER187_COUNT_LINES_SURVIVING_A_COUNT_ONLY_GREP" \
    "$ITER187_EXPECTED_FAILING_RELATIVE_PATH"

assert_substring_present \
    "S1.2 CARRIER 1: the count line carries the failing test's exit code too" \
    "$ITER187_COUNT_LINES_SURVIVING_A_COUNT_ONLY_GREP" \
    "(exit=7)"

# CARRIER 2 — the roster token. The old '    - <path>' prefix matched no
# plausible grep; FAILED-TEST-FILE matches 'FAILED', 'FAIL', 'TEST-FILE' and a
# case-insensitive 'fail'.
ITER187_ROSTER_LINES_SURVIVING_A_TOKEN_GREP="$(
    grep -F 'FAILED-TEST-FILE:' "$ITER187_STDOUT_ONLY_CAPTURE" || true
)"
assert_substring_present \
    "S1.3 CARRIER 2: a tokenised roster line names the failing file on stdout" \
    "$ITER187_ROSTER_LINES_SURVIVING_A_TOKEN_GREP" \
    "$ITER187_EXPECTED_FAILING_RELATIVE_PATH"

ITER187_LINES_SURVIVING_A_CASE_INSENSITIVE_FAIL_GREP="$(
    grep -i 'fail' "$ITER187_STDOUT_ONLY_CAPTURE" || true
)"
assert_substring_present \
    "S1.4 CARRIER 2: failing filename survives a bare case-insensitive 'grep -i fail'" \
    "$ITER187_LINES_SURVIVING_A_CASE_INSENSITIVE_FAIL_GREP" \
    "$ITER187_EXPECTED_FAILING_RELATIVE_PATH"

# CARRIER 3 — stderr. The strongest carrier: it survives ANY stdout-only filter,
# including one that discards stdout entirely, because `| grep` and `| tail`
# never touch stderr.
assert_substring_present \
    "S1.5 CARRIER 3: stderr alone names the failing file (survives total stdout suppression)" \
    "$ITER187_RED_STDERR_TEXT" \
    "$ITER187_EXPECTED_FAILING_RELATIVE_PATH"

assert_substring_present \
    "S1.6 CARRIER 3: the stderr mirror is self-labelling" \
    "$ITER187_RED_STDERR_TEXT" \
    "FAILED-TEST-FILE-ROSTER:"

# ─── NON-INFLATION INVARIANTS ────────────────────────────────────────────────
# The obvious implementation — reuse FILE-FAIL as the roster token — would
# silently break two existing consumers that COUNT that token with bare grep -c:
# the iter-75 parity test and the triage task. Pin the tallies.
echo ""
echo "── Scenario 1 (cont.): non-inflation invariants for existing log consumers ──"

ITER187_MERGED_LOG="$ITER187_SANDBOX_REPO_ROOT/red.merged"
cat "$ITER187_STDOUT_ONLY_CAPTURE" "$ITER187_STDERR_ONLY_CAPTURE" > "$ITER187_MERGED_LOG"

ITER187_BARE_FILE_FAIL_TALLY="$(grep -c 'FILE-FAIL' "$ITER187_MERGED_LOG" || true)"
assert_numbers_equal \
    "S1.7: iter-75 parity test's bare \"grep -c 'FILE-FAIL'\" still counts exactly the 1 failing test" \
    "$ITER187_BARE_FILE_FAIL_TALLY" \
    "1"

ITER187_BARE_FILE_PASS_TALLY="$(grep -c 'FILE-PASS' "$ITER187_MERGED_LOG" || true)"
assert_numbers_equal \
    "S1.8: iter-75 parity test's bare \"grep -c 'FILE-PASS'\" still counts exactly the 1 passing test" \
    "$ITER187_BARE_FILE_PASS_TALLY" \
    "1"

ITER187_TRIAGE_ANCHORED_TALLY="$(grep -cE '^  ✗ FILE-FAIL:' "$ITER187_MERGED_LOG" || true)"
assert_numbers_equal \
    "S1.9: triage task's anchored \"grep -cE '^  ✗ FILE-FAIL:'\" still counts exactly 1" \
    "$ITER187_TRIAGE_ANCHORED_TALLY" \
    "1"

# The release preflight parses the count with `grep -oE`, which matches only the
# label+number prefix — appending names AFTER the number must leave it intact.
# `awk 'NR==1'`, not `head -1`: awk drains its input, so there is no SIGPIPE race
# to make this pipeline return 141 under `pipefail`. (The preflight's own copy of
# this extractor still uses `head -1`; that is pre-existing and out of scope here,
# but it is the reason this test asserts the REGEX still matches rather than
# reproducing the reader verbatim.)
ITER187_PREFLIGHT_PARSED_FAILED_COUNT="$(
    { grep -oE 'Test files FAILED:[[:space:]]+[0-9]+' "$ITER187_MERGED_LOG" || true; } |
        awk 'NR==1 {print $NF}'
)"
assert_numbers_equal \
    "S1.10: release preflight's 'grep -oE Test files FAILED:' extractor still parses the count" \
    "$ITER187_PREFLIGHT_PARSED_FAILED_COUNT" \
    "1"

ITER187_PREFLIGHT_PARSED_PASSED_COUNT="$(
    { grep -oE 'Test files PASSED:[[:space:]]+[0-9]+' "$ITER187_MERGED_LOG" || true; } |
        awk 'NR==1 {print $NF}'
)"
assert_numbers_equal \
    "S1.11: release preflight's 'grep -oE Test files PASSED:' extractor still parses the count" \
    "$ITER187_PREFLIGHT_PARSED_PASSED_COUNT" \
    "1"

# ─── SCENARIO 2: everything passes ───────────────────────────────────────────
# The naming tokens must not appear on a green run, or every green log would
# read as red to the same greps this change teaches operators to use.
echo ""
echo "── Scenario 2: an all-green run emits no failure-naming tokens ──"

rm -f "$ITER187_SANDBOX_TESTS_DIR/$ITER187_SYNTHETIC_FAILING_TEST_BASENAME"

ITER187_GREEN_STDOUT_CAPTURE="$ITER187_SANDBOX_REPO_ROOT/green.stdout"
ITER187_GREEN_STDERR_CAPTURE="$ITER187_SANDBOX_REPO_ROOT/green.stderr"
ITER187_GREEN_RUN_EXIT_CODE=0
bash "$ITER187_SANDBOX_RUNNER" \
    > "$ITER187_GREEN_STDOUT_CAPTURE" 2> "$ITER187_GREEN_STDERR_CAPTURE" \
    || ITER187_GREEN_RUN_EXIT_CODE=$?

ITER187_GREEN_MERGED_TEXT="$(cat "$ITER187_GREEN_STDOUT_CAPTURE" "$ITER187_GREEN_STDERR_CAPTURE")"

assert_numbers_equal \
    "S2.1: runner exits 0 when every test file passes" \
    "$ITER187_GREEN_RUN_EXIT_CODE" \
    "0"

assert_substring_absent \
    "S2.2: no FAILED-TEST-FILE token on a green run" \
    "$ITER187_GREEN_MERGED_TEXT" \
    "FAILED-TEST-FILE"

assert_substring_present \
    "S2.3: green run still reports zero failures on the count line" \
    "$ITER187_GREEN_MERGED_TEXT" \
    "Test files FAILED:     0"

assert_substring_present \
    "S2.4: green run still emits the all-passed banner" \
    "$ITER187_GREEN_MERGED_TEXT" \
    "All marketplace hook regression tests PASSED"

# ─── VERDICT ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-187 — assertions passed: $ITER187_ASSERTIONS_PASSED, failed: $ITER187_ASSERTIONS_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════════"

if [[ "$ITER187_ASSERTIONS_FAILED" -gt 0 ]]; then
    echo "  ✗ Iter-187 regression test FAILED"
    exit 1
fi

echo "  ✓ Iter-187 regression test PASSED — a failing test file names itself on the"
echo "    count line, in a tokenised roster, and on stderr; existing log consumers"
echo "    (iter-75 parity, triage task, release preflight) are unaffected."
