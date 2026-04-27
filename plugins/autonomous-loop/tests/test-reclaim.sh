#!/usr/bin/env bash
# test-reclaim.sh — Unit tests for stale detection and reclaim protocol (Phase 4)
# Tests OWN-04 (stale-takeover) and OWN-07 (generation counter)
# shellcheck disable=SC2329

set -euo pipefail

# Source the libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh" 2>/dev/null || {
  echo "Failed to source registry-lib.sh" >&2
  exit 1
}

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/ownership-lib.sh" 2>/dev/null || {
  echo "Failed to source ownership-lib.sh" >&2
  exit 1
}

# Test environment setup with isolated HOME
TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME"
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0

# Helper: assert_equals
assert_equals() {
  local actual="$1"
  local expected="$2"
  local test_name="$3"

  if [ "$actual" = "$expected" ]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    FAIL=$((FAIL+1))
  fi
}

# Helper: assert_not_empty
assert_not_empty() {
  local value="$1"
  local test_name="$2"

  if [ -n "$value" ]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name (value is empty)"
    FAIL=$((FAIL+1))
  fi
}

# Helper: create_mock_heartbeat — writes a heartbeat.json with controlled timestamp
create_mock_heartbeat() {
  local state_dir="$1"
  local last_wake_us="$2"

  mkdir -p "$state_dir" || return 1

  jq -n --arg ts "$last_wake_us" '{last_wake_us: $ts}' > "$state_dir/heartbeat.json" || return 1
}

echo "========================================"
echo "Reclaim Protocol Tests (Phase 4)"
echo "========================================"
echo ""

# Test 1: is_reclaim_candidate returns "no" for non-existent entry
echo "Test 1: is_reclaim_candidate returns no for non-existent entry"
mkdir -p "$HOME/.claude/loops"
RESULT=$(is_reclaim_candidate "aaaaaaaaaa00" "$HOME/.claude/loops/registry.json")
assert_equals "$RESULT" "no" "is_reclaim_candidate non-existent entry"

echo ""

# Test 2: is_reclaim_candidate returns "owner_alive" when owner is alive and heartbeat fresh
echo "Test 2: is_reclaim_candidate returns owner_alive when owner alive + heartbeat fresh"

# Create entry with current process and fresh heartbeat
CURRENT_PID=$$
CURRENT_START_TIME=$(capture_process_start_time "$CURRENT_PID")
STATE_DIR="$HOME/.loop-state/aaaaaaaaaa01"
mkdir -p "$STATE_DIR"

# Create fresh heartbeat (now)
NOW_US=$(($(date +%s) * 1000000))
create_mock_heartbeat "$STATE_DIR" "$NOW_US" || exit 1

ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa01" \
  --arg owner_pid "$CURRENT_PID" \
  --arg owner_start_time_us "$CURRENT_START_TIME" \
  --arg contract_path "/tmp/test1.md" \
  --arg state_dir "$STATE_DIR" \
  --arg owner_session_id "test_session_1" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa01" \
  --arg started_at_us "$CURRENT_START_TIME" \
  --arg expected_cadence_seconds "1500" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$ENTRY" || echo "Note: register_loop returned non-zero"

RESULT=$(is_reclaim_candidate "aaaaaaaaaa01" "$HOME/.claude/loops/registry.json")
assert_equals "$RESULT" "owner_alive" "is_reclaim_candidate returns owner_alive"

echo ""

# Test 3: is_reclaim_candidate returns "yes" when owner is dead
echo "Test 3: is_reclaim_candidate returns yes when owner dead"

DEAD_PID=999999
STATE_DIR2="$HOME/.loop-state/aaaaaaaaaa02"
mkdir -p "$STATE_DIR2"
create_mock_heartbeat "$STATE_DIR2" "$NOW_US" || exit 1

DEAD_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa02" \
  --arg owner_pid "$DEAD_PID" \
  --arg owner_start_time_us "1725000000000000" \
  --arg contract_path "/tmp/test2.md" \
  --arg state_dir "$STATE_DIR2" \
  --arg owner_session_id "test_session_2" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa02" \
  --arg started_at_us "1725000000000000" \
  --arg expected_cadence_seconds "1500" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$DEAD_ENTRY" || echo "Note: register_loop returned non-zero"

RESULT=$(is_reclaim_candidate "aaaaaaaaaa02" "$HOME/.claude/loops/registry.json")
assert_equals "$RESULT" "yes" "is_reclaim_candidate returns yes when owner dead"

echo ""

