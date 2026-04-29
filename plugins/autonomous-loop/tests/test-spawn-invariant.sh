#!/usr/bin/env bash
# test-spawn-invariant.sh — Tests for waker.sh _invariant_check_spawn (WAKE-01..05).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
export CLAUDE_LOOPS_REGISTRY="$HOME/.claude/loops/registry.json"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source libraries needed for invariant function
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/ownership-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/notifications-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/provenance-lib.sh"

# Extract _invariant_check_spawn by sourcing waker.sh in a guarded way.
# waker.sh runs main() at the bottom; we override main to no-op.
main() { :; }
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/waker.sh" 2>/dev/null || true

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

# Build minimal registry entry; returns the entry as JSON.
build_entry() {
  local loop_id="$1" sid="$2" gen="${3:-0}"
  local contract_dir="$TEMP_DIR/proj-$loop_id"
  mkdir -p "$contract_dir/.loop-state/$loop_id"
  local contract="$contract_dir/LOOP_CONTRACT.md"
  echo "---" >"$contract"
  jq -nc \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract" \
    --arg state_dir "$contract_dir/.loop-state/$loop_id/" \
    --arg owner_session_id "$sid" \
    --argjson generation "$gen" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, generation: $generation}'
}

# Register entry into registry (so read_registry_entry under invariant works).
put_entry() {
  local entry="$1"
  if [ ! -f "$CLAUDE_LOOPS_REGISTRY" ]; then
    echo '{"schema_version": 1, "loops": []}' >"$CLAUDE_LOOPS_REGISTRY"
  fi
  jq --argjson e "$entry" '.loops += [$e]' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
}

reset() {
  rm -rf "$HOME/.claude/loops" "$TEMP_DIR/proj-"*
  mkdir -p "$HOME/.claude/loops"
}

# Write a heartbeat.json with given fields
write_hb() {
  local state_dir="$1" bound_cwd="$2" drift="${3:-false}"
  mkdir -p "$state_dir"
  jq -nc \
    --arg bc "$bound_cwd" \
    --argjson df "$drift" \
    --arg lwu "$(python3 -c "import time; print(int(time.time()*1_000_000))")" \
    '{bound_cwd: $bc, cwd_drift_detected: $df, last_wake_us: $lwu, iteration: 1}' \
    >"$state_dir/heartbeat.json"
}

# ===== Test 1: invalid UUID (pending-bind) → spawn_refused_invalid_session_id =====
echo "Test 1: invalid UUID"
reset
ENTRY=$(build_entry "111111111111" "anything")
put_entry "$ENTRY"
if _invariant_check_spawn "111111111111" "$ENTRY" "pending-bind" "1500"; then
  assert_eq "passed" "refused" "invariant should refuse pending-bind"
else
  EVT=$(jq -sr '.[] | select(.event=="spawn_refused_invalid_session_id" and .loop_id=="111111111111") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
  assert_eq "$EVT" "spawn_refused_invalid_session_id" "spawn_refused_invalid_session_id event emitted"
fi

# ===== Test 2: no heartbeat → spawn_refused_no_heartbeat =====
echo ""
echo "Test 2: no heartbeat"
reset
SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
ENTRY=$(build_entry "222222222222" "$SID")
put_entry "$ENTRY"
if _invariant_check_spawn "222222222222" "$ENTRY" "$SID" "1500"; then
  assert_eq "passed" "refused" "invariant should refuse without heartbeat"
else
  EVT=$(jq -sr '.[] | select(.event=="spawn_refused_no_heartbeat" and .loop_id=="222222222222") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
  assert_eq "$EVT" "spawn_refused_no_heartbeat" "spawn_refused_no_heartbeat event"
fi

# ===== Test 3: cwd drift (bound_cwd != contract_dir) → spawn_refused_cwd_drift =====
echo ""
echo "Test 3: cwd drift"
reset
ENTRY=$(build_entry "333333333333" "$SID")
put_entry "$ENTRY"
STATE_DIR=$(echo "$ENTRY" | jq -r '.state_dir')
write_hb "$STATE_DIR" "/some/wrong/dir" false
if _invariant_check_spawn "333333333333" "$ENTRY" "$SID" "1500"; then
  assert_eq "passed" "refused" "invariant should refuse cwd drift"
else
  EVT=$(jq -sr '.[] | select(.event=="spawn_refused_cwd_drift" and .loop_id=="333333333333") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
  assert_eq "$EVT" "spawn_refused_cwd_drift" "spawn_refused_cwd_drift event"
fi

# ===== Test 4: cwd_drift_detected flag set → refused =====
echo ""
echo "Test 4: cwd_drift_detected flag"
reset
ENTRY=$(build_entry "444444444444" "$SID")
put_entry "$ENTRY"
STATE_DIR=$(echo "$ENTRY" | jq -r '.state_dir')
CONTRACT_DIR="$TEMP_DIR/proj-444444444444"
write_hb "$STATE_DIR" "$CONTRACT_DIR" true
if _invariant_check_spawn "444444444444" "$ENTRY" "$SID" "1500"; then
  assert_eq "passed" "refused" "invariant should refuse when cwd_drift_detected=true"
else
  EVT=$(jq -sr '.[] | select(.event=="spawn_refused_cwd_drift" and .loop_id=="444444444444") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
  assert_eq "$EVT" "spawn_refused_cwd_drift" "spawn_refused_cwd_drift event (flag-based)"
fi

# ===== Test 5: generation drift → spawn_refused_generation_drift =====
echo ""
echo "Test 5: generation drift"
reset
ENTRY=$(build_entry "555555555555" "$SID" 1)
put_entry "$ENTRY"
STATE_DIR=$(echo "$ENTRY" | jq -r '.state_dir')
CONTRACT_DIR="$TEMP_DIR/proj-555555555555"
write_hb "$STATE_DIR" "$CONTRACT_DIR" false
# Bump registry generation AFTER snapshotting entry
jq '.loops[0].generation = 2' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
if _invariant_check_spawn "555555555555" "$ENTRY" "$SID" "1500"; then
  assert_eq "passed" "refused" "invariant should refuse on generation drift"
else
  EVT=$(jq -sr '.[] | select(.event=="spawn_refused_generation_drift" and .loop_id=="555555555555") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
  assert_eq "$EVT" "spawn_refused_generation_drift" "spawn_refused_generation_drift event"
fi

# ===== Test 6: all invariants hold → invariants_passed event =====
echo ""
echo "Test 6: happy path (all invariants pass)"
reset
ENTRY=$(build_entry "666666666666" "$SID" 0)
put_entry "$ENTRY"
STATE_DIR=$(echo "$ENTRY" | jq -r '.state_dir')
CONTRACT_DIR="$TEMP_DIR/proj-666666666666"
write_hb "$STATE_DIR" "$CONTRACT_DIR" false
if _invariant_check_spawn "666666666666" "$ENTRY" "$SID" "1500"; then
  EVT=$(jq -sr '.[] | select(.event=="spawn_invariants_passed" and .loop_id=="666666666666") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
  assert_eq "$EVT" "spawn_invariants_passed" "spawn_invariants_passed event emitted"
else
  assert_eq "refused" "passed" "invariant should pass when all checks OK"
fi

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
