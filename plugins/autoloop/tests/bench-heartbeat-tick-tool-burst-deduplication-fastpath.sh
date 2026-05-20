#!/usr/bin/env bash
# bench-heartbeat-tick-tool-burst-deduplication-fastpath.sh
#
# Measures the wall-clock latency of the iter-27
# tool-burst-tick-deduplication-throttle fast path — i.e. the cost of a
# heartbeat-tick.sh invocation that is SKIPPED because the throttle file
# is fresh.
#
# Why this benchmark exists (iter-27 finding):
#   Pre-iter-27 every Claude Code tool invocation paid the full ~130-165ms
#   heartbeat-tick cost. Tool calls arrive in bursts (5-20 calls / 50ms
#   during read/grep/edit flurries), so a single user message routinely
#   stacked >1 SECOND of hook latency on the user's response.
#
#   Iter-27 adds a session-keyed throttle file (default 500ms window): if
#   a successful tick fired recently, subsequent ticks exit early with
#   zero jq spawns. This bench measures that fast path's overhead — the
#   irreducible cost of "skip this tick" — to confirm it's <10ms and to
#   catch regressions if a future refactor accidentally moves jq work
#   above the throttle gate.
#
# This is the COMPLEMENT to bench-heartbeat-tick-jq-spawn-overhead.sh,
# which measures the SLOW path (when the throttle has expired).
#
# Usage:
#   ./bench-heartbeat-tick-tool-burst-deduplication-fastpath.sh [iterations=200]
#
# Output: writes JSON report to
#   /tmp/heartbeat-tick-tool-burst-deduplication-fastpath-bench-<epoch>.json

set -euo pipefail

# ===== Inputs =====
ITERATIONS="${1:-200}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="$SCRIPT_DIR/../hooks/heartbeat-tick.sh"

if [ ! -x "$HOOK_PATH" ]; then
  echo "✗ Hook not found or not executable: $HOOK_PATH" >&2
  exit 1
fi

# ===== Build fixture (isolated registry + heartbeat + warmed throttle) =====
BENCH_TMP_RAW=$(mktemp -d -t autoloop-bench-throttle-XXXXXX)
BENCH_TMP=$(cd "$BENCH_TMP_RAW" && pwd -P)
trap 'rm -rf "$BENCH_TMP_RAW"' EXIT

BENCH_LOOPS_DIR="$BENCH_TMP/loops"
BENCH_STATE_DIR="$BENCH_TMP/state"
BENCH_REGISTRY="$BENCH_LOOPS_DIR/registry.json"
BENCH_HEARTBEAT="$BENCH_STATE_DIR/heartbeat.json"
BENCH_CONTRACT="$BENCH_TMP/CONTRACT.md"
BENCH_SESSION_ID="bench-throttle-session-$(date +%s)"
BENCH_LOOP_ID="bec0deadbeef"
BENCH_THROTTLE_DIR="$BENCH_TMP/throttle"
BENCH_THROTTLE_FILE="$BENCH_THROTTLE_DIR/$BENCH_SESSION_ID.us"

mkdir -p "$BENCH_LOOPS_DIR" "$BENCH_STATE_DIR/revision-log" "$BENCH_THROTTLE_DIR"
touch "$BENCH_CONTRACT"

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

# Pre-warm the throttle file with a timestamp ~10ms in the future so every
# iteration during the bench hits the throttle. Using a forward-dated value
# absorbs the wall-clock drift across the iteration loop without expiring.
if command -v gdate >/dev/null 2>&1; then
  PRE_WARM_US=$(gdate +%s%6N)  # NOW. Combined with 600s throttle window
                              # (set above), all iterations land inside the
                              # dedup window — measures the steady-state
                              # fast-path latency.
else
  echo "✗ gdate (GNU coreutils) required for this bench. Install: brew install coreutils" >&2
  exit 1
fi
echo "$PRE_WARM_US" > "$BENCH_THROTTLE_FILE"

BENCH_PAYLOAD=$(jq -n \
  --arg sid "$BENCH_SESSION_ID" \
  --arg cwd "$BENCH_TMP" \
  '{session_id: $sid, cwd: $cwd}')

# ===== Spawn-count probe (PATH shadowing) =====
# Throttled fast path should fire ZERO jq processes. If any show up, the
# throttle gate has regressed (jq work landed above the throttle check).
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

# Single throttled tick with the shim to count spawns
PATH="$SHIM_DIR:$PATH" \
  CLAUDE_LOOPS_REGISTRY="$BENCH_REGISTRY" \
  AUTOLOOP_TICK_DEDUP_DIR="$BENCH_THROTTLE_DIR" \
  AUTOLOOP_TICK_DEDUP_INTERVAL_US=600000000 \
  bash "$HOOK_PATH" <<< "$BENCH_PAYLOAD" >/dev/null 2>&1 || true
