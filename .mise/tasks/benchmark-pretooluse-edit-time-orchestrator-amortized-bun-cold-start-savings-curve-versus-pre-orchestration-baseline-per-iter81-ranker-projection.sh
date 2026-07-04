#!/usr/bin/env bash
#MISE description="Iter-87 empirical microbenchmark validating iter-81 ranker's projected cold-start-amortization savings curve. Measures median end-to-end latency of: (A) pre-orchestration baseline (4 standalone bun spawns for the 4 currently-inlined subhooks), (B) iter-84/85/86/87 orchestrator (1 bun spawn invoking 4 inlined classifiers), (C) projected savings = A - B vs iter-81's predicted (N-1) × bun_cold_start_floor. Reports actual savings vs projection delta; surfaces if our ~44ms cold-start measurement is real or inflated by payload overhead (per iter-86 web-research finding of community 8-15ms benchmarks)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# --- Arg parsing ---
WARMUP_ITERATION_COUNT_TO_PRIME_BUN_REQUIRE_CACHE=3
BENCHMARK_ITERATION_COUNT_FOR_MEDIAN_LATENCY_MEASUREMENT=15
while [[ $# -gt 0 ]]; do
    case "$1" in
        --warmup) WARMUP_ITERATION_COUNT_TO_PRIME_BUN_REQUIRE_CACHE="$2"; shift 2 ;;
        --iterations) BENCHMARK_ITERATION_COUNT_FOR_MEDIAN_LATENCY_MEASUREMENT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--warmup N] [--iterations N]"
            echo "  --warmup     N priming runs (default 3) before timed measurements"
            echo "  --iterations N timed runs per benchmark target (default 15)"
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_DIR="$REPO_ROOT/plugins/itp-hooks/hooks"
ORCHESTRATOR_HOOK_PATH="$HOOK_DIR/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"

# 4 standalone subhooks corresponding to the 4 currently inlined in the orchestrator
STANDALONE_SUBHOOKS=(
    "$HOOK_DIR/pretooluse-version-guard.ts"
    "$HOOK_DIR/pretooluse-hoisted-deps-guard.ts"
    "$HOOK_DIR/pretooluse-gpu-optimization-guard.ts"
    "$HOOK_DIR/pretooluse-file-size-guard.ts"
)

# Synthetic Write payload designed to NOT trigger any subhook's deny path
# (path under /tmp/ is exempted by version-guard; non-pyproject.toml exempted
# by hoisted-deps-guard; non-.py exempted by gpu-optimization-guard; small
# content under file-size-guard threshold). All 4 should ALLOW quickly,
# exercising only the fastpath cost.
BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE=$(mktemp -t iter87-bench-payload.XXXXXX.json)
trap 'rm -f "$BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE"' EXIT
cat > "$BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter87-bench-neutral-fixture.txt","content":"hello world\nthis is a benchmark fixture\n"}}
PAYLOAD

echo "════════════════════════════════════════════════════════════════════════════════"
echo "  Iter-87 PreToolUse-Orchestrator Amortized-Cold-Start-Savings-Curve Benchmark"
echo "════════════════════════════════════════════════════════════════════════════════"
printf "  Warmup iterations:                  %d (priming bun require-cache)\n" "$WARMUP_ITERATION_COUNT_TO_PRIME_BUN_REQUIRE_CACHE"
printf "  Timed iterations per target:        %d\n" "$BENCHMARK_ITERATION_COUNT_FOR_MEDIAN_LATENCY_MEASUREMENT"
printf "  Standalone subhooks (baseline A):   %d (version, hoisted-deps, gpu-optim, file-size)\n" "${#STANDALONE_SUBHOOKS[@]}"
printf "  Orchestrator entry (target B):      %s\n" "$(basename "$ORCHESTRATOR_HOOK_PATH")"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# --- Helper: compute median of an array of integer milliseconds ---
median_of_integer_millisecond_array_via_sort_and_middle_index() {
    local sorted_array
    sorted_array=$(printf '%s\n' "$@" | sort -n)
    local count
    count=$(echo "$sorted_array" | wc -l | tr -d ' ')
    local middle_index=$(( (count + 1) / 2 ))
    echo "$sorted_array" | sed -n "${middle_index}p"
}

# --- Helper: time a single command end-to-end in milliseconds via gdate ---
# Falls back to bash $EPOCHREALTIME if gdate unavailable.
measure_command_wall_clock_milliseconds_via_epochrealtime() {
    local cmd_to_time="$1"
    local start_realtime end_realtime
    start_realtime=$EPOCHREALTIME
    eval "$cmd_to_time" >/dev/null 2>&1 || true
    end_realtime=$EPOCHREALTIME
    # EPOCHREALTIME is "seconds.microseconds"; compute delta * 1000 (ms)
    awk -v start="$start_realtime" -v end="$end_realtime" \
        'BEGIN { printf "%.0f", (end - start) * 1000 }'
}

