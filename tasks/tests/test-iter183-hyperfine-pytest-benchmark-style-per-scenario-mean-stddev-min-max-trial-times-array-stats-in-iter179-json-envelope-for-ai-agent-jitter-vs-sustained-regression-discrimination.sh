#!/usr/bin/env bash
#MISE description="Iter-183 regression test pinning the hyperfine-and-pytest-benchmark-style per-scenario statistical fields added to each iter-179 JSON envelope record. Pre-iter-183 the envelope emitted only median_ms + cap_ms + headroom_pct_signed + verdict per scenario. Web research (2026) confirmed hyperfine emits mean + stddev + median + min + max + times[] array, with times[] being 'the most valuable field for sophisticated regression detection' because AI agents and CI pipelines can re-derive any percentile / bootstrap CI / non-parametric test downstream. Pytest-benchmark emits the same plus iqr + q1 + q3 + outliers + ops. Pre-iter-183 the cc-skills envelope LACKED this: when a future iter ships a REGRESS verdict the operator could not distinguish 'one-off jitter spike' from 'sustained degradation' without re-running. Iter-183 closes the gap additively (iter174_schema_version stays at 1, backward-compatible per JSON-best-practice — older consumers ignore unknown fields). Test asserts (a) timing function renamed to encode full-stats responsibility, (b) 5 stats globals + 1 trials array global declared with verbose self-explanatory names, (c) JSON envelope contains 5 new stats fields + raw trials array per scenario, (d) math sanity: median ∈ [min, max], mean ∈ [min, max], stddev ≥ 0, trials array length == N_TRIALS, (e) human-mode output unchanged (still median-only, regression-safe), (f) schema_version invariant preserved at 1, (g) iter-156 dispatcher banner cites iter-183 hyperfine industry parity, (h) bash -n + shellcheck clean."
set -euo pipefail

ITER183_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER183_REPO_ROOT"

ITER183_ITER174_HARNESS_ABSOLUTE_PATH="$ITER183_REPO_ROOT/.mise/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"
ITER183_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER183_REPO_ROOT/.mise/tasks/commits/_default"

ITER183_TOTAL_ASSERTIONS_EVALUATED=0
ITER183_TOTAL_ASSERTIONS_FAILED=0

iter183_assert_substring_present_in_harness_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$ITER183_ITER174_HARNESS_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-183 HYPERFINE-PARITY PER-SCENARIO STATS REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: timing function renamed + 6 globals declared ────────────────
echo ""
echo "GROUP A (7 assertions): timing function + 5 stats globals + 1 trials array global declared with verbose self-explanatory names"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A1: timing function name encodes full-stats responsibility (not just median)" \
    "iter174_measure_median_and_iter183_full_stats_across_n_trials_using_bash5_epochrealtime_zero_fork_builtin_with_perl_time_hires_graceful_fallback_for_bash4_or_older"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A2: median global preserves iter-174 baseline-cap-comparison contract" \
    "ITER183_LATEST_BENCHMARK_SCENARIO_TRIAL_BATCH_MEDIAN_MS_FOR_PINNED_BASELINE_CAP_COMPARISON_PRESERVED_FROM_ITER174"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A3: mean global cites hyperfine + pytest-benchmark industry parity rationale" \
    "ITER183_LATEST_BENCHMARK_SCENARIO_TRIAL_BATCH_MEAN_MS_FOR_HYPERFINE_AND_PYTEST_BENCHMARK_INDUSTRY_PARITY_HEADLINE_METRIC"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A4: stddev global cites noise-floor regression-significance-testing rationale" \
    "ITER183_LATEST_BENCHMARK_SCENARIO_TRIAL_BATCH_STDDEV_MS_FOR_NOISE_FLOOR_BASED_REGRESSION_SIGNIFICANCE_TESTING"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A5: min global cites best-case-floor stable-cross-run-metric rationale" \
    "ITER183_LATEST_BENCHMARK_SCENARIO_TRIAL_BATCH_MIN_MS_FOR_BEST_CASE_FLOOR_STABLE_CROSS_RUN_METRIC"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A6: max global cites tail-latency-and-interference-indicator rationale" \
    "ITER183_LATEST_BENCHMARK_SCENARIO_TRIAL_BATCH_MAX_MS_FOR_TAIL_LATENCY_AND_INTERFERENCE_INDICATOR"