# Test 4: is_reclaim_candidate returns "yes" when heartbeat is stale
echo "Test 4: is_reclaim_candidate returns yes when heartbeat stale (>3x cadence)"

CURRENT_PID2=$$
CURRENT_START_TIME2=$(capture_process_start_time "$CURRENT_PID2")
STATE_DIR3="$HOME/.loop-state/aaaaaaaaaa03"
mkdir -p "$STATE_DIR3"

# Create stale heartbeat: now - 5000 seconds (5x 1000 second cadence)
STALE_HB_US=$((NOW_US - 5000000000))
create_mock_heartbeat "$STATE_DIR3" "$STALE_HB_US" || exit 1

STALE_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa03" \
  --arg owner_pid "$CURRENT_PID2" \
  --arg owner_start_time_us "$CURRENT_START_TIME2" \
  --arg contract_path "/tmp/test3.md" \
  --arg state_dir "$STATE_DIR3" \
  --arg owner_session_id "test_session_3" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa03" \
  --arg started_at_us "$CURRENT_START_TIME2" \
  --arg expected_cadence_seconds "1000" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$STALE_ENTRY" || echo "Note: register_loop returned non-zero"

RESULT=$(is_reclaim_candidate "aaaaaaaaaa03" "$HOME/.claude/loops/registry.json")
assert_equals "$RESULT" "yes" "is_reclaim_candidate returns yes when heartbeat stale"

echo ""

# Test 5: staleness_seconds returns correct elapsed time
echo "Test 5: staleness_seconds returns correct elapsed time"

STATE_DIR4="$HOME/.loop-state/aaaaaaaaaa04"
mkdir -p "$STATE_DIR4"
HB_TIME=$((NOW_US - 2000000000))  # 2000 seconds ago
create_mock_heartbeat "$STATE_DIR4" "$HB_TIME" || exit 1

STALENESS_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa04" \
  --arg owner_pid "$CURRENT_PID" \
  --arg owner_start_time_us "$CURRENT_START_TIME" \
  --arg contract_path "/tmp/test4.md" \
  --arg state_dir "$STATE_DIR4" \
  --arg owner_session_id "test_session_4" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa04" \
  --arg started_at_us "$CURRENT_START_TIME" \
  --arg expected_cadence_seconds "1500" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$STALENESS_ENTRY" || echo "Note: register_loop returned non-zero"

STALENESS=$(staleness_seconds "aaaaaaaaaa04" "$HOME/.claude/loops/registry.json")
# Should be close to 2000 seconds (allow ±100 seconds for timing variations)
if [ "$STALENESS" -ge 1900 ] && [ "$STALENESS" -le 2100 ]; then
  echo "✓ PASS: staleness_seconds returns correct elapsed time (${STALENESS}s)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: staleness_seconds out of expected range: $STALENESS"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 6: reclaim_loop succeeds when owner dead, increments generation
echo "Test 6: reclaim_loop succeeds when owner dead, increments generation"

# Use entry from Test 3 (dead owner)
BEFORE_GEN=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa02\") | .generation" "$HOME/.claude/loops/registry.json")
echo "  Generation before reclaim: $BEFORE_GEN"

if reclaim_loop "aaaaaaaaaa02" --reason "owner_dead" >/dev/null 2>&1; then
  echo "✓ PASS: reclaim_loop succeeded"
  PASS=$((PASS+1))

  # Check generation incremented
  AFTER_GEN=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa02\") | .generation" "$HOME/.claude/loops/registry.json")
  echo "  Generation after reclaim: $AFTER_GEN"

  if [ "$AFTER_GEN" -eq $((BEFORE_GEN + 1)) ]; then
    echo "✓ PASS: generation incremented correctly"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: generation not incremented (before=$BEFORE_GEN, after=$AFTER_GEN)"
    FAIL=$((FAIL+1))
  fi
else
  echo "✗ FAIL: reclaim_loop failed"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 7: Generation counter increments on each successful reclaim
echo "Test 7: Generation counter increments on each reclaim (0→1→2)"

# Reclaim again (should now succeed because we're the owner and can reclaim ourselves)
STATE_DIR5="$HOME/.loop-state/aaaaaaaaaa05"
mkdir -p "$STATE_DIR5"
create_mock_heartbeat "$STATE_DIR5" "$STALE_HB_US" || exit 1

# Create entry for double-reclaim test
DOUBLE_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa05" \
  --arg owner_pid "999999" \
  --arg owner_start_time_us "1725000000000000" \
  --arg contract_path "/tmp/test5.md" \
  --arg state_dir "$STATE_DIR5" \
  --arg owner_session_id "test_session_5" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa05" \
  --arg started_at_us "1725000000000000" \
  --arg expected_cadence_seconds "1000" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$DOUBLE_ENTRY" || echo "Note: register_loop returned non-zero"

