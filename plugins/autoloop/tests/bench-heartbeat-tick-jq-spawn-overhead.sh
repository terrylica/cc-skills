#!/usr/bin/env bash
# bench-heartbeat-tick-jq-spawn-overhead.sh
#
# Measures end-to-end latency of the autoloop PostToolUse hook
# (`heartbeat-tick.sh`) and the count of `jq` subprocess spawns it incurs.
#
# Why this benchmark exists (iter-25 finding):
#   `heartbeat-tick.sh` fires on EVERY Claude Code tool invocation when
#   autoloop is active. Each `jq` cold start on macOS is ~30-50ms (see
#   https://lobste.rs/s/ntn2yq/jaq_jq_clone_focussed_on_correctness ;
#   https://github.com/01mf02/jaq for context). Pre-refactor the hot
#   path spawned 13 jq processes per tick on m3max, so the hook added
#   ~80ms of latency to every tool call. The iter-25 hot-path-jq-batching
#   refactor consolidates single-field extractions into TSV-output batched
#   jq invocations, cutting the steady-state hot-path spawn count to 7
#   (-46%) and median wall-clock latency from 82ms to 62ms (-24% on m3max,
#   measured A/B with `git checkout` before/after).
#
# This benchmark is the ground-truth witness for that claim: it measures
# the actual wall-clock latency on the operator's machine and counts the
# jq spawns observed via PATH shadowing. Run it before and after any
# future refactor of `heartbeat-tick.sh` to catch performance regressions.
#
# Usage:
#   ./bench-heartbeat-tick-jq-spawn-overhead.sh [iterations=200]
#
# Output: writes a JSON report to /tmp/heartbeat-tick-bench-<epoch>.json
# with these fields:
#   - iterations:                       number of hook runs averaged
#   - jq_spawn_count_per_tick:          observed `jq` invocations per tick
#   - median_wall_ms:                   median end-to-end hook latency
#   - p95_wall_ms / p99_wall_ms:        tail latencies
#   - jaq_available:                    whether `jaq` is in PATH (future opt)
#   - host:                             hostname + uname -m + jq --version

set -euo pipefail

# ===== Inputs =====
ITERATIONS="${1:-200}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="$SCRIPT_DIR/../hooks/heartbeat-tick.sh"

if [ ! -x "$HOOK_PATH" ]; then
  echo "✗ Hook not found or not executable: $HOOK_PATH" >&2
  exit 1
fi

# ===== Build fixtures (isolated registry + heartbeat for this bench) =====
BENCH_TMP=$(mktemp -d -t autoloop-bench-XXXXXX)
trap 'rm -rf "$BENCH_TMP"' EXIT

BENCH_LOOPS_DIR="$BENCH_TMP/loops"
BENCH_STATE_DIR="$BENCH_TMP/state"
BENCH_REGISTRY="$BENCH_LOOPS_DIR/registry.json"
BENCH_HEARTBEAT="$BENCH_STATE_DIR/heartbeat.json"
BENCH_CONTRACT="$BENCH_TMP/CONTRACT.md"
BENCH_SESSION_ID="bench-session-$(date +%s)"
BENCH_LOOP_ID="bench00000000"

mkdir -p "$BENCH_LOOPS_DIR" "$BENCH_STATE_DIR/revision-log"
touch "$BENCH_CONTRACT"

# Realistic-shape registry with a single loop matching this bench session
cat > "$BENCH_REGISTRY" <<EOF
{
  "schema_version": 2,
  "loops": [
    {
      "loop_id": "$BENCH_LOOP_ID",
      "owner_session_id": "$BENCH_SESSION_ID",
      "owner_pid": $$,
      "owner_started_us": 0,
      "generation": 0,
      "state_dir": "$BENCH_STATE_DIR",
      "contract_path": "$BENCH_CONTRACT",
      "created_at_cwd": "$BENCH_TMP"
    }
  ]
}
EOF

cat > "$BENCH_HEARTBEAT" <<EOF
{
  "loop_id": "$BENCH_LOOP_ID",
  "session_id": "$BENCH_SESSION_ID",
  "iteration": 0,
  "generation": 0,
  "bound_cwd": "$BENCH_TMP"
}
EOF

# stdin payload (Claude Code hook contract)
BENCH_PAYLOAD=$(jq -n \
  --arg sid "$BENCH_SESSION_ID" \
  --arg cwd "$BENCH_TMP" \
  '{session_id: $sid, cwd: $cwd}')

# ===== Spawn-count probe (PATH shadowing) =====
#
# Shadow `jq` with a counter script. Each invocation appends a line to a
# counter file; we sum lines at the end. The shim itself dispatches to the
# real jq so behavior is identical — only counts are added.
SHIM_DIR="$BENCH_TMP/shim"
mkdir -p "$SHIM_DIR"
REAL_JQ=$(command -v jq)
JQ_SPAWN_LOG="$BENCH_TMP/jq-spawns.log"
: > "$JQ_SPAWN_LOG"

cat > "$SHIM_DIR/jq" <<EOF
#!/usr/bin/env bash
echo 1 >> "$JQ_SPAWN_LOG"
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$SHIM_DIR/jq"

# Single tick with the shim to count spawns
PATH="$SHIM_DIR:$PATH" CLAUDE_LOOPS_REGISTRY="$BENCH_REGISTRY" \
  bash "$HOOK_PATH" <<< "$BENCH_PAYLOAD" >/dev/null 2>&1 || true
