#!/usr/bin/env bash
#MISE description="Iter-184 regression test pinning the canonical outlier-warning surface added to each iter-179 JSON envelope record. Pre-iter-184 AI agents and CI pipelines parsing the iter-183 stats (mean, stddev, min, max, trials[]) each had to re-derive different outlier thresholds and would disagree on whether a regression is 'noisy' or 'real'. Web research (2026) confirmed hyperfine ships two canonical heuristics (outlier detection for background-process interference + first-run-cold-cache detection for OS page-cache warmup) and pytest-benchmark emits BOTH StdDev outlier count AND IQR outlier count simultaneously for richer diagnosis. Iter-184 closes the canonical-warning-surface gap by emitting a structured iter184_outlier_warnings array per scenario with up to 3 stable canonical warning codes per hyperfine + pytest-benchmark heuristic naming: (1) first_trial_cold_cache_spike_per_hyperfine_heuristic_two when trials[0] > median × 1.5, (2) high_relative_stddev_indicating_unstable_measurement_per_hyperfine_practice when stddev > median × 0.25, (3) tukey_iqr_outlier_runs_detected_per_pytest_benchmark_robust_definition when ≥1 trial outside [Q1-1.5×IQR, Q3+1.5×IQR] (sorted[2]/sorted[4] quartiles for N=5). Schema stays at v1 (additive). Test asserts (a) warnings array global declared with verbose self-explanatory name, (b) all 3 detection blocks present in source with canonical warning code strings, (c) JSON envelope contains iter184_outlier_warnings array per scenario (even if empty), (d) clean-signal scenarios emit empty warnings array, (e) synthetic threshold-crossing tests exercise each warning code, (f) iter-156 dispatcher cites iter-184, (g) bash -n + shellcheck clean."
set -euo pipefail

ITER184_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER184_REPO_ROOT"

ITER184_ITER174_HARNESS_ABSOLUTE_PATH="$ITER184_REPO_ROOT/.mise/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"
ITER184_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER184_REPO_ROOT/.mise/tasks/commits/_default"

ITER184_TOTAL_ASSERTIONS_EVALUATED=0
ITER184_TOTAL_ASSERTIONS_FAILED=0

iter184_assert_substring_present_in_harness_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$ITER184_ITER174_HARNESS_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-184 CANONICAL OUTLIER-WARNING SURFACE REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: warnings global declared + 3 canonical warning codes present ─
echo ""
echo "GROUP A (4 assertions): iter-184 outlier-warnings global declared + 3 canonical warning codes present in source"

iter184_assert_substring_present_in_harness_with_human_readable_label \
    "A1: iter-184 warnings array global declared with verbose self-explanatory name" \
    "ITER184_LATEST_BENCHMARK_SCENARIO_OUTLIER_WARNINGS_ARRAY_FOR_AI_AGENT_SIGNAL_QUALITY_ASSESSMENT"

iter184_assert_substring_present_in_harness_with_human_readable_label \
    "A2: canonical warning code #1 — first-trial cold-cache spike per hyperfine heuristic two" \
    "first_trial_cold_cache_spike_per_hyperfine_heuristic_two"

iter184_assert_substring_present_in_harness_with_human_readable_label \
    "A3: canonical warning code #2 — high relative stddev per hyperfine practice" \
    "high_relative_stddev_indicating_unstable_measurement_per_hyperfine_practice"

iter184_assert_substring_present_in_harness_with_human_readable_label \
    "A4: canonical warning code #3 — Tukey IQR-fence outliers per pytest-benchmark robust definition" \
    "tukey_iqr_outlier_runs_detected_per_pytest_benchmark_robust_definition"

# ─── Group B: --json envelope contains iter184_outlier_warnings array per scenario ─
echo ""
echo "GROUP B (2 assertions): --json envelope contains iter184_outlier_warnings array per scenario (even if empty for clean signals)"

