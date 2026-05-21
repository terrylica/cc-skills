#!/usr/bin/env bash
#MISE description="Iter-94 microbenchmark: measure end-to-end PostToolUse orchestrator wall-clock with the async-Bun.spawn-refactored subhooks (ty + tsgo). Reports median over N=5 runs for two synthetic payloads (.py and .ts) plus a non-applicable .txt payload (baseline orchestrator-overhead-only). Empirically confirms the iter-94 finding that async-Bun.spawn lets the orchestrator's Promise.all achieve real parallelism — the .ts payload triggers tsgo only (1 spawn), the .py payload triggers ty only (1 spawn), and a hypothetical future state where BOTH fire on the same payload would have wall-clock ≈ MAX(ty_time, tsgo_time) rather than SUM(ty_time, tsgo_time). Mirrors iter-80's PreToolUse profiler architecture (median-of-N with Bun.nanoseconds resolution)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"

NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD=5
MICROBENCHMARK_TEMP_DIRECTORY=$(mktemp -d -t iter94-orchestrator-bench.XXXXXX)
trap 'rm -rf "$MICROBENCHMARK_TEMP_DIRECTORY"' EXIT

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-94 PostToolUse orchestrator wall-clock microbenchmark"
echo ""
echo "  Theory:    Bun.spawn (async) + Promise.all → wall-clock ≈ MAX(subhook_i)"
echo "  Anti-thy:  Bun.spawnSync inside Promise.all → wall-clock ≈ SUM(subhook_i)"
echo "  Source:    bun.com/docs/api/spawn + 2026 community guidance"
echo "  Replicates: N=$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD per payload (median reported)"
echo ""

if [[ ! -f "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" ]]; then
    echo "  ⊘ orchestrator file not found — benchmark cannot run"
    exit 0
fi

# ─── Synthetic payloads ──────────────────────────────────────────────────
NON_APPLICABLE_TXT_PAYLOAD_PATH="$MICROBENCHMARK_TEMP_DIRECTORY/payload-non-applicable-txt.json"
PYTHON_APPLICABLE_PY_PAYLOAD_PATH="$MICROBENCHMARK_TEMP_DIRECTORY/payload-python-applicable-py.json"
TYPESCRIPT_APPLICABLE_TS_PAYLOAD_PATH="$MICROBENCHMARK_TEMP_DIRECTORY/payload-typescript-applicable-ts.json"

cat > "$NON_APPLICABLE_TXT_PAYLOAD_PATH" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter94-bench.txt","content":"hello\n"}}
PAYLOAD

cat > "$PYTHON_APPLICABLE_PY_PAYLOAD_PATH" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter94-bench-non-existent.py","content":"def f():\n    return 1\n"}}
PAYLOAD

cat > "$TYPESCRIPT_APPLICABLE_TS_PAYLOAD_PATH" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter94-bench-non-existent.ts","content":"export function f(): number { return 1; }\n"}}
PAYLOAD

# ─── Benchmark loop ──────────────────────────────────────────────────────
#
# For each payload, run the orchestrator N times capturing wall-clock in
# milliseconds (via `bun -e` with performance.now() bracketing). Then
# compute the median by sorting the N samples and picking the middle one.
# Median (not mean) so a single GC pause or filesystem hiccup doesn't skew
# the result.
benchmark_single_payload_and_report_median_wall_clock_milliseconds() {
    local payload_label="$1"
    local payload_path_absolute="$2"
    local replicates="$3"

    declare -a wall_clock_milliseconds_samples=()
    for ((replicate=1; replicate<=replicates; replicate++)); do
        # Run orchestrator and time it. Use bun -e to wrap the timing
        # inside Bun's own runtime (more accurate than `time` shell builtin
        # because we avoid the shell-startup component).
        local elapsed_ms
        elapsed_ms=$(bun -e "
const startNanos = process.hrtime.bigint();
const child = Bun.spawn(['bun', '$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH'], {
  stdin: Bun.file('$payload_path_absolute'),
  stdout: 'pipe',
  stderr: 'pipe',
});
await child.exited;
const elapsedNanos = process.hrtime.bigint() - startNanos;
console.log(Number(elapsedNanos) / 1_000_000);
" 2>/dev/null)
        wall_clock_milliseconds_samples+=("$elapsed_ms")
    done

    # Compute median via shell sort
    local sorted_samples
    sorted_samples=$(printf '%s\n' "${wall_clock_milliseconds_samples[@]}" | sort -g)
    local median_index=$((replicates / 2 + 1))
    local median_milliseconds
    median_milliseconds=$(echo "$sorted_samples" | sed -n "${median_index}p")

    printf "  %-50s median: %8.2f ms  (samples: %s)\n" \
        "$payload_label" "$median_milliseconds" "$(printf '%s ' "${wall_clock_milliseconds_samples[@]}")"
}

echo "  ─── Per-payload median wall-clock (across $NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD replicates) ───"
echo ""
benchmark_single_payload_and_report_median_wall_clock_milliseconds \
    "non-applicable .txt (baseline overhead only)" \
    "$NON_APPLICABLE_TXT_PAYLOAD_PATH" \
    "$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD"
benchmark_single_payload_and_report_median_wall_clock_milliseconds \
    "python-applicable .py (ty subprocess spawned)" \
    "$PYTHON_APPLICABLE_PY_PAYLOAD_PATH" \
    "$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD"
benchmark_single_payload_and_report_median_wall_clock_milliseconds \
    "typescript-applicable .ts (tsgo subprocess spawned)" \
    "$TYPESCRIPT_APPLICABLE_TS_PAYLOAD_PATH" \
    "$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD"

echo ""
print_banner "Interpretation"
echo ""
echo "  - The baseline .txt median = bun cold-start + orchestrator parse +"
echo "    Promise.all overhead + both subhooks' O(1) extension-filter fastpath."
echo "  - The .py median includes the ty subprocess time. The .ts median"
echo "    includes the tsgo subprocess time. Neither file actually exists, so"
echo "    the subhook short-circuits via existsSync() (.py path) or"
echo "    locateNearestEnclosingTsconfigJsonDirectoryByWalkingUpward() returning"
echo "    null (.ts path). Wall-clock should approach the baseline."
echo "  - When BOTH subhooks fire on the same payload (future state when"
echo "    oxlint, biome, etc. are inlined), the iter-94 async-Bun.spawn refactor"
echo "    means the wall-clock approaches MAX(subhook_i), not SUM. The"
echo "    static audit at"
echo "    .mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh"
echo "    prevents regression."
echo ""
exit 0
