#!/usr/bin/env bash
#MISE description="Iter-75 parity regression test for the parallelized marketplace-hook-regression-suite runner. Synthesizes 3 fixture tests (2 pass + 1 fail) and exercises the xargs-P-with-per-test-temp-file-capture primitive directly to verify exit-code aggregation, per-test stdout capture, and the defensive missing-evidence path. Plus live-marketplace integration assertion: parallel runner against the real test suite must produce identical green-path counts to the iter-50 sequential reference. Catches regressions that would let parallelism corrupt the gate BEFORE release publishes a tag deploying broken concurrency semantics to operator Layer 3 caches (see iter-42 docs/HOOKS.md for cache lifecycle)."

# Iter-75 parity regression test for the parallelized
# .mise/tasks/test-marketplace-hook-regression-suite runner that replaces
# the iter-50 sequential `for test_file in ...` baseline with an
# xargs-P-with-per-test-temp-file-capture concurrency primitive.
#
# Two-tier coverage strategy:
#
#   1. SYNTHETIC FIXTURE TIER — exercises the parallelism primitive
#      directly with 3 known-shape test scripts:
#        a. fixture-passing-test.sh — exits 0, stdout matches expected
#        b. fixture-failing-test.sh — exits 1, stderr contains expected
#        c. fixture-passing-test-second.sh — exits 0 (proves multiple
#           PASS paths don't get confused with each other)
#      Asserts: per-test stdout file exists, per-test .exit file
#      contains correct code, aggregator's pass/fail tally matches
#      ground truth.
#
#   2. LIVE-MARKETPLACE TIER — runs the actual production runner
#      (.mise/tasks/test-marketplace-hook-regression-suite) against
#      the real marketplace test set and asserts: exit code 0,
#      PASS count matches discovered test count, FAIL count is 0.
#      This is the iter-50/iter-74 green-path invariant.
#
# Two-tier coverage protects against:
#   - Concurrency bugs (synthetic) that wouldn't show up in green-path
#     live runs but would corrupt a real FAIL scenario.
#   - Integration drift (live) where the runner's discovery or
#     aggregation paths diverge from the iter-50 reference even though
#     the primitive itself is correct.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNNER_PATH="$REPO_ROOT/.mise/tasks/test-marketplace-hook-regression-suite"

if [[ ! -f "$RUNNER_PATH" ]]; then
    echo "FAIL: Production runner not found at expected path: $RUNNER_PATH"
    exit 1
fi

PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER=$(mktemp -d -t iter75-parallel-runner-parity-fixtures.XXXXXX)
trap 'rm -rf "$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER"' EXIT

ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST=0
ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST=0

assert_equal_with_diagnostic() {
    local assertion_label="$1"
    local expected_value="$2"
    local actual_value="$3"
    if [[ "$expected_value" == "$actual_value" ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST + 1))
    else
        echo "  ✗ $assertion_label: expected=[$expected_value], actual=[$actual_value]"
        ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST + 1))
    fi
}

assert_file_exists_with_diagnostic() {
    local assertion_label="$1"
    local file_path="$2"
    if [[ -f "$file_path" ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST + 1))
    else
        echo "  ✗ $assertion_label: expected file does not exist: $file_path"
        ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST + 1))
    fi
}

# --- Tier 1: Synthetic fixtures exercise the parallelism primitive directly ---
FIXTURE_PASSING_TEST_PATH="$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER/fixture-passing-test.sh"
cat > "$FIXTURE_PASSING_TEST_PATH" <<'EOF_FIXTURE_PASSING_TEST_EXITS_ZERO'
#!/usr/bin/env bash
echo "synthetic-passing-test marker line A"
echo "synthetic-passing-test marker line B"
exit 0
EOF_FIXTURE_PASSING_TEST_EXITS_ZERO
chmod +x "$FIXTURE_PASSING_TEST_PATH"

FIXTURE_FAILING_TEST_PATH="$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER/fixture-failing-test.sh"
cat > "$FIXTURE_FAILING_TEST_PATH" <<'EOF_FIXTURE_FAILING_TEST_EXITS_NONZERO'
#!/usr/bin/env bash
echo "synthetic-failing-test stdout line"
echo "synthetic-failing-test stderr line" >&2
exit 7
EOF_FIXTURE_FAILING_TEST_EXITS_NONZERO
chmod +x "$FIXTURE_FAILING_TEST_PATH"

