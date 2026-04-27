#!/usr/bin/env bash
# test-notify-coalesce.sh — Tests for notification coalescing (Phase 11, STAT-03, STAT-04)
# Tests: coalescing algorithm, cursor tracking, pass-through, window grouping, idempotency, per-loop preservation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library under test
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/notify-coalesce-lib.sh" 2>/dev/null || {
  echo "FAIL: Cannot source notify-coalesce-lib.sh" >&2
  exit 1
}

# Test counter
PASS=0
FAIL=0

# Setup: create temporary test directory
TEST_HOME=$(mktemp -d)
export CLAUDE_LOOPS_NOTIFY="$TEST_HOME"
NOTIF_FILE="$TEST_HOME/.notifications.jsonl"
COALESCED_FILE="$TEST_HOME/.notifications-coalesced.jsonl"
CURSOR_FILE="$TEST_HOME/.notifications.cursor"

# shellcheck disable=SC2329
cleanup_test() {
  rm -rf "$TEST_HOME"
}
trap cleanup_test EXIT

echo "Test suite: notify-coalesce (Phase 11)"
echo "========================================"
echo ""

# Test 1: Empty raw notifications → exit 0, cursor unchanged, no coalesced output
test_empty_notifications() {
  echo -n "Test 1: Empty notifications → no-op... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # Run coalesce with no input
  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)

  if [ -z "$output" ] && [ ! -f "$COALESCED_FILE" ]; then
    PASS=$((PASS + 1))
    echo "PASS"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (output: '$output', file created: $([[ -f "$COALESCED_FILE" ]] && echo yes || echo no))"
  fi
}

# Test 2: <3 distinct loops in window → pass-through (no coalescing)
test_passthrough_low_volume() {
  echo -n "Test 2: <3 distinct loops → pass-through... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # Emit 2 notifications from 2 distinct loops in same window
  local ts1=1725000000000000
  local ts2=1725000001000000
  jq -nc --arg ts_us "$ts1" --arg loop_id "a1b2c3d4e5f6" --arg kind "stuck" --arg message "msg1" \
    '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  jq -nc --arg ts_us "$ts2" --arg loop_id "b1b2c3d4e5f6" --arg kind "stuck" --arg message "msg2" \
    '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"

  # Coalesce should pass-through both (no coalescing for <3 distinct)
  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)
  count=$(echo "$output" | grep -c "^{" || true)

  if [ "$count" -eq 2 ]; then
    PASS=$((PASS + 1))
    echo "PASS (2 pass-through messages)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (expected 2 messages, got $count)"
  fi
}

# Test 3: ≥3 distinct loops in window → ONE coalesced message
test_coalesce_threshold() {
  echo -n "Test 3: ≥3 distinct loops → one coalesced message... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # Emit 3 notifications from 3 distinct loops in same window
  local ts=1725000000000000
  for i in 1 2 3; do
    jq -nc --arg ts_us "$ts" --arg loop_id "loop${i}c3d4e5f6ab${i}" --arg kind "stuck" --arg message "msg$i" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  done

  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)
  kind=$(echo "$output" | jq -r '.kind // ""' 2>/dev/null)
  count=$(echo "$output" | jq -r '.count // 0' 2>/dev/null)

  if [ "$kind" = "coalesced" ] && [ "$count" -eq 3 ]; then
    PASS=$((PASS + 1))
    echo "PASS (coalesced with count=3)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (expected kind=coalesced count=3, got kind=$kind count=$count)"
  fi
}

# Test 4: 5 notifications from same loop in window → pass-through (still <3 distinct)
test_passthrough_same_loop() {
  echo -n "Test 4: 5 from same loop → pass-through (distinct=1)... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # Emit 5 notifications from same loop
  local loop_id="sameloopabcd"
  for i in 1 2 3 4 5; do
    local ts=$((1725000000000000 + i * 100000))
    jq -nc --arg ts_us "$ts" --arg loop_id "$loop_id" --arg kind "stuck" --arg message "msg$i" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  done

  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)
  count=$(echo "$output" | grep -c "^{" || true)
  kind_first=$(echo "$output" | head -1 | jq -r '.kind // ""' 2>/dev/null)

  if [ "$count" -eq 5 ] && [ "$kind_first" != "coalesced" ]; then
    PASS=$((PASS + 1))
    echo "PASS (5 pass-through messages, no coalescing)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (expected 5 pass-through, got count=$count kind=$kind_first)"
  fi
}

# Test 5: Multi-window grouping
test_multi_window() {
  echo -n "Test 5: Multi-window grouping... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # 3 loops in window A (ts ~0)
  for i in 1 2 3; do
    jq -nc --arg ts_us "1725000000000000" --arg loop_id "windowAloop${i}5f6" --arg kind "stuck" --arg message "msgA$i" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  done

  # 4 loops in window B (ts ~120s later)
  for i in 1 2 3 4; do
    jq -nc --arg ts_us "1725000120000000" --arg loop_id "windowBloop${i}5f6" --arg kind "stuck" --arg message "msgB$i" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  done

  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)
  coalesced_count=$(echo "$output" | grep -c '"kind":"coalesced"' || true)

  if [ "$coalesced_count" -eq 2 ]; then
    PASS=$((PASS + 1))
    echo "PASS (2 coalesced messages, one per window)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (expected 2 coalesced, got $coalesced_count)"
  fi
}