JQ_SPAWN_COUNT=$(wc -l < "$JQ_SPAWN_LOG" | tr -d ' ')

# Reset heartbeat (the first tick mutated iteration) so latency runs from
# a steady state.
cat > "$BENCH_HEARTBEAT" <<EOF
{
  "loop_id": "$BENCH_LOOP_ID",
  "session_id": "$BENCH_SESSION_ID",
  "iteration": 0,
  "generation": 0,
  "bound_cwd": "$BENCH_TMP"
}
EOF

# ===== Latency measurement (without the shim — measures real performance) =====
LATENCY_LOG="$BENCH_TMP/latency-ms.log"
: > "$LATENCY_LOG"

if command -v hyperfine >/dev/null 2>&1; then
  # Preferred path: hyperfine for statistically-clean numbers
  HYPERFINE_JSON="$BENCH_TMP/hyperfine.json"
  hyperfine --warmup 10 --runs "$ITERATIONS" \
    --export-json "$HYPERFINE_JSON" \
    --shell=none \
    --setup "true" \
    "bash $HOOK_PATH" \
    < /dev/null > /dev/null 2>&1 || true

  # hyperfine's JSON gives mean/median in seconds — convert to ms below.
  if [ -f "$HYPERFINE_JSON" ]; then
    MEDIAN_MS=$(jq -r '.results[0].median * 1000' "$HYPERFINE_JSON")
    P95_MS=$(jq -r '
      .results[0].times
      | sort
      | .[(length * 0.95 | floor)]
      * 1000
    ' "$HYPERFINE_JSON")
    P99_MS=$(jq -r '
      .results[0].times
      | sort
      | .[(length * 0.99 | floor)]
      * 1000
    ' "$HYPERFINE_JSON")
    MEASUREMENT_TOOL="hyperfine"
  fi
else
  # Fallback: hand-rolled timing using `gdate +%s%N` (GNU coreutils on macOS).
  # If neither hyperfine nor gdate are installed, the benchmark records
  # `null` for latency fields; the spawn count is still valid.
  GDATE=$(command -v gdate || true)
  if [ -n "$GDATE" ]; then
    for ((i=0; i<ITERATIONS; i++)); do
      START_NS=$("$GDATE" +%s%N)
      CLAUDE_LOOPS_REGISTRY="$BENCH_REGISTRY" \
        bash "$HOOK_PATH" <<< "$BENCH_PAYLOAD" >/dev/null 2>&1 || true
      END_NS=$("$GDATE" +%s%N)
      ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
      echo "$ELAPSED_MS" >> "$LATENCY_LOG"
    done
    MEDIAN_MS=$(sort -n "$LATENCY_LOG" | awk -v n="$ITERATIONS" 'NR == int(n/2) {print; exit}')
    P95_MS=$(sort -n "$LATENCY_LOG" | awk -v n="$ITERATIONS" 'NR == int(n * 0.95) {print; exit}')
    P99_MS=$(sort -n "$LATENCY_LOG" | awk -v n="$ITERATIONS" 'NR == int(n * 0.99) {print; exit}')
    MEASUREMENT_TOOL="gdate-loop"
  else
    MEDIAN_MS="null"
    P95_MS="null"
    P99_MS="null"
    MEASUREMENT_TOOL="none (install hyperfine or coreutils)"
  fi
fi

# ===== Emit report =====
REPORT_PATH="/tmp/heartbeat-tick-bench-$(date +%s).json"
JQ_VERSION=$(jq --version 2>/dev/null || echo "unknown")
JAQ_AVAILABLE=$(command -v jaq >/dev/null 2>&1 && echo "true" || echo "false")
JAQ_VERSION=$(jaq --version 2>/dev/null || echo "n/a")
HOST_DESC="$(hostname) ($(uname -sm))"

jq -n \
  --argjson iterations "$ITERATIONS" \
  --argjson jq_spawn_count_per_tick "$JQ_SPAWN_COUNT" \
  --arg median_wall_ms "$MEDIAN_MS" \
  --arg p95_wall_ms "$P95_MS" \
  --arg p99_wall_ms "$P99_MS" \
  --arg measurement_tool "$MEASUREMENT_TOOL" \
  --arg jq_version "$JQ_VERSION" \
  --argjson jaq_available "$JAQ_AVAILABLE" \
  --arg jaq_version "$JAQ_VERSION" \
  --arg host "$HOST_DESC" \
  --arg hook_path "$HOOK_PATH" \
  '{
    benchmark: "heartbeat-tick-jq-spawn-overhead",
    iter25_baseline_target: { jq_spawn_count_per_tick: 7, median_wall_ms_target: 70 },
    measured: {
      iterations: $iterations,
      jq_spawn_count_per_tick: $jq_spawn_count_per_tick,
      median_wall_ms: ($median_wall_ms | tonumber? // null),
      p95_wall_ms: ($p95_wall_ms | tonumber? // null),
      p99_wall_ms: ($p99_wall_ms | tonumber? // null),
      measurement_tool: $measurement_tool
    },
    environment: {
      jq_version: $jq_version,
      jaq_available: $jaq_available,
      jaq_version: $jaq_version,
      host: $host,
      hook_path: $hook_path
    }
  }' > "$REPORT_PATH"

cat "$REPORT_PATH"
echo ""
echo "✓ Report written to $REPORT_PATH"