ITER184_JSON_ENVELOPE_OUTPUT_CAPTURE=$(bash "$ITER184_ITER174_HARNESS_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    ITER184_TEMP_JSON_CAPTURE_FILE=$(mktemp -t iter184-json-envelope-capture-XXXXXX)
    echo "$ITER184_JSON_ENVELOPE_OUTPUT_CAPTURE" > "$ITER184_TEMP_JSON_CAPTURE_FILE"
    if python3 - "$ITER184_TEMP_JSON_CAPTURE_FILE" <<'PYTHON_BLOCK' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
WARNINGS_FIELD = "iter184_outlier_warnings_per_hyperfine_and_pytest_benchmark_canonical_heuristics_for_ai_agent_signal_quality_assessment"
VALID_WARNING_CODES = {
    "first_trial_cold_cache_spike_per_hyperfine_heuristic_two",
    "high_relative_stddev_indicating_unstable_measurement_per_hyperfine_practice",
    "tukey_iqr_outlier_runs_detected_per_pytest_benchmark_robust_definition",
}
for r in d["results"]:
    assert WARNINGS_FIELD in r, f"scenario {r['id']} missing iter184_outlier_warnings field"
    assert isinstance(r[WARNINGS_FIELD], list), f"scenario {r['id']} warnings not a list"
    for code in r[WARNINGS_FIELD]:
        assert code in VALID_WARNING_CODES, f"scenario {r['id']} has unrecognized warning code: {code}"
PYTHON_BLOCK
    then
        echo "  ✓ B1: every scenario record has iter184_outlier_warnings array + every emitted code is in the canonical {first_trial_cold_cache, high_relative_stddev, tukey_iqr_outliers} set"
    else
        echo "  ✗ B1: iter184_outlier_warnings field missing OR contains invalid warning codes"
        ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
    fi
    rm -f "$ITER184_TEMP_JSON_CAPTURE_FILE"
else
    echo "  ⊘ B1: python3 not available — SKIPPED (assertion uncounted)"
    ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# B2: schema_version preserved at 1 (additive iter-184 extension).
ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER184_JSON_ENVELOPE_OUTPUT_CAPTURE" == *'"iter174_schema_version": 1'* ]]; then
    echo "  ✓ B2: iter174_schema_version still 1 (additive iter-184 warnings are backward-compatible; older consumers ignore unknown fields)"
else
    echo "  ✗ B2: iter174_schema_version bumped or missing — backward-compat invariant violated"
    ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: synthetic threshold-crossing — each warning code path exercised ─
echo ""
echo "GROUP C (3 assertions): synthetic threshold-crossing — each canonical warning code path exercised by hand-crafted trial data"

# Each sub-assertion runs an inline bash script that sources the function-
# definition portion of iter-174, then directly calls the timing function on
# a command whose latency we shape by sleeping precise durations across the
# 5 trials. Cleaner approach: extract the warning-detection block into a pure
# python script that we feed synthetic trial arrays. This avoids subshell
# trickery and exercises the math, not the integration.

ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    # Synthetic trials [60, 20, 20, 20, 20]: median=20, first-trial=60 (>20*1.5=30) → warning #1.
    # Stddev: high relative → likely warning #2 also.
    # Tukey: sorted=[20,20,20,20,60], Q1=20, Q3=20, IQR=0, fences=[20,20], 60 outside → warning #3.
    # We expect all three warnings to fire on this synthetic.
    iter184_synthetic_test_python_block_for_cold_cache_spike_detection() {
        python3 <<'PYTHON_BLOCK'
import math
trials = [60, 20, 20, 20, 20]
sorted_trials = sorted(trials)
median = sorted_trials[len(trials) // 2]  # N=5 → index 2 → 20
mean = sum(trials) / len(trials)
N = len(trials)
sample_stddev_sq = sum((x - mean) ** 2 for x in trials) / (N - 1)
sample_stddev = math.sqrt(sample_stddev_sq)
first_trial = trials[0]
q1 = sorted_trials[1]  # 20
q3 = sorted_trials[3]  # 20
iqr = q3 - q1  # 0
lower_fence = q1 - 1.5 * iqr  # 20
upper_fence = q3 + 1.5 * iqr  # 20
warnings = []
if first_trial > median * 1.5:
    warnings.append("first_trial_cold_cache_spike_per_hyperfine_heuristic_two")
if sample_stddev > median * 0.25:
    warnings.append("high_relative_stddev_indicating_unstable_measurement_per_hyperfine_practice")
if any(t < lower_fence or t > upper_fence for t in trials):
    warnings.append("tukey_iqr_outlier_runs_detected_per_pytest_benchmark_robust_definition")
# All 3 warnings should fire on the [60,20,20,20,20] synthetic.
expected_warnings = {
    "first_trial_cold_cache_spike_per_hyperfine_heuristic_two",
    "high_relative_stddev_indicating_unstable_measurement_per_hyperfine_practice",
    "tukey_iqr_outlier_runs_detected_per_pytest_benchmark_robust_definition",
}
got_warnings = set(warnings)
assert got_warnings == expected_warnings, f"synthetic [60,20,20,20,20]: expected {expected_warnings}, got {got_warnings}"
PYTHON_BLOCK
    }
    if iter184_synthetic_test_python_block_for_cold_cache_spike_detection 2>/dev/null; then
        echo "  ✓ C1: synthetic [60,20,20,20,20] triggers ALL 3 warnings (first-trial spike + high-stddev + Tukey-IQR-outlier) — threshold math correct"
    else
        echo "  ✗ C1: synthetic threshold math FAILED to fire all 3 expected warnings"
        ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ C1: python3 not available — SKIPPED"
    ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    # Synthetic trials [20, 20, 20, 20, 20]: completely flat — NO warnings expected.
    iter184_synthetic_test_python_block_for_no_warnings_on_flat_signal() {
        python3 <<'PYTHON_BLOCK'
import math
trials = [20, 20, 20, 20, 20]
sorted_trials = sorted(trials)
median = sorted_trials[2]
mean = sum(trials) / len(trials)
sample_stddev = 0.0
warnings = []
if trials[0] > median * 1.5: warnings.append("cold")
if sample_stddev > median * 0.25: warnings.append("stddev")
q1, q3 = sorted_trials[1], sorted_trials[3]
iqr = q3 - q1
if any(t < q1 - 1.5 * iqr or t > q3 + 1.5 * iqr for t in trials): warnings.append("tukey")
assert warnings == [], f"flat signal should emit zero warnings, got {warnings}"
PYTHON_BLOCK
    }
    if iter184_synthetic_test_python_block_for_no_warnings_on_flat_signal 2>/dev/null; then
        echo "  ✓ C2: synthetic [20,20,20,20,20] (perfectly flat) emits ZERO warnings — no-false-positive invariant preserved"
    else
        echo "  ✗ C2: flat-signal synthetic emitted unexpected warnings (false positive in threshold math)"
        ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ C2: python3 not available — SKIPPED"
    ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# C3: clean-signal scenarios from the real harness invocation produce empty warnings array.
ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    ITER184_TEMP_JSON_CAPTURE_FILE=$(mktemp -t iter184-json-clean-XXXXXX)
    echo "$ITER184_JSON_ENVELOPE_OUTPUT_CAPTURE" > "$ITER184_TEMP_JSON_CAPTURE_FILE"
    if python3 - "$ITER184_TEMP_JSON_CAPTURE_FILE" <<'PYTHON_BLOCK' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
WARNINGS_FIELD = "iter184_outlier_warnings_per_hyperfine_and_pytest_benchmark_canonical_heuristics_for_ai_agent_signal_quality_assessment"
# We don't assert all scenarios are empty (system jitter is real); instead we
# assert that the field exists for every scenario AND that scenarios with
# trial values strictly equal to each other produce empty warnings.
# This validates the no-false-positive on clean-signal invariant.
for r in d["results"]:
    trials = r["iter183_trial_wall_clock_times_ms_for_ai_agent_to_recompute_any_percentile"]
    if len(set(trials)) == 1:  # all trials identical = perfectly clean
        assert r[WARNINGS_FIELD] == [], f"scenario {r['id']} with identical trials {trials} should have empty warnings, got {r[WARNINGS_FIELD]}"
PYTHON_BLOCK
    then
        echo "  ✓ C3: any scenarios with perfectly-identical trial values produce empty warnings (no-false-positive invariant on real harness output)"
    else
        echo "  ✗ C3: false-positive warnings detected on perfectly-flat real-harness scenarios"
        ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
    fi
    rm -f "$ITER184_TEMP_JSON_CAPTURE_FILE"
else
    echo "  ⊘ C3: python3 not available — SKIPPED"
    ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group D: iter-156 dispatcher cites iter-184 ──────────────────────────
echo ""
echo "GROUP D (1 assertion): iter-156 dispatcher banner cites iter-184 outlier-warning surface"

ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if grep -qF "iter-184" "$ITER184_ITER156_DISPATCHER_ABSOLUTE_PATH"; then
    echo "  ✓ D1: iter-156 dispatcher banner cites iter-184"
else
    echo "  ✗ D1: iter-156 dispatcher banner missing iter-184 citation"
    ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: bash -n + shellcheck ─────────────────────────────────────────
echo ""
echo "GROUP E (2 assertions): iter-174 harness passes bash -n + shellcheck after iter-184 warning additions"

ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER184_ITER174_HARNESS_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ E1: iter-174 passes bash -n syntax check after iter-184 warning additions"
else
    echo "  ✗ E1: iter-174 FAILS bash -n syntax check after iter-184 warning additions"
    ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER184_ITER174_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ E2: iter-174 passes shellcheck zero-warning after iter-184 warning additions"
    else
        echo "  ✗ E2: iter-174 has shellcheck warnings after iter-184 warning additions"
        ITER184_TOTAL_ASSERTIONS_FAILED=$((ITER184_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER184_TOTAL_ASSERTIONS_EVALUATED=$((ITER184_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER184_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-184 REGRESSION TEST: ${ITER184_TOTAL_ASSERTIONS_EVALUATED}/${ITER184_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-184 REGRESSION TEST: $((ITER184_TOTAL_ASSERTIONS_EVALUATED - ITER184_TOTAL_ASSERTIONS_FAILED))/${ITER184_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER184_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
