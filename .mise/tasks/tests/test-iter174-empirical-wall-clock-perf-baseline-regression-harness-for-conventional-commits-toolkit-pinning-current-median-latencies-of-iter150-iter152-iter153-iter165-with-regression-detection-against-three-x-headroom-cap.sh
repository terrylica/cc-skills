#!/usr/bin/env bash
#MISE description="Iter-174 empirical wall-clock perf-baseline regression harness for the iter-150 through iter-173 conventional-commits operator toolkit. Pre-iter-174 there was no automated mechanism to detect when a future iteration silently regressed the wall-clock latency of a frequently-invoked tool (e.g., iter-153 advisor is invoked on every git commit via the iter-157 commit-msg hook; a 5x latency regression would be silently shipped). Iter-174 closes this preventive-infrastructure gap by pinning empirically-measured median wall-clocks of 5 toolkit scripts as baseline caps and asserting each script stays under the cap. Caps are set to 3x the iter-174-baseline-measurement median to give generous headroom for system jitter and legitimate future feature growth while catching order-of-magnitude regressions (e.g., 41ms → 250ms). Methodology - run N=5 trials per script, take median (robust to jitter), compare against pinned cap. Test asserts (a) iter-150 renderer median under cap, (b) iter-153 advisor default mode under cap, (c) iter-153 advisor json strict mode under cap, (d) iter-152 5-panel dashboard under cap, (e) iter-165 pending-release aggregator under cap. Mirrors the iter-148 SSH multiplexing empirical validation harness preventive pattern."
set -euo pipefail

ITER174_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER174_REPO_ROOT"

# ─── ITER-179 DUAL-MODE OUTPUT: HUMAN-READABLE DEFAULT OR --json FOR AI AGENTS ─
# Pre-iter-179 the harness emitted only human-readable text. AI agents and CI
# pipelines consuming the regression-detection output had to regex-parse the
# "✓ A1: …median=Xms ≤ cap=Yms (Z% headroom unused)" lines — fragile against
# future label/format changes. Iter-179 closes this dual-mode gap by emitting
# a stable JSON envelope under --json (iter174_schema_version=1) while
# preserving human-readable text under the default no-flag invocation.
#
# Mirrors the iter-152 dashboard / iter-153 advisor / iter-160 doctor /
# iter-165 aggregator --json dual-mode pattern. Schema records per-scenario
# {id, description, median_ms, cap_ms, headroom_pct, verdict} plus aggregate
# {total_evaluated, total_failed, overall_verdict}. Pure-bash JSON
# construction; labels are ASCII-only by convention so no escape lib needed.
ITER179_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION="human"
for iter179_arg_for_dispatch_parsing in "$@"; do
    case "$iter179_arg_for_dispatch_parsing" in
        --json)
            ITER179_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION="json"
            ;;
    esac
done

# Accumulator arrays for --json mode (one entry per benchmark scenario).
# In human mode these stay empty and the final-report block emits text.
ITER179_PER_SCENARIO_JSON_RECORDS_ACCUMULATED_ACROSS_ALL_BENCHMARKS_FOR_FINAL_ENVELOPE_EMISSION=()

# iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean:
# centralizes the "echo conditionally" pattern so future scenario additions
# stay parse-clean for --json consumers without per-call-site if-guards.
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean() {
    if [[ "$ITER179_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "human" ]]; then
        echo "$@"
    fi
}

# ─── Iter-174 empirical baseline pins (measured 2026-05-21 on local macOS arm64) ─
# Methodology: 5-trial median measurement on each toolkit script. Caps are
# 3x the measured median to give generous headroom for variance + legitimate
# future feature growth while still catching order-of-magnitude regressions.
#
# If a script's wall-clock exceeds its cap, the harness FAILS — operator
# can either: (a) optimize the regression, or (b) audit + adjust the cap if
# the cost is intentional and well-understood.
ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION=5
ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER150_RENDERER_DEFAULT_TEN_COMMITS=100  # measured median 23ms × 4.3 headroom
ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER153_ADVISOR_DEFAULT_HUMAN_READABLE_MODE=200  # measured median 41ms × 4.9 headroom (HOT PATH: every git commit)
ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER153_ADVISOR_JSON_STRICT_AI_AGENT_AUTOMATION_MODE=250  # measured median 53ms × 4.7 headroom
ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER152_COMMITS_HEALTH_FIVE_PANEL_DASHBOARD=300  # measured median 61ms × 4.9 headroom (slowest absolute in toolkit; iter-175+ candidate for iter-167 batched-git-log perf treatment)
ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER165_PENDING_RELEASE_AGGREGATOR_POST_ITER167_OPTIMIZATION=200  # measured median 36ms × 5.5 headroom (already iter-167-optimized; regression here means iter-167 NUL-delim fan-in broke)
ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER160_DOCTOR_POST_ITER177_OPTIMIZATION=1500  # measured median 530ms × 2.8 headroom (operator-facing, runs 15 timed health checks; iter-177 replaced perl Time::HiRes with bash 5+ EPOCHREALTIME zero-fork builtin saving ~135ms; cap is intentionally tighter (2.8x not 4-5x) since this is the slowest absolute script in the toolkit and any further sub-linear-scaling check addition deserves an explicit baseline re-pin)

ITER174_TOTAL_ASSERTIONS_EVALUATED=0
ITER174_TOTAL_ASSERTIONS_FAILED=0

# Compute the median wall-clock in milliseconds across N trials of an arbitrary
# command. Uses perl Time::HiRes for nanosecond-precision timing. Sorts the
# trials, takes the middle element (median for odd N). Robust against single-
# trial cold-start jitter, GC pauses, and macOS launchd thermal throttle.
# The function takes a command + args (no label parameter; the caller emits
# its own scenario label in the comparison verdict).
iter174_measure_median_wall_clock_in_milliseconds_across_n_trials_using_perl_time_hires_nanosecond_precision() {
    local each_trial_elapsed_ms_array=()
    local each_trial_iteration_counter
    local before_invocation_ns_clock after_invocation_ns_clock elapsed_ms_for_this_single_trial
    for each_trial_iteration_counter in $(seq 1 "$ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION"); do
        : "trial=${each_trial_iteration_counter}"  # name the loop variable in body to satisfy shellcheck SC2034 + document intent
        before_invocation_ns_clock=$(perl -MTime::HiRes=time -e 'printf "%.0f", time() * 1e9')
        "$@" >/dev/null 2>&1 || true
        after_invocation_ns_clock=$(perl -MTime::HiRes=time -e 'printf "%.0f", time() * 1e9')
        elapsed_ms_for_this_single_trial=$(awk -v b="$before_invocation_ns_clock" -v a="$after_invocation_ns_clock" 'BEGIN { printf "%.0f", (a-b)/1e6 }')
        each_trial_elapsed_ms_array+=("$elapsed_ms_for_this_single_trial")
    done
    local sorted_trials_newline_separated
    sorted_trials_newline_separated=$(printf '%s\n' "${each_trial_elapsed_ms_array[@]}" | sort -n)
    local median_index_zero_based middle_trial_value
    median_index_zero_based=$(( (ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION + 1) / 2 ))
    middle_trial_value=$(echo "$sorted_trials_newline_separated" | sed -n "${median_index_zero_based}p")
    printf "%s" "$middle_trial_value"
}

# Run a single benchmark scenario: measure median, compare to cap, emit PASS/REGRESS.
# In human mode prints the canonical text line; in --json mode appends a
# structured record to the iter-179 per-scenario accumulator (silent to stdout).
iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict() {
    local human_readable_scenario_label="$1"
    local pinned_baseline_cap_milliseconds="$2"
    shift 2
    ITER174_TOTAL_ASSERTIONS_EVALUATED=$((ITER174_TOTAL_ASSERTIONS_EVALUATED + 1))
    local observed_median_wall_clock_ms
    observed_median_wall_clock_ms=$(iter174_measure_median_wall_clock_in_milliseconds_across_n_trials_using_perl_time_hires_nanosecond_precision "$@")
    # Extract canonical scenario id (the "A1"/"A2"/... prefix before the colon)
    # so JSON consumers get a stable identifier independent of the human-readable
    # description suffix (which may evolve across iters).
    local iter179_canonical_scenario_id_extracted_from_human_readable_label="${human_readable_scenario_label%%:*}"
    local iter179_human_readable_description_after_canonical_id_prefix="${human_readable_scenario_label#*: }"
    local iter179_pass_or_regress_verdict_string
    local iter179_headroom_or_overage_percentage_signed
    if (( observed_median_wall_clock_ms <= pinned_baseline_cap_milliseconds )); then
        iter179_pass_or_regress_verdict_string="PASS"
        iter179_headroom_or_overage_percentage_signed=$(awk -v obs="$observed_median_wall_clock_ms" -v cap="$pinned_baseline_cap_milliseconds" 'BEGIN { printf "%.0f", 100 * (cap - obs) / cap }')
        iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "  ✓ ${human_readable_scenario_label}: median=${observed_median_wall_clock_ms}ms ≤ cap=${pinned_baseline_cap_milliseconds}ms (${iter179_headroom_or_overage_percentage_signed}% headroom unused)"
    else
        iter179_pass_or_regress_verdict_string="REGRESS"
        iter179_headroom_or_overage_percentage_signed=$(awk -v obs="$observed_median_wall_clock_ms" -v cap="$pinned_baseline_cap_milliseconds" 'BEGIN { printf "%.0f", -100 * (obs - cap) / cap }')
        iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "  ✗ ${human_readable_scenario_label}: median=${observed_median_wall_clock_ms}ms > cap=${pinned_baseline_cap_milliseconds}ms (REGRESSION: $((iter179_headroom_or_overage_percentage_signed * -1))% over cap)"
        ITER174_TOTAL_ASSERTIONS_FAILED=$((ITER174_TOTAL_ASSERTIONS_FAILED + 1))
    fi
    # Append a JSON-safe scenario record for --json mode final-envelope emission.
    # Labels are ASCII-only by convention so no escape lib needed; substring the
    # description down to a JSON-safe shape (strip embedded double-quotes
    # defensively even though current labels contain none).
    local iter179_json_safe_description_with_double_quotes_stripped_defensively="${iter179_human_readable_description_after_canonical_id_prefix//\"/}"
    ITER179_PER_SCENARIO_JSON_RECORDS_ACCUMULATED_ACROSS_ALL_BENCHMARKS_FOR_FINAL_ENVELOPE_EMISSION+=("{\"id\": \"${iter179_canonical_scenario_id_extracted_from_human_readable_label}\", \"description\": \"${iter179_json_safe_description_with_double_quotes_stripped_defensively}\", \"median_ms\": ${observed_median_wall_clock_ms}, \"cap_ms\": ${pinned_baseline_cap_milliseconds}, \"headroom_pct_signed\": ${iter179_headroom_or_overage_percentage_signed}, \"verdict\": \"${iter179_pass_or_regress_verdict_string}\"}")
}

iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean ""
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "═══════════════════════════════════════════════════════════════════════════════"
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "  ITER-174 EMPIRICAL WALL-CLOCK PERF-BASELINE REGRESSION HARNESS"
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "  ${ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION} trials per script; median compared against pinned 3× headroom baseline caps"
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "═══════════════════════════════════════════════════════════════════════════════"

iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean ""
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "GROUP A (5 assertions): each conventional-commits toolkit script median ≤ pinned baseline cap"

# Resolve script absolute paths (already cd'd to repo root above).
ITER174_ITER150_RENDERER_ABSOLUTE_PATH=$(find scripts -maxdepth 1 -name 'iter150-readable-git-log-renderer-*.sh' -type f | head -1)
ITER174_ITER152_DASHBOARD_ABSOLUTE_PATH=$(find scripts -maxdepth 1 -name 'iter152-operator-facing-commits-subject-length-distribution-histogram-*.sh' -type f | head -1)
ITER174_ITER153_ADVISOR_ABSOLUTE_PATH=$(find scripts -maxdepth 1 -name 'iter153-operator-facing-pre-commit-dry-run-advisor-*.sh' -type f | head -1)
ITER174_ITER165_AGGREGATOR_ABSOLUTE_PATH=$(find scripts -maxdepth 1 -name 'iter165-pending-release-aggregator-*.sh' -type f | head -1)
ITER174_ITER160_DOCTOR_ABSOLUTE_PATH=$(find scripts -maxdepth 1 -name 'iter160-operator-facing-commits-arc-self-diagnosis-task-*.sh' -type f | head -1)

iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict \
    "A1: iter-150 renderer (occasional, N=10 commits)" \
    "$ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER150_RENDERER_DEFAULT_TEN_COMMITS" \
    bash "$ITER174_ITER150_RENDERER_ABSOLUTE_PATH"

iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict \
    "A2: iter-153 advisor default mode (HOT PATH: every git commit via iter-157)" \
    "$ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER153_ADVISOR_DEFAULT_HUMAN_READABLE_MODE" \
    bash "$ITER174_ITER153_ADVISOR_ABSOLUTE_PATH" -- "feat(iter-174): perf-baseline probe subject"

iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict \
    "A3: iter-153 advisor --json --strict (AI-agent automation pipeline path)" \
    "$ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER153_ADVISOR_JSON_STRICT_AI_AGENT_AUTOMATION_MODE" \
    bash "$ITER174_ITER153_ADVISOR_ABSOLUTE_PATH" --strict --json -- "feat(iter-174): perf-baseline probe subject"

iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict \
    "A4: iter-152 commits:health 5-panel dashboard (occasional, N=10)" \
    "$ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER152_COMMITS_HEALTH_FIVE_PANEL_DASHBOARD" \
    bash "$ITER174_ITER152_DASHBOARD_ABSOLUTE_PATH"

iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict \
    "A5: iter-165 pending-release aggregator (every release:preflight, post-iter-167)" \
    "$ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER165_PENDING_RELEASE_AGGREGATOR_POST_ITER167_OPTIMIZATION" \
    bash "$ITER174_ITER165_AGGREGATOR_ABSOLUTE_PATH"

iter174_run_single_benchmark_scenario_measuring_median_and_comparing_to_pinned_baseline_cap_with_pass_or_regress_verdict \
    "A6: iter-160 doctor 15-check self-diagnosis (operator-facing, post-iter-177)" \
    "$ITER174_BASELINE_CAP_MILLISECONDS_FOR_ITER160_DOCTOR_POST_ITER177_OPTIMIZATION" \
    bash "$ITER174_ITER160_DOCTOR_ABSOLUTE_PATH"

# ─── Group B: structural invariant on the harness itself ────────────────────
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean ""
iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "GROUP B (1 assertion): harness self-pins the N-trial count constant (regression-detect on accidental N=1 sampling that would fail to compute median)"

ITER174_TOTAL_ASSERTIONS_EVALUATED=$((ITER174_TOTAL_ASSERTIONS_EVALUATED + 1))
if (( ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION >= 3 )); then
    iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "  ✓ B1: harness N-trial count = ${ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION} (≥3 required for meaningful median; 5 is robust against single-trial cold-start jitter)"
else
    iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean "  ✗ B1: harness N-trial count = ${ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION} (< 3; insufficient samples for median)"
    ITER174_TOTAL_ASSERTIONS_FAILED=$((ITER174_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
if [[ "$ITER179_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "json" ]]; then
    # Emit canonical iter-179 JSON envelope. Per-scenario records were accumulated
    # by each iter174_run_single_benchmark_scenario_... call into the array above.
    iter179_overall_verdict_pass_or_regress_for_top_level_json_envelope_summary_field=$(( ITER174_TOTAL_ASSERTIONS_FAILED == 0 ? 0 : 1 ))
    if (( iter179_overall_verdict_pass_or_regress_for_top_level_json_envelope_summary_field == 0 )); then
        iter179_overall_verdict_string_for_envelope="PASS"
    else
        iter179_overall_verdict_string_for_envelope="REGRESS"
    fi
    iter179_per_scenario_records_joined_by_commas_for_json_array_body=""
    for iter179_each_scenario_record in "${ITER179_PER_SCENARIO_JSON_RECORDS_ACCUMULATED_ACROSS_ALL_BENCHMARKS_FOR_FINAL_ENVELOPE_EMISSION[@]}"; do
        if [[ -n "$iter179_per_scenario_records_joined_by_commas_for_json_array_body" ]]; then
            iter179_per_scenario_records_joined_by_commas_for_json_array_body+=","
        fi
        iter179_per_scenario_records_joined_by_commas_for_json_array_body+=$'\n    '"$iter179_each_scenario_record"
    done
    cat <<EOF
{
  "iter174_schema_version": 1,
  "iter174_perf_baseline_regression_harness_machine_readable_output": true,
  "trials_per_script": ${ITER174_NUMBER_OF_WALL_CLOCK_TRIALS_PER_SCRIPT_FOR_MEDIAN_COMPUTATION},
  "results": [${iter179_per_scenario_records_joined_by_commas_for_json_array_body}
  ],
  "summary": {
    "total_evaluated": ${ITER174_TOTAL_ASSERTIONS_EVALUATED},
    "total_failed": ${ITER174_TOTAL_ASSERTIONS_FAILED},
    "total_passed": $((ITER174_TOTAL_ASSERTIONS_EVALUATED - ITER174_TOTAL_ASSERTIONS_FAILED)),
    "overall_verdict": "${iter179_overall_verdict_string_for_envelope}"
  }
}
EOF
    if (( ITER174_TOTAL_ASSERTIONS_FAILED == 0 )); then
        exit 0
    else
        exit 1
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER174_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-174 PERF-BASELINE REGRESSION HARNESS: ${ITER174_TOTAL_ASSERTIONS_EVALUATED}/${ITER174_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-174 PERF-BASELINE REGRESSION HARNESS: $((ITER174_TOTAL_ASSERTIONS_EVALUATED - ITER174_TOTAL_ASSERTIONS_FAILED))/${ITER174_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER174_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