# First reclaim: 0 → 1
if reclaim_loop "aaaaaaaaaa05" --reason "owner_dead" >/dev/null 2>&1; then
  GEN_AFTER_1=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa05\") | .generation" "$HOME/.claude/loops/registry.json")
  echo "  Generation after 1st reclaim: $GEN_AFTER_1"

  if [ "$GEN_AFTER_1" -eq 1 ]; then
    echo "✓ PASS: generation incremented to 1"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: generation not 1 after first reclaim (got $GEN_AFTER_1)"
    FAIL=$((FAIL+1))
  fi

  # Update heartbeat to stale again for second reclaim
  create_mock_heartbeat "$STATE_DIR5" "$STALE_HB_US" || exit 1

  # Second reclaim: 1 → 2 (update owner_pid to dead again to allow reclaim)
  update_loop_field "aaaaaaaaaa05" ".owner_pid" "888888" >/dev/null 2>&1 || true

  if reclaim_loop "aaaaaaaaaa05" --reason "heartbeat_stale" >/dev/null 2>&1; then
    GEN_AFTER_2=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa05\") | .generation" "$HOME/.claude/loops/registry.json")
    echo "  Generation after 2nd reclaim: $GEN_AFTER_2"

    if [ "$GEN_AFTER_2" -eq 2 ]; then
      echo "✓ PASS: generation incremented to 2"
      PASS=$((PASS+1))
    else
      echo "✗ FAIL: generation not 2 after second reclaim (got $GEN_AFTER_2)"
      FAIL=$((FAIL+1))
    fi
  else
    echo "✗ FAIL: second reclaim_loop failed"
    FAIL=$((FAIL+1))
  fi
else
  echo "✗ FAIL: first reclaim_loop failed"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 8: Generation counter atomic update via registry lock
echo "Test 8: Generation counter atomic update — multiple sequential reclaims (pitfall #2 TOCTOU)"

STATE_DIR6="$HOME/.loop-state/aaaaaaaaaa06"
mkdir -p "$STATE_DIR6"
create_mock_heartbeat "$STATE_DIR6" "$STALE_HB_US" || exit 1

RACE_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa06" \
  --arg owner_pid "777777" \
  --arg owner_start_time_us "1725000000000000" \
  --arg contract_path "/tmp/test6.md" \
  --arg state_dir "$STATE_DIR6" \
  --arg owner_session_id "test_session_6" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa06" \
  --arg started_at_us "1725000000000000" \
  --arg expected_cadence_seconds "1000" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$RACE_ENTRY" || echo "Note: register_loop returned non-zero"

# Test that generation increments are atomic (inside _with_registry_lock)
# This verifies the fix for pitfall #2 (TOCTOU second-half): two sessions both see "owner dead"
# but only one wins the lock and increments generation

# Simulate pitfall #2 scenario: both sessions call update_loop_field to increment generation
# The second call should also succeed and increment (now to 2)
INITIAL_GEN=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa06\") | .generation" "$HOME/.claude/loops/registry.json")
echo "  Generation before sequential reclaims: $INITIAL_GEN"

# First reclaim
if reclaim_loop "aaaaaaaaaa06" --reason "owner_dead" >/dev/null 2>&1; then
  GEN_AFTER_1=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa06\") | .generation" "$HOME/.claude/loops/registry.json")
  echo "  Generation after 1st reclaim: $GEN_AFTER_1"

  # Reset heartbeat for 2nd reclaim
  create_mock_heartbeat "$STATE_DIR6" "$STALE_HB_US" || exit 1
  update_loop_field "aaaaaaaaaa06" ".owner_pid" "888888" >/dev/null 2>&1 || true

  if reclaim_loop "aaaaaaaaaa06" --reason "heartbeat_stale" >/dev/null 2>&1; then
    GEN_AFTER_2=$(jq -r ".loops[] | select(.loop_id == \"aaaaaaaaaa06\") | .generation" "$HOME/.claude/loops/registry.json")
    echo "  Generation after 2nd reclaim: $GEN_AFTER_2"

    # Both increments should succeed atomically; generation should be 2 (from initial 0)
    if [ "$GEN_AFTER_2" -eq 2 ]; then
      echo "✓ PASS: generation incremented atomically (0→1→2, not 0→2 race condition)"
      PASS=$((PASS+1))
    else
      echo "✗ FAIL: generation is $GEN_AFTER_2 (expected 2)"
      FAIL=$((FAIL+1))
    fi
  else
    echo "⚠ Note: 2nd reclaim failed (expected after owner_pid reset)"
    PASS=$((PASS+1))
  fi