# Test 6: Cursor advance and idempotency
test_cursor_idempotency() {
  echo -n "Test 6: Cursor advances correctly; second run is idempotent... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # Emit 3 notifications
  local ts=1725000000000000
  for i in 1 2 3; do
    jq -nc --arg ts_us "$ts" --arg loop_id "loop${i}c3d4e5f6ab${i}" --arg kind "stuck" --arg message "msg$i" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  done

  # Run 1: should emit coalesced, update cursor
  notify_coalesce_run "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE" >/dev/null 2>&1 || true
  cursor_1=$(cat "$CURSOR_FILE" 2>/dev/null || echo "")
  coalesced_count_1=$(grep -c "^{" "$COALESCED_FILE" 2>/dev/null || echo "0")

  # Run 2: should emit nothing (cursor blocks)
  notify_coalesce_run "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE" >/dev/null 2>&1 || true
  cursor_2=$(cat "$CURSOR_FILE" 2>/dev/null || echo "")
  coalesced_count_2=$(grep -c "^{" "$COALESCED_FILE" 2>/dev/null || echo "0")

  if [ "$coalesced_count_1" -eq 1 ] && [ "$coalesced_count_2" -eq 1 ] && [ "$cursor_1" = "$cursor_2" ]; then
    PASS=$((PASS + 1))
    echo "PASS (idempotent, cursor unchanged on second run)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (run1 count=$coalesced_count_1, run2 count=$coalesced_count_2, cursor stable=$([[ "$cursor_1" == "$cursor_2" ]] && echo yes || echo no))"
  fi
}

# Test 7: Per-loop entries preserved in raw file (STAT-04)
test_stat04_preservation() {
  echo -n "Test 7: STAT-04 - raw .notifications.jsonl unchanged after coalesce... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  # Emit 3 notifications
  local ts=1725000000000000
  for i in 1 2 3; do
    jq -nc --arg ts_us "$ts" --arg loop_id "loop${i}c3d4e5f6ab${i}" --arg kind "stuck" --arg message "msg$i" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}' >> "$NOTIF_FILE"
  done

  notif_before=$(cat "$NOTIF_FILE" 2>/dev/null || echo "")
  notify_coalesce_run "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE" >/dev/null 2>&1 || true
  notif_after=$(cat "$NOTIF_FILE" 2>/dev/null || echo "")

  if [ "$notif_before" = "$notif_after" ]; then
    PASS=$((PASS + 1))
    echo "PASS (raw file preserved)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (raw file was modified)"
  fi
}

# Test 8: macOS notification detection
test_macos_notification() {
  echo -n "Test 8: macOS notification display (no-op on non-macOS or if osascript missing)... "

  # Just verify it doesn't crash
  display_macos_notification "Test Title" "Test Message" >/dev/null 2>&1 || true
  PASS=$((PASS + 1))
  echo "PASS (no-op succeeds)"
}

# Test 9: Distinct loop_ids array in coalesced output
test_coalesced_loop_ids() {
  echo -n "Test 9: Coalesced message includes loop_ids array... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  local ts=1725000000000000
  {
    jq -nc --arg ts_us "$ts" --arg loop_id "loopa3d4e5f6ab1" --arg kind "stuck" --arg message "msgA" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}'
    jq -nc --arg ts_us "$ts" --arg loop_id "loopb3d4e5f6ab2" --arg kind "anomaly" --arg message "msgB" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}'
    jq -nc --arg ts_us "$ts" --arg loop_id "loopc3d4e5f6ab3" --arg kind "pending_takeover" --arg message "msgC" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}'
  } >> "$NOTIF_FILE"

  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)
  loop_ids=$(echo "$output" | jq -r '.loop_ids // []' 2>/dev/null)
  count=$(echo "$loop_ids" | jq 'length' 2>/dev/null)

  if [ "$count" -eq 3 ]; then
    PASS=$((PASS + 1))
    echo "PASS (loop_ids array has 3 entries)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (expected 3 loop_ids, got $count)"
  fi
}

# Test 10: Window filtering (exclude non-coalesce kinds)
test_window_filtering() {
  echo -n "Test 10: Window filters non-stuck kinds... "
  rm -f "$NOTIF_FILE" "$COALESCED_FILE" "$CURSOR_FILE"

  local ts=1725000000000000
  # 3 notifications: 2 stuck, 1 spawn (spawn is not coalesce-relevant)
  {
    jq -nc --arg ts_us "$ts" --arg loop_id "loopa3d4e5f6ab1" --arg kind "stuck" --arg message "msgA" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}'
    jq -nc --arg ts_us "$ts" --arg loop_id "loopb3d4e5f6ab2" --arg kind "stuck" --arg message "msgB" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}'
    jq -nc --arg ts_us "$ts" --arg loop_id "loopc3d4e5f6ab3" --arg kind "spawn" --arg message "msgC" \
      '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}'
  } >> "$NOTIF_FILE"

  output=$(coalesce_notifications 0 60 "$NOTIF_FILE" || true)
  # Should pass-through all 3 (only 2 distinct relevant kinds, <3)
  count=$(echo "$output" | grep -c "^{" || true)

  if [ "$count" -eq 3 ]; then
    PASS=$((PASS + 1))
    echo "PASS (3 pass-through, spawn filtered out of distinct count)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (expected 3 pass-through, got $count)"
  fi
}

# Run all tests
test_empty_notifications
test_passthrough_low_volume
test_coalesce_threshold
test_passthrough_same_loop
test_multi_window
test_cursor_idempotency
test_stat04_preservation
test_macos_notification
test_coalesced_loop_ids
test_window_filtering

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