JQ_SPAWN_COUNT=$(wc -l < "$JQ_SPAWN_LOG" | tr -d ' ')

# ===== Latency measurement (without the shim — measures real performance) =====
LATENCY_LOG="$BENCH_TMP/latency-ms.log"
: > "$LATENCY_LOG"

# Re-pre-warm throttle since the shim's tick may have advanced or not
# touched it. Push it forward another 60s so all iterations hit throttle.
PRE_WARM_US=$(gdate +%s%6N)
echo "$PRE_WARM_US" > "$BENCH_THROTTLE_FILE"

if command -v hyperfine >/dev/null 2>&1; then
  HYPERFINE_JSON="$BENCH_TMP/hyperfine.json"
  CLAUDE_LOOPS_REGISTRY="$BENCH_REGISTRY" \
  AUTOLOOP_TICK_DEDUP_DIR="$BENCH_THROTTLE_DIR" \
  AUTOLOOP_TICK_DEDUP_INTERVAL_US=600000000 \
  hyperfine --warmup 10 --runs "$ITERATIONS" \
    --export-json "$HYPERFINE_JSON" \
    --shell=none \
    "bash $HOOK_PATH" \
    < /dev/null > /dev/null 2>&1 || true

  if [ -f "$HYPERFINE_JSON" ]; then
    MEDIAN_MS=$(jq -r '.results[0].median * 1000' "$HYPERFINE_JSON")
    P95_MS=$(jq -r '.results[0].times | sort | .[(length * 0.95 | floor)] * 1000' "$HYPERFINE_JSON")
    P99_MS=$(jq -r '.results[0].times | sort | .[(length * 0.99 | floor)] * 1000' "$HYPERFINE_JSON")
    MEASUREMENT_TOOL="hyperfine"
  fi
else
  for ((i=0; i<ITERATIONS; i++)); do
    START_NS=$(gdate +%s%N)
    CLAUDE_LOOPS_REGISTRY="$BENCH_REGISTRY" \
    AUTOLOOP_TICK_DEDUP_DIR="$BENCH_THROTTLE_DIR" \
    AUTOLOOP_TICK_DEDUP_INTERVAL_US=600000000 \
      bash "$HOOK_PATH" <<< "$BENCH_PAYLOAD" >/dev/null 2>&1 || true
    END_NS=$(gdate +%s%N)
    ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
    echo "$ELAPSED_MS" >> "$LATENCY_LOG"
  done
  MEDIAN_MS=$(sort -n "$LATENCY_LOG" | awk -v n="$ITERATIONS" 'NR == int(n/2) {print; exit}')
  P95_MS=$(sort -n "$LATENCY_LOG" | awk -v n="$ITERATIONS" 'NR == int(n * 0.95) {print; exit}')
  P99_MS=$(sort -n "$LATENCY_LOG" | awk -v n="$ITERATIONS" 'NR == int(n * 0.99) {print; exit}')
  MEASUREMENT_TOOL="gdate-loop"
fi

# ===== Emit report =====
REPORT_PATH="/tmp/heartbeat-tick-tool-burst-deduplication-fastpath-bench-$(date +%s).json"
JQ_VERSION=$(jq --version 2>/dev/null || echo "unknown")
HOST_DESC="$(hostname) ($(uname -sm))"

jq -n \
  --argjson iterations "$ITERATIONS" \
  --argjson jq_spawn_count_per_throttled_tick "$JQ_SPAWN_COUNT" \
  --arg median_wall_ms "$MEDIAN_MS" \
  --arg p95_wall_ms "$P95_MS" \
  --arg p99_wall_ms "$P99_MS" \
  --arg measurement_tool "$MEASUREMENT_TOOL" \
  --arg jq_version "$JQ_VERSION" \
  --arg host "$HOST_DESC" \
  --arg hook_path "$HOOK_PATH" \
  '{
    benchmark: "heartbeat-tick-tool-burst-deduplication-fastpath",
    iter27_target: {
      jq_spawn_count_per_throttled_tick: 0,
      median_wall_ms_target: 15,
      note: "Throttled tick must do NO jq work — zero spawns. Wall-clock target <15ms covers bash start + gdate + cat; everything above that suggests jq work leaked above the throttle gate or set_contract_field is still firing."
    },
    measured: {
      iterations: $iterations,
      jq_spawn_count_per_throttled_tick: $jq_spawn_count_per_throttled_tick,
      median_wall_ms: ($median_wall_ms | tonumber? // null),
      p95_wall_ms: ($p95_wall_ms | tonumber? // null),
      p99_wall_ms: ($p99_wall_ms | tonumber? // null),
      measurement_tool: $measurement_tool
    },
    environment: {
      jq_version: $jq_version,
      host: $host,
      hook_path: $hook_path
    }
  }' > "$REPORT_PATH"

cat "$REPORT_PATH"
echo ""
echo "✓ Report written to $REPORT_PATH"
