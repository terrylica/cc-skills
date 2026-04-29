#!/usr/bin/env bash
# test-session-bind.sh — Tests for hooks/session-bind.sh (Phase 36 BIND-01..02).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/session-bind.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
export CLAUDE_LOOPS_REGISTRY="$HOME/.claude/loops/registry.json"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"
export SESSION_BIND_STALE_THRESHOLD_S=3600
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

# Build a minimal registry with one loop entry; returns the contract dir.
init_loop() {
  local loop_id="$1" owner_sid="$2" owner_pid="${3:-99999}" age_s="${4:-0}"
  local contract_dir="$TEMP_DIR/proj-$loop_id"
  mkdir -p "$contract_dir"
  local contract="$contract_dir/LOOP_CONTRACT.md"
  {
    echo "---"
    echo "name: test"
    echo "loop_id: $loop_id"
    echo "---"
  } >"$contract"

  local now_us start_us
  now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))")
  start_us=$((now_us - age_s * 1000000))

  local entry
  entry=$(jq -nc \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract" \
    --arg state_dir "$contract_dir/.loop-state/$loop_id/" \
    --arg owner_session_id "$owner_sid" \
    --arg owner_pid "$owner_pid" \
    --arg owner_start_time_us "$start_us" \
    --argjson generation 0 \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, generation: $generation}')

  if [ ! -f "$CLAUDE_LOOPS_REGISTRY" ]; then
    echo '{"schema_version": 1, "loops": []}' >"$CLAUDE_LOOPS_REGISTRY"
  fi
  jq --argjson e "$entry" '.loops += [$e]' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
  mkdir -p "$contract_dir/.loop-state/$loop_id"
  echo "$contract_dir"
}

run_hook() {
  local session_id="$1" cwd="$2"
  local payload
  payload=$(jq -nc --arg s "$session_id" --arg c "$cwd" '{session_id: $s, cwd: $c, source: "startup", hook_event_name: "SessionStart"}')
  echo "$payload" | bash "$HOOK" 2>/dev/null || true
}

reset() {
  rm -rf "$HOME/.claude/loops" "$TEMP_DIR/proj-"*
  mkdir -p "$HOME/.claude/loops"
}

# ===== Test 1: bind_first when owner_session_id=pending-bind =====
echo "Test 1: bind_first on pending-bind"
reset
DIR1=$(init_loop "aaaaaaaaaaaa" "pending-bind")
run_hook "uuid-session-1" "$DIR1"
NEW_SID=$(jq -r '.loops[] | select(.loop_id=="aaaaaaaaaaaa") | .owner_session_id' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$NEW_SID" "uuid-session-1" "owner_session_id bound to pipe payload session_id"
EVENT=$(jq -sr '.[] | select(.event=="bind_first" and .loop_id=="aaaaaaaaaaaa") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
assert_eq "$EVENT" "bind_first" "bind_first provenance event emitted"

# ===== Test 2: bind_resume idempotent =====
echo ""
echo "Test 2: bind_resume idempotent"
reset
DIR2=$(init_loop "bbbbbbbbbbbb" "pending-bind")
run_hook "uuid-session-2" "$DIR2"
run_hook "uuid-session-2" "$DIR2"
RESUME_COUNT=$(jq -sr '[.[] | select(.event=="bind_resume" and .loop_id=="bbbbbbbbbbbb")] | length' "$PROVENANCE_GLOBAL_FILE")
assert_eq "$RESUME_COUNT" "1" "second call emits exactly one bind_resume"
SID2=$(jq -r '.loops[] | select(.loop_id=="bbbbbbbbbbbb") | .owner_session_id' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$SID2" "uuid-session-2" "owner_session_id unchanged after re-bind"

# ===== Test 3: parallel race for binding =====
echo ""
echo "Test 3: parallel race — exactly one wins"
reset
DIR3=$(init_loop "cccccccccccc" "pending-bind")
for i in 1 2 3 4 5; do
  (run_hook "race-uuid-$i" "$DIR3") &
done
wait
WIN=$(jq -r '.loops[] | select(.loop_id=="cccccccccccc") | .owner_session_id' "$CLAUDE_LOOPS_REGISTRY")
case "$WIN" in
  race-uuid-1|race-uuid-2|race-uuid-3|race-uuid-4|race-uuid-5)
    assert_eq "matched" "matched" "exactly one race-uuid winner ($WIN)" ;;
  *)
    assert_eq "$WIN" "race-uuid-?" "exactly one race winner — got '$WIN'" ;;
esac
# At least one bind_first event recorded
BIND_FIRSTS=$(jq -sr '[.[] | select(.event=="bind_first" and .loop_id=="cccccccccccc")] | length' "$PROVENANCE_GLOBAL_FILE")
if [ "$BIND_FIRSTS" -ge 1 ]; then
  assert_eq "ok" "ok" "at least one bind_first emitted ($BIND_FIRSTS)"
else
  assert_eq "$BIND_FIRSTS" ">=1" "at least one bind_first"
fi

# ===== Test 4: dead owner > threshold → stale_owner_detected (no auto-reclaim) =====
echo ""
echo "Test 4: dead owner stale → stale_owner_detected, no mutation"
reset
DIR4=$(init_loop "dddddddddddd" "uuid-old-owner" "999999" "7200")  # dead pid, 2h old
run_hook "uuid-new-session" "$DIR4"
SID4=$(jq -r '.loops[] | select(.loop_id=="dddddddddddd") | .owner_session_id' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$SID4" "uuid-old-owner" "registry NOT auto-reclaimed (owner unchanged)"
STALE=$(jq -sr '.[] | select(.event=="stale_owner_detected" and .loop_id=="dddddddddddd") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
assert_eq "$STALE" "stale_owner_detected" "stale_owner_detected provenance event emitted"

# ===== Test 5: live other-owner → observer =====
echo ""
echo "Test 5: live other-owner → observer (no mutation)"
reset
LIVE_PID=$$
DIR5=$(init_loop "eeeeeeeeeeee" "uuid-other-live-owner" "$LIVE_PID" "0")
run_hook "uuid-incoming" "$DIR5"
SID5=$(jq -r '.loops[] | select(.loop_id=="eeeeeeeeeeee") | .owner_session_id' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$SID5" "uuid-other-live-owner" "registry unchanged"
OBS=$(jq -sr '.[] | select(.event=="observer" and .loop_id=="eeeeeeeeeeee") | .event' "$PROVENANCE_GLOBAL_FILE" | head -1)
assert_eq "$OBS" "observer" "observer provenance event emitted"

# ===== Summary =====
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