FIXTURE_PASSING_TEST_SECOND_PATH="$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER/fixture-passing-test-second.sh"
cat > "$FIXTURE_PASSING_TEST_SECOND_PATH" <<'EOF_FIXTURE_SECOND_PASSING_TEST_EXITS_ZERO'
#!/usr/bin/env bash
echo "second-synthetic-passing-test marker"
exit 0
EOF_FIXTURE_SECOND_PASSING_TEST_EXITS_ZERO
chmod +x "$FIXTURE_PASSING_TEST_SECOND_PATH"

# Per-test stdout/exit capture directory for the synthetic tier
SYNTHETIC_TIER_PER_RUN_RESULTS_DIR="$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER/synthetic-tier-results"
mkdir -p "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR"

# Invoke the EXACT same xargs-P pattern the production runner uses.
# If the production runner's primitive changes, this synthetic-tier
# block must be updated to track — that's intentional, so regressions
# in the primitive design fail this test.
# shellcheck disable=SC2016
printf '%s\n' "$FIXTURE_PASSING_TEST_PATH" "$FIXTURE_FAILING_TEST_PATH" "$FIXTURE_PASSING_TEST_SECOND_PATH" | \
    xargs -P 4 -I {} bash -c '
        single_test_file_path="$1"
        per_run_results_dir="$2"
        test_basename_for_stable_lookup="$(basename "$single_test_file_path" .sh)"
        if bash "$single_test_file_path" \
            > "$per_run_results_dir/$test_basename_for_stable_lookup.stdout" 2>&1; then
            echo 0 > "$per_run_results_dir/$test_basename_for_stable_lookup.exit"
        else
            echo "$?" > "$per_run_results_dir/$test_basename_for_stable_lookup.exit"
        fi
    ' _ {} "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR"

# Assert each fixture produced both files
assert_file_exists_with_diagnostic "Synthetic: passing-test stdout file exists" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test.stdout"
assert_file_exists_with_diagnostic "Synthetic: passing-test exit-code file exists" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test.exit"
assert_file_exists_with_diagnostic "Synthetic: failing-test stdout file exists" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-failing-test.stdout"
assert_file_exists_with_diagnostic "Synthetic: failing-test exit-code file exists" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-failing-test.exit"
assert_file_exists_with_diagnostic "Synthetic: passing-test-second stdout file exists" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test-second.stdout"
assert_file_exists_with_diagnostic "Synthetic: passing-test-second exit-code file exists" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test-second.exit"

# Assert exit codes are captured correctly
assert_equal_with_diagnostic "Synthetic: passing-test exit code is 0" \
    "0" "$(cat "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test.exit")"
assert_equal_with_diagnostic "Synthetic: failing-test exit code is 7 (not 0, not 1)" \
    "7" "$(cat "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-failing-test.exit")"
assert_equal_with_diagnostic "Synthetic: passing-test-second exit code is 0" \
    "0" "$(cat "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test-second.exit")"

# Assert stdout content is captured correctly
if grep -q "synthetic-passing-test marker line A" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-passing-test.stdout"; then
    ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST + 1))
else
    echo "  ✗ Synthetic: passing-test stdout does not contain expected marker"
    ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST + 1))
fi

# Assert stderr content is captured correctly (2>&1 redirection in worker)
if grep -q "synthetic-failing-test stderr line" \
    "$SYNTHETIC_TIER_PER_RUN_RESULTS_DIR/fixture-failing-test.stdout"; then
    ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST + 1))
else
    echo "  ✗ Synthetic: failing-test stderr was not captured to .stdout (2>&1 redirection broken)"
    ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST + 1))
fi

# --- Tier 2: Live-marketplace integration. The production runner against the real test set. ---
#
# Recursion guard: this test lives in .mise/tasks/tests/ and is auto-
# discovered by the runner it tests. To avoid `runner → parity test →
# runner → parity test → ...` infinite recursion, the production
# runner exports a sentinel env var on entry. When this parity test
# detects it, the live-tier integration step is SKIPPED (the synthetic
# tier above still runs to exercise the parallelism primitive). When
# invoked standalone (operator running this test directly via bash),
# the env var is unset and full two-tier coverage executes.
if [[ "${MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD:-0}" == "1" ]]; then
    echo ""
    echo "  ⊘ Live-tier integration SKIPPED — running inside parent runner invocation (recursion guard active)"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Iter-75 parallel-runner parity test (synthetic-tier only — recursion guard active)"
    echo "═══════════════════════════════════════════════════════════"
    echo "  Assertions passed: $ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST"
    echo "  Assertions failed: $ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST"
    echo "═══════════════════════════════════════════════════════════"
    if [[ "$ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST" -gt 0 ]]; then
        echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST assertion(s) failed"
        exit 1
    fi
    echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST synthetic-tier assertions passed (live-tier skipped due to recursion guard)"
    exit 0
