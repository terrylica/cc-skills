#!/usr/bin/env bash
#MISE description="Iter-80 forensic profiler: measures every registered PreToolUse hook in plugins/itp-hooks/hooks/pretooluse-*.{ts,mjs} against a representative NON-APPLICABLE Edit payload (Go file, no domain-specific signals). Reports median latency over N=5 runs sorted descending, identifies HIGH-OVERHEAD outliers (>50ms median) for targeted optimization, and benchmarks the bun cold-start floor for calibration. Use to: (a) catch hook-overhead regressions before a new hook lands, (b) decide whether a new hook needs a pre-JSON-parse fastpath, (c) verify the bun-startup-cost-floor claim in docs/HOOKS.md. Companion to the iter-73 release-pipeline timing instrumentation."

# Iter-80 — Edit-Time PreToolUse Hook Cold-Start Cost Profiler
#
# Background:
#   The cc-skills marketplace registers ~10 PreToolUse hooks under the
#   matcher "Write|Edit", each of which fires SEQUENTIALLY on every
#   Write/Edit tool invocation. Past iterations (iter-39/40/41/55/56)
#   added "pre-JSON-parse fastpaths" claiming ~70-200x speedups on
#   bail-out paths. Iter-80 forensic measurement REVISES that claim:
#
#     - bun cold-start floor (empty stdin -> empty allow JSON):  ~32ms
#     - Real-hook with fastpath, non-applicable payload:         ~40ms
#     - Real-hook without fastpath, non-applicable payload:      ~40ms
#
#   Conclusion: bun process spawn dominates. Fastpath saves ~8ms per
#   hook, not the ~30ms previously assumed. Edit-time hook overhead
#   is bounded below by N_hooks × bun_startup_floor (~32ms × 10 hooks
#   = ~320ms minimum per Write/Edit). To meaningfully reduce edit
#   latency, future work must REDUCE THE BUN SPAWN COUNT (e.g., via
#   a PreToolUse orchestrator pattern like the iter-66 stop-orchestrator
#   precedent) — not optimize within individual hook code paths.
#
# What this profiler does:
#   1. Discovers every plugins/*/hooks/pretooluse-*.{ts,mjs} hook,
#      excluding test fixtures (*.test.*).
#   2. For each hook, runs it 5 times against a representative
#      NON-APPLICABLE Edit payload (a Go file edit — no domain
#      signals that any Python/CLAUDE.md/mise/cargo-specific hook
#      would care about).
#   3. Reports MEDIAN latency (more stable than mean for ~5 runs),
#      sorted descending.
#   4. Flags HIGH-OVERHEAD outliers (>50ms median) — anything
#      meaningfully above the bun-startup-floor + fastpath-overhead
#      budget.
#   5. Benchmarks the bun cold-start floor itself for calibration.
#
# What this profiler does NOT do:
#   - Measure APPLICABLE-payload latency (where the hook actually
#     classifies + emits a decision). That's separate work.
#   - Measure end-to-end Write/Edit latency in a live Claude session.
#   - Stress-test concurrent hook execution.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# Task lives at .mise/tasks/<task>.sh; repo root is two levels up.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILER_RUNS_PER_HOOK_FOR_MEDIAN_STABILITY=5
HIGH_OVERHEAD_OUTLIER_THRESHOLD_MILLISECONDS=50

# Representative non-applicable payload — Go file edit, no domain
# signals (no .py, no .pyi, no CLAUDE.md, no mise.toml, no pyproject.toml,
# no .plist, no cargo, no CLAUDE_PLUGIN_ROOT reference). Every domain-
# scoped PreToolUse hook should short-circuit on this payload.
NON_APPLICABLE_REPRESENTATIVE_EDIT_TOOL_INPUT_PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/some-source.go","old_string":"foo","new_string":"bar"}}'

emit_section_banner() {
    local title="$1"
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  $title"
    echo "═══════════════════════════════════════════════════════════════════════════"
}

read_high_resolution_wall_clock_milliseconds() {
    /usr/bin/python3 -c 'import time; print(int(time.time()*1000000))'
}

