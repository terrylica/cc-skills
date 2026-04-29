#!/usr/bin/env bash
# test-empty-firing.sh — Tests for hooks/empty-firing-detector.sh.
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/empty-firing-detector.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
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

mk_transcript() {
  local sid="$1" want_schedule="$2" want_other="$3"
  local f="$TEMP_DIR/transcript-$sid.jsonl"
  : >"$f"
  local i=0
  while [ "$i" -lt "$want_schedule" ]; do
    jq -nc --arg sid "$sid" '{sessionId:$sid, message:{content:[{type:"tool_use",name:"ScheduleWakeup"}]}}' >>"$f"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$want_other" ]; do
    jq -nc --arg sid "$sid" '{sessionId:$sid, message:{content:[{type:"tool_use",name:"Edit"}]}}' >>"$f"
    i=$((i + 1))
  done
  printf '%s' "$f"
}

run_hook() {
  local sid="$1" tpath="$2"
  local payload
  payload=$(jq -nc --arg s "$sid" --arg t "$tpath" '{
    session_id: $s, transcript_path: $t, hook_event_name: "Stop"
  }')
  echo "$payload" | bash "$HOOK" 2>/dev/null || true
}

reset() {
  rm -rf "$HOME/.claude/loops"
  mkdir -p "$HOME/.claude/loops"
}

# ===== Test 1: ScheduleWakeup-only (1 schedule, 0 other) → empty_firing_detected =====
echo "Test 1: 1 ScheduleWakeup + 0 other → empty_firing_detected"
reset
T=$(mk_transcript "session-A" 1 0)
run_hook "session-A" "$T"
COUNT=$(jq -sr '[.[] | select(.event == "empty_firing_detected" and .session_id == "session-A")] | length' "$PROVENANCE_GLOBAL_FILE")
assert_eq "$COUNT" "1" "empty_firing_detected emitted"

# ===== Test 2: real work present → no event =====
echo ""
echo "Test 2: 1 ScheduleWakeup + 5 Edit → no event"
reset
T=$(mk_transcript "session-B" 1 5)
run_hook "session-B" "$T"
COUNT=0
if [ -f "$PROVENANCE_GLOBAL_FILE" ]; then
  COUNT=$(jq -sr '[.[] | select(.event == "empty_firing_detected" and .session_id == "session-B")] | length' "$PROVENANCE_GLOBAL_FILE" || echo 0)
fi
assert_eq "$COUNT" "0" "no event when real work present"

# ===== Test 3: no ScheduleWakeup at all → no event =====
echo ""
echo "Test 3: 0 ScheduleWakeup + 3 Edit → no event"
reset
T=$(mk_transcript "session-C" 0 3)
run_hook "session-C" "$T"
COUNT=0
if [ -f "$PROVENANCE_GLOBAL_FILE" ]; then
  COUNT=$(jq -sr '[.[] | select(.event == "empty_firing_detected" and .session_id == "session-C")] | length' "$PROVENANCE_GLOBAL_FILE" || echo 0)
fi
assert_eq "$COUNT" "0" "no event when no ScheduleWakeup"

# ===== Test 4: missing transcript → graceful (no error, no event) =====
echo ""
echo "Test 4: missing transcript → graceful exit 0"
reset
echo '{"session_id":"x","transcript_path":"/nonexistent/path","hook_event_name":"Stop"}' | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "exit 0 on missing transcript"

# ===== Test 5: empty stdin → graceful =====
echo ""
echo "Test 5: empty stdin → graceful exit 0"
reset
echo "" | bash "$HOOK" 2>/dev/null
RC=$?
assert_eq "$RC" "0" "exit 0 on empty stdin"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