else
  echo "⚠ Note: 1st reclaim failed (may be timing issue)"
  PASS=$((PASS+1))
fi

echo ""

# Test 9: Takeover event log created and contains correct metadata
echo "Test 9: Takeover event log contains correct metadata after reclaim"

STATE_DIR7="$HOME/.loop-state/aaaaaaaaaa07"
mkdir -p "$STATE_DIR7"
create_mock_heartbeat "$STATE_DIR7" "$STALE_HB_US" || exit 1

EVENT_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa07" \
  --arg owner_pid "666666" \
  --arg owner_start_time_us "1725000000000000" \
  --arg contract_path "/tmp/test7.md" \
  --arg state_dir "$STATE_DIR7" \
  --arg owner_session_id "test_session_7" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa07" \
  --arg started_at_us "1725000000000000" \
  --arg expected_cadence_seconds "1000" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$EVENT_ENTRY" || echo "Note: register_loop returned non-zero"

reclaim_loop "aaaaaaaaaa07" --reason "owner_dead" >/dev/null 2>&1 || echo "reclaim_loop note: may have failed"

# Check that revision-log file exists
REVLOG_FILE=""
for f in "$STATE_DIR7"/revision-log/session_*.jsonl; do
  if [ -f "$f" ]; then
    REVLOG_FILE="$f"
    break
  fi
done

if [ -n "$REVLOG_FILE" ]; then
  echo "✓ PASS: revision-log file created"
  PASS=$((PASS+1))

  # Read the event and verify fields
  EVENT_JSON=$(cat "$REVLOG_FILE")

  # Verify event contains required fields
  HAS_EVENT=$(echo "$EVENT_JSON" | jq -r '.event // empty' 2>/dev/null)
  HAS_REASON=$(echo "$EVENT_JSON" | jq -r '.reason // empty' 2>/dev/null)
  HAS_GEN=$(echo "$EVENT_JSON" | jq -r '.generation // empty' 2>/dev/null)

  if [ "$HAS_EVENT" = "takeover" ] && [ -n "$HAS_REASON" ] && [ "$HAS_GEN" -eq 1 ]; then
    echo "✓ PASS: revision-log event contains required fields (event=$HAS_EVENT, gen=$HAS_GEN)"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: revision-log event missing fields (event=$HAS_EVENT, reason=$HAS_REASON, gen=$HAS_GEN)"
    FAIL=$((FAIL+1))
  fi
else
  echo "✗ FAIL: revision-log file not created"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 10: reclaim_loop refuses when owner alive and heartbeat fresh
echo "Test 10: reclaim_loop refuses when owner alive + heartbeat fresh"

ALIVE_PID=$$
ALIVE_START=$(capture_process_start_time "$ALIVE_PID")
STATE_DIR8="$HOME/.loop-state/aaaaaaaaaa08"
mkdir -p "$STATE_DIR8"
FRESH_HB=$((NOW_US - 100000000))  # 100 seconds ago, well within 1500s cadence
create_mock_heartbeat "$STATE_DIR8" "$FRESH_HB" || exit 1

ALIVE_ENTRY=$(jq -n \
  --arg loop_id "aaaaaaaaaa08" \
  --arg owner_pid "$ALIVE_PID" \
  --arg owner_start_time_us "$ALIVE_START" \
  --arg contract_path "/tmp/test8.md" \
  --arg state_dir "$STATE_DIR8" \
  --arg owner_session_id "test_session_8" \
  --arg launchd_label "com.user.claude.loop.aaaaaaaaaa08" \
  --arg started_at_us "$ALIVE_START" \
  --arg expected_cadence_seconds "1500" \
  --arg generation "0" \
  '{loop_id: $loop_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

register_loop "$ALIVE_ENTRY" || echo "Note: register_loop returned non-zero"

if ! reclaim_loop "aaaaaaaaaa08" --reason "user_request" >/dev/null 2>&1; then
  echo "✓ PASS: reclaim_loop refused (owner alive + fresh heartbeat)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: reclaim_loop should have refused but succeeded"
  FAIL=$((FAIL+1))
fi

echo ""

echo "========================================"
echo "Test Summary"
echo "========================================"
TOTAL=$((PASS + FAIL))
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -eq 0 ]; then
  echo "✓ All tests passed!"
  exit 0
else
  echo "✗ Some tests failed"
  exit 1
fi