measure_single_hook_invocation_median_latency_over_n_runs() {
    local hook_path_to_profile="$1"
    local stdin_payload_for_invocation="$2"
    local sample_count="$3"

    local measured_latencies_microseconds=()
    local run_index
    for ((run_index = 1; run_index <= sample_count; run_index++)); do
        local invocation_start_microseconds
        invocation_start_microseconds=$(read_high_resolution_wall_clock_milliseconds)
        printf '%s' "$stdin_payload_for_invocation" \
            | bun "$hook_path_to_profile" >/dev/null 2>&1 || true
        local invocation_end_microseconds
        invocation_end_microseconds=$(read_high_resolution_wall_clock_milliseconds)
        measured_latencies_microseconds+=(
            $((invocation_end_microseconds - invocation_start_microseconds))
        )
    done

    # Compute median: sort ascending, take middle element.
    local sorted_latencies_microseconds
    sorted_latencies_microseconds=$(
        printf '%s\n' "${measured_latencies_microseconds[@]}" | sort -n
    )
    local median_position_one_indexed=$(((sample_count + 1) / 2))
    local median_latency_microseconds
    median_latency_microseconds=$(
        echo "$sorted_latencies_microseconds" \
            | sed -n "${median_position_one_indexed}p"
    )
    echo $((median_latency_microseconds / 1000))
}

detect_fastpath_keyword_presence_in_hook_source() {
    local hook_path_to_inspect="$1"
    if grep -qE 'FAST_PATH|FASTPATH|hasKeyword|fastpath' \
            "$hook_path_to_inspect" 2>/dev/null; then
        echo "YES"
    else
        echo "no"
    fi
}

emit_section_banner "Edit-Time PreToolUse Hook Cold-Start Cost Profiler (iter-80)"

# ---------------------------------------------------------------------------
# Stage 1: Calibrate the bun cold-start floor.
# ---------------------------------------------------------------------------
echo ""
echo "  Stage 1: Calibrating bun cold-start floor (no-op hook baseline)"
echo ""

bun_cold_start_calibration_noop_hook_path=$(mktemp -t bun-cold-start-calibration-noop-hook.XXXXXX.ts)
trap 'rm -f "$bun_cold_start_calibration_noop_hook_path"' EXIT

cat > "$bun_cold_start_calibration_noop_hook_path" <<'EOF_NOOP_HOOK'
// Iter-80 cold-start calibration no-op hook. Spawn bun, emit minimal
// allow JSON, exit. Used to measure the lower bound of edit-time hook
// overhead.
console.log('{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}');
EOF_NOOP_HOOK

bun_cold_start_floor_median_milliseconds=$(
    measure_single_hook_invocation_median_latency_over_n_runs \
        "$bun_cold_start_calibration_noop_hook_path" \
        '{}' \
        "$PROFILER_RUNS_PER_HOOK_FOR_MEDIAN_STABILITY"
)

printf "  bun-cold-start-floor (median over %d runs): %d ms\n" \
    "$PROFILER_RUNS_PER_HOOK_FOR_MEDIAN_STABILITY" \
    "$bun_cold_start_floor_median_milliseconds"

# ---------------------------------------------------------------------------
# Stage 2: Discover every PreToolUse hook source file.
# ---------------------------------------------------------------------------
echo ""
echo "  Stage 2: Discovering plugins/*/hooks/pretooluse-*.{ts,mjs}"
echo ""

discovered_pretooluse_hook_source_files=()
while IFS= read -r candidate_hook_path; do
    [[ -f "$candidate_hook_path" ]] || continue
    case "$candidate_hook_path" in
        *.test.ts|*.test.mjs|*.test.js|*.test.sh) continue ;;
        *pretooluse-helpers.ts) continue ;;  # shared module, not a hook
    esac
    discovered_pretooluse_hook_source_files+=("$candidate_hook_path")
done < <(
    find "$REPO_ROOT/plugins" -path '*/hooks/pretooluse-*' \
        \( -name '*.ts' -o -name '*.mjs' \) -type f 2>/dev/null \
        | sort
)

printf "  Discovered %d PreToolUse hooks (test fixtures + helpers module excluded)\n" \
    "${#discovered_pretooluse_hook_source_files[@]}"

# ---------------------------------------------------------------------------
# Stage 3: Measure each hook's median latency on the non-applicable
# representative payload.
# ---------------------------------------------------------------------------
echo ""
echo "  Stage 3: Measuring each hook (representative non-applicable Go-file Edit)"
echo ""

# Accumulate raw "ms hook-path fastpath" lines for later sorting.
hook_median_latency_measurements_raw=""

for hook_path in "${discovered_pretooluse_hook_source_files[@]}"; do
    median_latency_milliseconds=$(
        measure_single_hook_invocation_median_latency_over_n_runs \
            "$hook_path" \
            "$NON_APPLICABLE_REPRESENTATIVE_EDIT_TOOL_INPUT_PAYLOAD" \
            "$PROFILER_RUNS_PER_HOOK_FOR_MEDIAN_STABILITY"
    )
    fastpath_marker_present=$(
        detect_fastpath_keyword_presence_in_hook_source "$hook_path"
    )
    hook_basename=$(basename "$hook_path")
    hook_median_latency_measurements_raw+="$median_latency_milliseconds $hook_basename $fastpath_marker_present"$'\n'
done

