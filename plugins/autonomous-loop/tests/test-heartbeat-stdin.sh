#!/usr/bin/env bash
# test-heartbeat-stdin.sh — Tests for heartbeat-tick.sh stdin reading + cwd-drift (BIND-03).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/heartbeat-tick.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
export CLAUDE_LOOPS_REGISTRY="$HOME/.claude/loops/registry.json"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0
assert_eq() {
  if [ "$1" = "$2" ]; then
    echo "  ✓ PASS: $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $3 (expected=$2 actual=$1)"
    FAIL=$((FAIL + 1))
  fi
}

init_loop_bound() {
  local loop_id="$1" sid="$2"
  local contract_dir="$TEMP_DIR/proj-$loop_id"
  mkdir -p "$contract_dir/.loop-state/$loop_id"
  local contract="$contract_dir/LOOP_CONTRACT.md"
  {
    echo "---"
    echo "name: test"
    echo "loop_id: $loop_id"
    echo "---"
  } >"$contract"

  local now_us
  now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))")
  local entry
  entry=$(jq -nc \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract" \
    --arg state_dir "$contract_dir/.loop-state/$loop_id/" \
    --arg owner_session_id "$sid" \
    --arg owner_pid "$$" \
    --arg owner_start_time_us "$now_us" \
    --argjson generation 0 \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, generation: $generation}')
  if [ ! -f "$CLAUDE_LOOPS_REGISTRY" ]; then
    echo '{"schema_version": 1, "loops": []}' >"$CLAUDE_LOOPS_REGISTRY"
  fi
  jq --argjson e "$entry" '.loops += [$e]' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
  echo "$contract_dir"
}

reset() {
  rm -rf "$HOME/.claude/loops" "$TEMP_DIR/proj-"*
  mkdir -p "$HOME/.claude/loops"
}

run_hook() {
  local session_id="$1" cwd="$2"
  local payload
  payload=$(jq -nc --arg s "$session_id" --arg c "$cwd" '{session_id: $s, cwd: $c, hook_event_name: "PostToolUse"}')
  echo "$payload" | bash "$HOOK" 2>/dev/null || true
}

# ===== Test 1: stdin happy path — heartbeat written, bound_cwd recorded =====
echo "Test 1: stdin happy path — heartbeat + bound_cwd recorded"
reset
DIR1=$(init_loop_bound "1111aaaa1111" "uuid-1")
run_hook "uuid-1" "$DIR1"
HB="$DIR1/.loop-state/1111aaaa1111/heartbeat.json"
if [ -f "$HB" ]; then
  assert_eq "exists" "exists" "heartbeat.json created"
else
  assert_eq "missing" "exists" "heartbeat.json"
fi
BOUND=$(jq -r '.bound_cwd // ""' "$HB" 2>/dev/null)
assert_eq "$BOUND" "$DIR1" "bound_cwd recorded on first tick"

# ===== Test 2: cwd drift sets cwd_drift_detected and emits provenance =====
echo ""
echo "Test 2: cwd drift detection"
reset
DIR2=$(init_loop_bound "2222bbbb2222" "uuid-2")
# First tick at correct cwd to record bound_cwd
run_hook "uuid-2" "$DIR2"
# Second tick from a DIFFERENT cwd
DIFF_CWD="$TEMP_DIR/somewhere-else"
mkdir -p "$DIFF_CWD"
run_hook "uuid-2" "$DIFF_CWD"
HB2="$DIR2/.loop-state/2222bbbb2222/heartbeat.json"
DRIFT=$(jq -r '.cwd_drift_detected // false' "$HB2" 2>/dev/null)
assert_eq "$DRIFT" "true" "cwd_drift_detected flag set in heartbeat.json"
DRIFT_EVENT=$(jq -sr '.[] | select(.event=="cwd_drift_detected" and .loop_id=="2222bbbb2222") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
assert_eq "$DRIFT_EVENT" "cwd_drift_detected" "cwd_drift_detected provenance event emitted"

# ===== Test 3: empty stdin + no env var → graceful exit =====
echo ""
echo "Test 3: empty stdin + no env var → graceful no-op"
reset
DIR3=$(init_loop_bound "3333cccc3333" "uuid-3")
# Pipe empty stdin and unset env
unset CLAUDE_SESSION_ID 2>/dev/null || true
echo "" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "exit code 0 (graceful)"
HB3="$DIR3/.loop-state/3333cccc3333/heartbeat.json"
if [ ! -f "$HB3" ]; then
  assert_eq "no" "no" "no heartbeat written without session_id"
else
  assert_eq "yes" "no" "no heartbeat (file exists)"
fi

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