iter183_assert_substring_present_in_harness_with_human_readable_label \
    "A7: per-trial times array global cites AI-agent recompute-any-percentile rationale" \
    "ITER183_LATEST_BENCHMARK_SCENARIO_PER_TRIAL_WALL_CLOCK_TIMES_MS_ARRAY_FOR_AI_AGENT_TO_RECOMPUTE_ANY_PERCENTILE"

# ─── Group B: --json envelope contains 5 new stats fields + raw trials ────
echo ""
echo "GROUP B (3 assertions): --json envelope per-scenario records contain iter-183 hyperfine-parity stats fields"

ITER183_JSON_ENVELOPE_OUTPUT_CAPTURE=$(bash "$ITER183_ITER174_HARNESS_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    ITER183_TEMP_JSON_CAPTURE_FILE=$(mktemp -t iter183-json-envelope-capture-XXXXXX)
    echo "$ITER183_JSON_ENVELOPE_OUTPUT_CAPTURE" > "$ITER183_TEMP_JSON_CAPTURE_FILE"
    if python3 - "$ITER183_TEMP_JSON_CAPTURE_FILE" <<'PYTHON_BLOCK' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for r in d["results"]:
    required_iter183_fields = ["iter183_mean_ms", "iter183_stddev_ms", "iter183_min_ms", "iter183_max_ms", "iter183_trial_wall_clock_times_ms_for_ai_agent_to_recompute_any_percentile"]
    for field in required_iter183_fields:
        assert field in r, f"scenario {r['id']} missing field {field}"
    assert all(isinstance(r[field], int) for field in ["iter183_mean_ms", "iter183_stddev_ms", "iter183_min_ms", "iter183_max_ms"]), f"scenario {r['id']} stats not all int"
    assert isinstance(r["iter183_trial_wall_clock_times_ms_for_ai_agent_to_recompute_any_percentile"], list), f"scenario {r['id']} trials not a list"
PYTHON_BLOCK
    then
        echo "  ✓ B1: every scenario record contains iter183_mean_ms + iter183_stddev_ms + iter183_min_ms + iter183_max_ms + iter183_trial_wall_clock_times_ms array (all 6 scenarios, all 5 fields)"
    else
        echo "  ✗ B1: scenario records missing iter-183 stats fields OR types invalid"
        echo "      (envelope head: $(echo "$ITER183_JSON_ENVELOPE_OUTPUT_CAPTURE" | head -15))"
        ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
    fi
    rm -f "$ITER183_TEMP_JSON_CAPTURE_FILE"
else
    echo "  ⊘ B1: python3 not available — SKIPPED (assertion uncounted)"
    ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# B2: math sanity — for every scenario, median ∈ [min, max], mean ∈ [min, max], stddev ≥ 0
ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    ITER183_TEMP_JSON_CAPTURE_FILE=$(mktemp -t iter183-json-math-sanity-XXXXXX)
    echo "$ITER183_JSON_ENVELOPE_OUTPUT_CAPTURE" > "$ITER183_TEMP_JSON_CAPTURE_FILE"
    if python3 - "$ITER183_TEMP_JSON_CAPTURE_FILE" <<'PYTHON_BLOCK' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for r in d["results"]:
    median = r["median_ms"]
    mean = r["iter183_mean_ms"]
    stddev = r["iter183_stddev_ms"]
    min_v = r["iter183_min_ms"]
    max_v = r["iter183_max_ms"]
    trials = r["iter183_trial_wall_clock_times_ms_for_ai_agent_to_recompute_any_percentile"]
    assert min_v <= median <= max_v, f"scenario {r['id']} median {median} not in [min={min_v}, max={max_v}]"
    assert min_v <= mean <= max_v, f"scenario {r['id']} mean {mean} not in [min={min_v}, max={max_v}]"
    assert stddev >= 0, f"scenario {r['id']} stddev {stddev} negative"
    assert len(trials) == 5, f"scenario {r['id']} trials array length {len(trials)} != 5 (N_TRIALS pin)"
    assert min(trials) == min_v, f"scenario {r['id']} min(trials)={min(trials)} != min_v={min_v}"
    assert max(trials) == max_v, f"scenario {r['id']} max(trials)={max(trials)} != max_v={max_v}"
PYTHON_BLOCK
    then
        echo "  ✓ B2: math sanity across all 6 scenarios — median ∈ [min, max], mean ∈ [min, max], stddev ≥ 0, |trials| == 5, min/max consistent with trials"
    else
        echo "  ✗ B2: math sanity check FAILED across at least one scenario"
        ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
    fi
    rm -f "$ITER183_TEMP_JSON_CAPTURE_FILE"
else
    echo "  ⊘ B2: python3 not available — SKIPPED (assertion uncounted)"
    ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# B3: schema_version invariant preserved at 1 (additive iter-183 extension, backward-compatible).
ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER183_JSON_ENVELOPE_OUTPUT_CAPTURE" == *'"iter174_schema_version": 1'* ]]; then
    echo "  ✓ B3: iter174_schema_version still 1 (additive iter-183 stats are backward-compatible; older consumers ignore unknown fields)"
else
    echo "  ✗ B3: iter174_schema_version bumped or missing — backward-compat invariant violated"
    ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: human-mode output unchanged (median-only, regression-safe) ──
echo ""
echo "GROUP C (1 assertion): human-mode output unchanged — still median-only output, no iter-183 noise leaked into operator text"

ITER183_HUMAN_MODE_OUTPUT_CAPTURE=$(bash "$ITER183_ITER174_HARNESS_ABSOLUTE_PATH" 2>&1 || true)

ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER183_HUMAN_MODE_OUTPUT_CAPTURE" == *"7/7 assertions PASSED"* ]] && \
   [[ "$ITER183_HUMAN_MODE_OUTPUT_CAPTURE" != *"iter183_mean_ms"* ]] && \
   [[ "$ITER183_HUMAN_MODE_OUTPUT_CAPTURE" != *"iter183_stddev_ms"* ]] && \
   [[ "$ITER183_HUMAN_MODE_OUTPUT_CAPTURE" != *"iter183_trial_wall_clock"* ]]; then
    echo "  ✓ C1: human-mode still 7/7 PASS + no iter-183 stats leaked into text output (still median-only headline per operator UX)"
else
    echo "  ✗ C1: human-mode regressed OR iter-183 stats leaked into text output"
    echo "      (tail: $(echo "$ITER183_HUMAN_MODE_OUTPUT_CAPTURE" | tail -3))"
    ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: iter-156 dispatcher cites iter-183 ──────────────────────────
echo ""
echo "GROUP D (1 assertion): iter-156 dispatcher banner cites iter-183 hyperfine industry parity"

ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if grep -qF "iter-183" "$ITER183_ITER156_DISPATCHER_ABSOLUTE_PATH"; then
    echo "  ✓ D1: iter-156 dispatcher banner cites iter-183"
else
    echo "  ✗ D1: iter-156 dispatcher banner missing iter-183 citation"
    ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: bash -n + shellcheck ─────────────────────────────────────────
echo ""
echo "GROUP E (2 assertions): iter-174 harness passes bash -n + shellcheck after iter-183 stats additions"

ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER183_ITER174_HARNESS_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ E1: iter-174 passes bash -n syntax check after iter-183 stats additions"
else
    echo "  ✗ E1: iter-174 FAILS bash -n syntax check after iter-183 stats additions"
    ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER183_ITER174_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ E2: iter-174 passes shellcheck zero-warning after iter-183 stats additions"
    else
        echo "  ✗ E2: iter-174 has shellcheck warnings after iter-183 stats additions"
        ITER183_TOTAL_ASSERTIONS_FAILED=$((ITER183_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER183_TOTAL_ASSERTIONS_EVALUATED=$((ITER183_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER183_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-183 REGRESSION TEST: ${ITER183_TOTAL_ASSERTIONS_EVALUATED}/${ITER183_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-183 REGRESSION TEST: $((ITER183_TOTAL_ASSERTIONS_EVALUATED - ITER183_TOTAL_ASSERTIONS_FAILED))/${ITER183_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER183_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