# --- WARMUP: prime bun's require-cache for both targets ---
echo "→ Warmup: priming bun require-cache ($WARMUP_ITERATION_COUNT_TO_PRIME_BUN_REQUIRE_CACHE iterations per target)..."
for ((w = 0; w < WARMUP_ITERATION_COUNT_TO_PRIME_BUN_REQUIRE_CACHE; w++)); do
    for standalone in "${STANDALONE_SUBHOOKS[@]}"; do
        bun "$standalone" < "$BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE" >/dev/null 2>&1 || true
    done
    bun "$ORCHESTRATOR_HOOK_PATH" < "$BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE" >/dev/null 2>&1 || true
done
echo "  ✓ Warmup complete"
echo ""

# --- TARGET A: baseline = sum of 4 sequential standalone bun spawns ---
echo "→ Target A: pre-orchestration baseline (4 sequential standalone bun spawns)"
TARGET_A_LATENCY_MILLISECOND_SAMPLES=()
for ((i = 0; i < BENCHMARK_ITERATION_COUNT_FOR_MEDIAN_LATENCY_MEASUREMENT; i++)); do
    sum_ms=0
    for standalone in "${STANDALONE_SUBHOOKS[@]}"; do
        per_subhook_ms=$(measure_command_wall_clock_milliseconds_via_epochrealtime \
            "bun '$standalone' < '$BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE'")
        sum_ms=$((sum_ms + per_subhook_ms))
    done
    TARGET_A_LATENCY_MILLISECOND_SAMPLES+=("$sum_ms")
done
target_a_median_ms=$(median_of_integer_millisecond_array_via_sort_and_middle_index \
    "${TARGET_A_LATENCY_MILLISECOND_SAMPLES[@]}")
printf "  Median end-to-end latency (4-standalone baseline): %d ms\n" "$target_a_median_ms"
echo ""

# --- TARGET B: orchestrator with 4 inlined subhooks (1 bun spawn) ---
echo "→ Target B: iter-84/85/86/87 orchestrator (1 bun spawn invoking 4 inlined classifiers)"
TARGET_B_LATENCY_MILLISECOND_SAMPLES=()
for ((i = 0; i < BENCHMARK_ITERATION_COUNT_FOR_MEDIAN_LATENCY_MEASUREMENT; i++)); do
    orch_ms=$(measure_command_wall_clock_milliseconds_via_epochrealtime \
        "bun '$ORCHESTRATOR_HOOK_PATH' < '$BENCHMARK_NEUTRAL_WRITE_PAYLOAD_FILE'")
    TARGET_B_LATENCY_MILLISECOND_SAMPLES+=("$orch_ms")
done
target_b_median_ms=$(median_of_integer_millisecond_array_via_sort_and_middle_index \
    "${TARGET_B_LATENCY_MILLISECOND_SAMPLES[@]}")
printf "  Median end-to-end latency (orchestrator inline): %d ms\n" "$target_b_median_ms"
echo ""

# --- Compute and report savings vs iter-81 projection ---
empirical_amortization_savings_ms=$((target_a_median_ms - target_b_median_ms))
iter81_per_subhook_cold_start_floor_estimate_ms=44
iter81_projected_savings_ms=$((3 * iter81_per_subhook_cold_start_floor_estimate_ms))

echo "════════════════════════════════════════════════════════════════════════════════"
echo "  Empirical Amortization Savings vs Iter-81 Projection"
echo "════════════════════════════════════════════════════════════════════════════════"
printf "  Baseline median (A):                 %5d ms (4 standalone spawns)\n" "$target_a_median_ms"
printf "  Orchestrator median (B):             %5d ms (1 orchestrator spawn)\n" "$target_b_median_ms"
printf "  Empirical savings (A - B):           %5d ms\n" "$empirical_amortization_savings_ms"
printf "  Iter-81 projected (4-1)×44ms floor:  %5d ms\n" "$iter81_projected_savings_ms"
delta_ms=$((empirical_amortization_savings_ms - iter81_projected_savings_ms))
printf "  Empirical-vs-projection delta:       %5d ms" "$delta_ms"
if [[ "$delta_ms" -gt 0 ]]; then
    printf " (empirical OUTPERFORMS projection)\n"
elif [[ "$delta_ms" -lt -20 ]]; then
    printf " (empirical UNDERPERFORMS projection — likely the iter-80 ~44ms floor was inflated by payload-handling overhead; community benchmarks suggest 8-15ms pure bun cold-start)\n"
else
    printf " (empirical matches projection within noise)\n"
fi
echo "════════════════════════════════════════════════════════════════════════════════"
printf "  Effective per-subhook saved-cold-start cost = %d ms / 3 saved spawns = %d ms each\n" \
    "$empirical_amortization_savings_ms" "$((empirical_amortization_savings_ms / 3))"
echo "════════════════════════════════════════════════════════════════════════════════"
exit 0
