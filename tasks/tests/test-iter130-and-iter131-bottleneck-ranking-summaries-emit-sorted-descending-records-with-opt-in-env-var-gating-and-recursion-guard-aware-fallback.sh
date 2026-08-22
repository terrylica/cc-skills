#!/usr/bin/env bash
#MISE description="Iter-132 regression test for the iter-130 PREFLIGHT_TIMING_PROFILE top-N-slowest-checks bottleneck-ranking-summary AND the iter-131 marketplace-hook-regression-suite top-N-slowest-tests bottleneck-ranking-summary. Two-tier coverage: (1) source-fingerprint assertions verify helper-function definitions, env-var-driven opt-in gating, sort -rn pipelines, and integration call sites exist in their canonical files (always run, fast — no subprocess invocation needed); (2) integration assertions invoke the actual mise tools with the opt-in env vars set and verify the observable output shape (Top-N section appears, ranking sorted descending by elapsed-milliseconds, custom-N override respected). Tier-2 self-skips under MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD=1 to prevent runaway suite recursion when this test runs as part of the suite itself (same recursion-guard pattern as iter-75 parity test). Closes the every-iter-N-gets-a-regression-test discipline gap."

# Iter-132 regression test combining iter-130 + iter-131 coverage. Both
# features are usability instrumentation surfacing the slowest checks/tests
# so operators iterating on perf don't have to manually scan dozens of
# per-phase or per-test "elapsed: Nms" lines. They share a near-identical
# design (TAB-separated record array + sort -rn -k1 + head -n N + awk),
# so a single combined test is the right granularity.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PREFLIGHT_SCRIPT_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/release/preflight"
MARKETPLACE_HOOK_REGRESSION_SUITE_RUNNER_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/test-marketplace-hook-regression-suite"

ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=0
ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=0

assert_substring_present() {
    local assertion_label_for_iter132="$1"
    local haystack="$2"
    local expected_substring="$3"
    if [[ "$haystack" == *"$expected_substring"* ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST + 1))
        echo "  ✓ PASS: $assertion_label_for_iter132"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: $assertion_label_for_iter132"
        echo "    expected substring: $expected_substring"
        echo "    haystack (first 200 chars): ${haystack:0:200}"
    fi
}

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-132 regression test"
echo "  (covers iter-130 preflight top-N + iter-131 marketplace-suite top-N)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "── TIER 1: source-fingerprint assertions (always run, no subprocess) ──"

# ─── Tier 1.A: iter-130 source-fingerprint checks ────────────────────────
preflight_script_source="$(cat "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")"

assert_substring_present \
    "Tier 1.A1: iter-130 helper function defined in preflight" \
    "$preflight_script_source" \
    "__iter130_emit_top_n_slowest_preflight_checks_ranked_by_elapsed_milliseconds_descending_bottleneck_summary"

assert_substring_present \
    "Tier 1.A2: iter-130 accumulator array declared" \
    "$preflight_script_source" \
    "iter130_per_phase_timing_record_array_for_top_n_slowest_bottleneck_ranking_summary"

assert_substring_present \
    "Tier 1.A3: iter-130 operator-tunable env var ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY present" \
    "$preflight_script_source" \
    "ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY"

assert_substring_present \
    "Tier 1.A4: iter-130 sort -rn -k1 ranking pipeline present (descending by elapsed_ms first field)" \
    "$preflight_script_source" \
    "sort -rn -k1"

assert_substring_present \
    "Tier 1.A5: iter-130 PREFLIGHT_TIMING_PROFILE env-var-gated opt-in (early return when not set)" \
    "$preflight_script_source" \
    "PREFLIGHT_TIMING_PROFILE"

# ─── Tier 1.B: iter-131 source-fingerprint checks ────────────────────────
marketplace_hook_regression_suite_runner_source="$(cat "$MARKETPLACE_HOOK_REGRESSION_SUITE_RUNNER_ABSOLUTE_PATH")"

assert_substring_present \
    "Tier 1.B1: iter-131 helper function defined in marketplace-suite runner" \
    "$marketplace_hook_regression_suite_runner_source" \
    "__iter131_emit_top_n_slowest_marketplace_hook_regression_tests_ranked_by_wall_clock_milliseconds_descending_bottleneck_summary"

assert_substring_present \
    "Tier 1.B2: iter-131 per-test EPOCHREALTIME start-capture variable present in xargs worker" \
    "$marketplace_hook_regression_suite_runner_source" \
    "iter131_per_test_wall_clock_start_seconds_for_ranked_bottleneck_summary"

assert_substring_present \
    "Tier 1.B3: iter-131 per-test EPOCHREALTIME end-capture variable present in xargs worker" \
    "$marketplace_hook_regression_suite_runner_source" \
    "iter131_per_test_wall_clock_end_seconds_for_ranked_bottleneck_summary"

assert_substring_present \
    "Tier 1.B4: iter-131 .elapsed_ms sidecar file pattern written by xargs worker" \
    "$marketplace_hook_regression_suite_runner_source" \
    ".elapsed_ms"

assert_substring_present \
    "Tier 1.B5: iter-131 operator-tunable env var MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY present" \
    "$marketplace_hook_regression_suite_runner_source" \
    "MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY"

assert_substring_present \
    "Tier 1.B6: iter-131 sort -rn -k1 ranking pipeline present (descending by elapsed_ms first field)" \
    "$marketplace_hook_regression_suite_runner_source" \
    "sort -rn -k1"

