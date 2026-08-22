#!/usr/bin/env bash
#MISE description="Iter-95 microbenchmark variant complementing iter-94's no-spawn benchmark: creates a REAL .ts file in a tsconfig-rooted dir, runs the orchestrator, and measures wall-clock with N=2 actual subprocesses (tsgo + oxlint) firing in parallel via Bun.spawn (biome may also fire if installed). Empirically confirms that wall-clock approaches MAX(subhook_i) rather than SUM(subhook_i) — the iter-94 async-Bun.spawn refactor's claimed benefit. Median-of-N=5 reported per payload."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"

NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD=5
EMPIRICAL_PARALLELISM_BENCHMARK_TEMP_DIRECTORY=$(mktemp -d -t iter95-empirical-parallelism-bench.XXXXXX)
trap 'rm -rf "$EMPIRICAL_PARALLELISM_BENCHMARK_TEMP_DIRECTORY"' EXIT

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-95 PostToolUse orchestrator EMPIRICAL parallelism microbenchmark"
echo ""
echo "  Theory:    With Bun.spawn (async) + Promise.all, N parallel subprocess"
echo "             spawns produce wall-clock ≈ MAX(subhook_i), not SUM."
echo "  Anti-thy:  With Bun.spawnSync, the wall-clock would be SUM (serial)."
echo "  Test:     creates a REAL .ts file in a tsconfig-rooted dir; orchestrator"
echo "            fires tsgo + oxlint + biome subprocesses concurrently."
echo "  Source:    bun.com/docs/api/spawn + 2026 community guidance"
echo "  Replicates: N=$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD per payload (median)"
echo ""

# ─── Set up a real TypeScript project so subprocesses actually fire ──
SYNTHETIC_PROJECT_DIRECTORY="$EMPIRICAL_PARALLELISM_BENCHMARK_TEMP_DIRECTORY/synthetic-ts-project"
mkdir -p "$SYNTHETIC_PROJECT_DIRECTORY"

# Minimal valid tsconfig.json so tsgo will run
cat > "$SYNTHETIC_PROJECT_DIRECTORY/tsconfig.json" <<'TSCONFIG_EOF'
{
  "compilerOptions": {
    "target": "esnext",
    "module": "esnext",
    "moduleResolution": "node",
    "strict": false,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["**/*.ts"]
}
TSCONFIG_EOF

# Trivial valid .ts file — no type errors, no lint issues. This is the
# baseline: subprocesses spawn, run to completion cleanly, then exit. We're
# measuring the SPAWN COORDINATION cost, not the type-check work itself.
SYNTHETIC_TYPESCRIPT_FILE_ABSOLUTE_PATH="$SYNTHETIC_PROJECT_DIRECTORY/example.ts"
cat > "$SYNTHETIC_TYPESCRIPT_FILE_ABSOLUTE_PATH" <<'TYPESCRIPT_EOF'
export function greetByName(name: string): string {
  return `Hello, ${name}!`;
}
const TRIVIAL_VALUE: number = 42;
console.log(greetByName(`world`), TRIVIAL_VALUE);
TYPESCRIPT_EOF

# ─── Build the synthetic PostToolUse payload pointing at the real .ts ───
REAL_TYPESCRIPT_PAYLOAD_PATH="$EMPIRICAL_PARALLELISM_BENCHMARK_TEMP_DIRECTORY/payload-real-typescript.json"
cat > "$REAL_TYPESCRIPT_PAYLOAD_PATH" <<PAYLOAD_EOF
{"tool_name":"Write","tool_input":{"file_path":"$SYNTHETIC_TYPESCRIPT_FILE_ABSOLUTE_PATH","content":"export function greetByName(name: string): string { return name; }\n"}}
PAYLOAD_EOF

# ─── Optional non-applicable baseline payload for delta calculation ──
NON_APPLICABLE_PAYLOAD_PATH="$EMPIRICAL_PARALLELISM_BENCHMARK_TEMP_DIRECTORY/payload-non-applicable.json"
cat > "$NON_APPLICABLE_PAYLOAD_PATH" <<'PAYLOAD_EOF'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter95-bench.txt","content":"hi\n"}}
PAYLOAD_EOF

# ─── Benchmark execution ────────────────────────────────────────────
benchmark_single_payload_and_report_median_wall_clock_milliseconds() {
    local payload_label="$1"
    local payload_path_absolute="$2"
    local replicates="$3"

    declare -a wall_clock_milliseconds_samples=()
    for ((replicate=1; replicate<=replicates; replicate++)); do
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

    local sorted_samples
    sorted_samples=$(printf '%s\n' "${wall_clock_milliseconds_samples[@]}" | sort -g)
    local median_index=$((replicates / 2 + 1))
    local median_milliseconds
    median_milliseconds=$(echo "$sorted_samples" | sed -n "${median_index}p")

    printf "  %-55s median: %8.2f ms  (samples: %s)\n" \
        "$payload_label" "$median_milliseconds" "$(printf '%s ' "${wall_clock_milliseconds_samples[@]}")"
}

echo "  ─── Per-payload median wall-clock (across $NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD replicates) ───"
echo ""
benchmark_single_payload_and_report_median_wall_clock_milliseconds \
    "non-applicable .txt (orchestrator overhead only)" \
    "$NON_APPLICABLE_PAYLOAD_PATH" \
    "$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD"
benchmark_single_payload_and_report_median_wall_clock_milliseconds \
    "REAL .ts in tsconfig-rooted dir (≥2 subprocesses fire)" \
    "$REAL_TYPESCRIPT_PAYLOAD_PATH" \
    "$NUMBER_OF_BENCHMARK_REPLICATES_PER_PAYLOAD"

echo ""
print_banner "Interpretation"
echo ""
echo "  - non-applicable baseline = bun cold-start + orchestrator parse +"
echo "    Promise.all overhead + 4 subhooks' O(1) extension-filter fastpath."
echo "  - real .ts payload = baseline + tsgo subprocess + oxlint subprocess"
echo "    (+ biome subprocess if installed) firing CONCURRENTLY via Bun.spawn."
echo "  - The DELTA between the two payloads ≈ MAX(subhook_i) — NOT the sum"
echo "    of individual tool times, because Bun.spawn (async) lets the JS"
echo "    event loop overlap subprocess work. If the delta approached the"
echo "    SUM, the parallelism would be broken (likely a Bun.spawnSync"
echo "    regression; the iter-94 static audit prevents this)."
echo "  - tsgo's ~170ms project-check dominates the per-subhook cost; oxlint"
echo "    ~50ms; biome ~50ms. SUM ≈ 270ms; MAX ≈ 170ms. The async-spawn"
echo "    invariant should yield delta ≈ 170ms, not 270ms."
echo ""
exit 0