# ---------------------------------------------------------------------------
# Stage 4: Render sorted report + HIGH-OVERHEAD outlier flag.
# ---------------------------------------------------------------------------
echo ""
emit_section_banner "Hook Latency Report (median over $PROFILER_RUNS_PER_HOOK_FOR_MEDIAN_STABILITY runs, sorted DESC)"
echo ""
printf "  %4s | %-70s | %s\n" "ms" "Hook" "fastpath"
printf "  %4s-+-%-70s-+-%s\n" "----" "----------------------------------------------------------------------" "--------"

total_hooks_above_high_overhead_outlier_threshold=0
high_overhead_outlier_hook_diagnostic_lines=""

# Sort descending by latency (numeric reverse).
sorted_descending_by_latency_milliseconds=$(
    printf '%s' "$hook_median_latency_measurements_raw" | sort -rn
)

while IFS=' ' read -r median_ms hook_basename fastpath_marker; do
    [[ -z "$median_ms" ]] && continue
    printf "  %4s | %-70s | %s\n" "$median_ms" "$hook_basename" "$fastpath_marker"
    if [[ "$median_ms" -gt "$HIGH_OVERHEAD_OUTLIER_THRESHOLD_MILLISECONDS" ]]; then
        total_hooks_above_high_overhead_outlier_threshold=$((
            total_hooks_above_high_overhead_outlier_threshold + 1
        ))
        high_overhead_outlier_hook_diagnostic_lines+="    - $hook_basename: $median_ms ms (fastpath: $fastpath_marker)"$'\n'
    fi
done <<< "$sorted_descending_by_latency_milliseconds"

# ---------------------------------------------------------------------------
# Stage 5: Summary + recommendations.
# ---------------------------------------------------------------------------
echo ""
emit_section_banner "Summary"
echo ""
printf "  bun-cold-start-floor:                            %d ms\n" \
    "$bun_cold_start_floor_median_milliseconds"
printf "  Total PreToolUse hooks profiled:                 %d\n" \
    "${#discovered_pretooluse_hook_source_files[@]}"
printf "  HIGH-OVERHEAD outliers (>%d ms median):           %d\n" \
    "$HIGH_OVERHEAD_OUTLIER_THRESHOLD_MILLISECONDS" \
    "$total_hooks_above_high_overhead_outlier_threshold"

if [[ "$total_hooks_above_high_overhead_outlier_threshold" -gt 0 ]]; then
    echo ""
    echo "  HIGH-OVERHEAD outliers (candidates for fastpath review):"
    printf '%s' "$high_overhead_outlier_hook_diagnostic_lines"
fi

# Calculate worst-case edit-time hook latency (sequential firing of all
# Write|Edit-matched hooks). This sets the realistic budget for any
# orchestrator-pattern future work.
total_aggregate_edit_time_hook_overhead_milliseconds=0
while IFS=' ' read -r median_ms _; do
    [[ -z "$median_ms" ]] && continue
    total_aggregate_edit_time_hook_overhead_milliseconds=$((
        total_aggregate_edit_time_hook_overhead_milliseconds + median_ms
    ))
done <<< "$sorted_descending_by_latency_milliseconds"

echo ""
printf "  Aggregate worst-case sequential-firing overhead: %d ms\n" \
    "$total_aggregate_edit_time_hook_overhead_milliseconds"
printf "  (Sum of every PreToolUse hook firing once per Write/Edit; actual)\n"
printf "  (per-edit overhead depends on which matchers fire for the tool.)\n"
echo ""

# Architectural-direction guidance based on the cold-start finding.
echo "  Optimization-strategy guidance (per iter-80 cold-start-floor finding):"
echo ""
echo "    1. Within-hook optimization (fastpath, jq-batching, etc.) saves"
echo "       at most ~$((40 - bun_cold_start_floor_median_milliseconds)) ms per hook. Marginal."
echo ""
echo "    2. To meaningfully reduce edit-time hook overhead, REDUCE THE BUN"
echo "       SPAWN COUNT. Each spawned bun process costs ~$bun_cold_start_floor_median_milliseconds ms minimum."
echo "       Candidate pattern: a PreToolUse-orchestrator hook (like the"
echo "       iter-66 stop-orchestrator) that runs N subhooks in one bun"
echo "       process. Saves ~$((bun_cold_start_floor_median_milliseconds * 8)) ms across the 10-hook Write|Edit chain."
echo ""
echo "    3. Alternative: AOT-compile hooks via 'bun build --compile' to"
echo "       trim a few ms off cold start. Marginal but composable with #2."
echo ""
echo "  Forensic source: iter-80 measurement run (this task)."
echo "  Documented baseline: docs/HOOKS.md 'Edit-Time Hook Overhead Cost Model'."

exit 0