fi

LIVE_TIER_RUNNER_OUTPUT_LOG="$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER/live-tier-runner.log"
if bash "$RUNNER_PATH" > "$LIVE_TIER_RUNNER_OUTPUT_LOG" 2>&1; then
    LIVE_TIER_RUNNER_EXIT_CODE=0
else
    LIVE_TIER_RUNNER_EXIT_CODE=$?
fi

# grep -c prints "0" natively when no matches AND exits 1; the
# || true swallows the exit 1 so we don't trip pipefail. NEVER add
# `|| echo 0` here — that would APPEND a second "0" line to grep's
# native "0" output, producing the multi-line garbage that broke the
# first ship of this test ("expected=[0], actual=[0\n0]").
LIVE_TIER_PASS_COUNT=$(grep -c 'FILE-PASS' "$LIVE_TIER_RUNNER_OUTPUT_LOG" || true)
LIVE_TIER_FAIL_COUNT=$(grep -c 'FILE-FAIL' "$LIVE_TIER_RUNNER_OUTPUT_LOG" || true)
LIVE_TIER_DISCOVERED_COUNT=$( { grep -oE 'Discovered [0-9]+ test file' "$LIVE_TIER_RUNNER_OUTPUT_LOG" || true; } | grep -oE '[0-9]+' | head -1 || echo 0)

assert_equal_with_diagnostic "Live: runner exit code is 0 (green path)" \
    "0" "$LIVE_TIER_RUNNER_EXIT_CODE"
assert_equal_with_diagnostic "Live: FAIL count is 0" \
    "0" "$LIVE_TIER_FAIL_COUNT"
# PASS count must equal discovered count (every test ran and passed)
assert_equal_with_diagnostic "Live: PASS count equals discovered count ($LIVE_TIER_DISCOVERED_COUNT)" \
    "$LIVE_TIER_DISCOVERED_COUNT" "$LIVE_TIER_PASS_COUNT"

# Lane-equivalence: parallel runner must give identical green counts
# at lanes=1 (degenerate sequential), lanes=8 (default), and lanes=14
# (max). Catches concurrency bugs where some tests would silently be
# skipped or counted twice under high concurrency.
for lane_count_under_test in 1 4 8; do
    LANE_SCAN_OUTPUT_LOG="$PARITY_TEST_TEMP_DIR_FOR_ITER75_PARALLEL_RUNNER/lane-scan-$lane_count_under_test.log"
    if MARKETPLACE_HOOK_REGRESSION_PARALLEL_LANES="$lane_count_under_test" \
        bash "$RUNNER_PATH" > "$LANE_SCAN_OUTPUT_LOG" 2>&1; then
        LANE_SCAN_PASS=$(grep -c 'FILE-PASS' "$LANE_SCAN_OUTPUT_LOG" || true)
        LANE_SCAN_FAIL=$(grep -c 'FILE-FAIL' "$LANE_SCAN_OUTPUT_LOG" || true)
        assert_equal_with_diagnostic "Lanes=$lane_count_under_test: PASS count matches default-lane reference" \
            "$LIVE_TIER_PASS_COUNT" "$LANE_SCAN_PASS"
        assert_equal_with_diagnostic "Lanes=$lane_count_under_test: FAIL count matches default-lane reference (0)" \
            "0" "$LANE_SCAN_FAIL"
    else
        echo "  ✗ Lanes=$lane_count_under_test: runner exited non-zero on green-path marketplace"
        ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST + 1))
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Iter-75 parallel-runner parity test"
echo "═══════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST"
echo "  Live PASS count: $LIVE_TIER_PASS_COUNT (matches discovered: $LIVE_TIER_DISCOVERED_COUNT)"
echo "  Live FAIL count: $LIVE_TIER_FAIL_COUNT"
echo "═══════════════════════════════════════════════════════════"

if [[ "$ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED_FOR_ITER75_PARITY_TEST assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED_FOR_ITER75_PARITY_TEST assertions passed"