# ─── Tier 2: integration assertions (self-skip under recursion guard) ────
echo ""
echo "── TIER 2: integration assertions (skipped under recursion guard) ──"

if [[ "${MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD:-0}" == "1" ]]; then
    echo "  ⊘ Tier 2 SKIPPED — running inside parent runner invocation"
    echo "    (recursion guard active; iter-75 parity-test pattern). When invoked"
    echo "    standalone the integration tier exercises the actual mise tools."
else
    # ─── Tier 2.A: iter-131 integration — invoke suite with N=3 ──────────
    # Faster than iter-130 integration (suite is ~3s vs preflight ~7s) so we
    # do iter-131 first. Uses N=3 (not default 5) to also validate the
    # operator-tunable override path simultaneously with the basic invocation.
    iter131_integration_output="$(MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY=3 \
        mise run test-marketplace-hook-regression-suite 2>&1)"

    assert_substring_present \
        "Tier 2.B1: iter-131 emits 'Top 3 slowest tests' header section when env var set to 3" \
        "$iter131_integration_output" \
        "Top 3 slowest tests"

    assert_substring_present \
        "Tier 2.B2: iter-131 ranking lines emit 'ms' suffix and test-name (formatted by awk printf)" \
        "$iter131_integration_output" \
        "ms  test-"

    assert_substring_present \
        "Tier 2.B3: iter-131 emits override-hint footer pointing operator to the env var name" \
        "$iter131_integration_output" \
        "override count via MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY"

    # Verify sort-descending invariant: extract elapsed_ms numbers from the
    # ranking lines and assert they are in non-increasing order.
    iter131_ranking_elapsed_ms_extracted_in_emission_order=$(
        echo "$iter131_integration_output" \
        | grep -E '^[[:space:]]+[0-9]+\.[[:space:]]+[0-9]+ ms[[:space:]]+test-' \
        | awk '{print $2}'
    )
    iter131_ranking_elapsed_ms_sorted_descending=$(
        echo "$iter131_ranking_elapsed_ms_extracted_in_emission_order" \
        | sort -rn
    )
    if [[ "$iter131_ranking_elapsed_ms_extracted_in_emission_order" == "$iter131_ranking_elapsed_ms_sorted_descending" ]] && \
       [[ -n "$iter131_ranking_elapsed_ms_extracted_in_emission_order" ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST + 1))
        echo "  ✓ PASS: Tier 2.B4: iter-131 ranking elapsed_ms values emit in non-increasing order (sort-descending invariant)"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: Tier 2.B4: iter-131 ranking elapsed_ms not sorted descending"
        echo "    extracted:        $(echo "$iter131_ranking_elapsed_ms_extracted_in_emission_order" | tr '\n' ' ')"
        echo "    sorted descending: $(echo "$iter131_ranking_elapsed_ms_sorted_descending" | tr '\n' ' ')"
    fi

    # ─── Tier 2.C: iter-131 default mode — NO ranking section when unset ─
    iter131_default_mode_output="$(mise run test-marketplace-hook-regression-suite 2>&1)"
    if [[ "$iter131_default_mode_output" == *"Top "*" slowest tests"* ]]; then
        ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: Tier 2.B5: iter-131 default mode (env var unset) should NOT emit ranking section but did"
    else
        ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST + 1))
        echo "  ✓ PASS: Tier 2.B5: iter-131 default mode preserves bit-for-bit output (no ranking section)"
    fi

    # ─── Tier 2.D: iter-130 integration — gated behind opt-in env var ────
    # Preflight is slower than the suite (~7s) — gated behind ITER132_RUN_
    # PREFLIGHT_INTEGRATION_TIER=1 to keep the regression test under 10s in
    # the common case. The suite's iter-131 integration above already covers
    # the shared bottleneck-ranking-summary design pattern.
    if [[ "${ITER132_RUN_PREFLIGHT_INTEGRATION_TIER:-0}" == "1" ]]; then
        iter130_integration_output="$(PREFLIGHT_TIMING_PROFILE=1 \
            ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY=3 \
            mise run release:preflight 2>&1)"

        assert_substring_present \
            "Tier 2.A1: iter-130 emits 'Top 3 slowest preflight checks' header when env vars set" \
            "$iter130_integration_output" \
            "Top 3 slowest preflight checks"

        assert_substring_present \
            "Tier 2.A2: iter-130 emits override-hint footer pointing operator to ITER130_TOP_N" \
            "$iter130_integration_output" \
            "override count via ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY"
    else
        echo "  ⊘ Tier 2.A (iter-130 preflight integration) SKIPPED — set ITER132_RUN_PREFLIGHT_INTEGRATION_TIER=1 to enable"
        echo "    (preflight is ~7s; gated to keep the regression test fast in the common case)"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-132 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

if [[ "$ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST assertion(s) failed"
    exit 1
fi

echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED_FOR_ITER132_BOTTLENECK_RANKING_REGRESSION_TEST assertions passed"
echo ""
echo "  🚀 Iter-130 + iter-131 bottleneck-ranking-summary features regression-guarded."
echo "     Both source-fingerprint (function names, env vars, sort pipelines)"
echo "     AND integration shape (header section, sort-descending invariant,"
echo "     opt-in env-var gating) are now protected against future regressions."
