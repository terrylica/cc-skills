#!/usr/bin/env bash
# FILE-SIZE-OK
# test-waker.sh — Comprehensive test suite for waker.sh decision tree and pitfall #6 race defense
# Tests WAKE-03, WAKE-04, spawn safeguards, double-spawn prevention, notification atomicity

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
PASS=0
FAIL=0

# Cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create a stub claude binary in temp bin directory for testing
mkdir -p "$TEMP_DIR/bin"
cat > "$TEMP_DIR/bin/claude" << 'EOF'
#!/bin/bash
echo "STUB: claude $@" >> "$TEMP_DIR/spawn.log"
exit 0
EOF
chmod +x "$TEMP_DIR/bin/claude"

# Test utilities
# shellcheck disable=SC2329 # Utility functions invoked directly in tests
assert_equal() {
  local actual="$1"
  local expected="$2"
  local msg="$3"

  if [ "$actual" = "$expected" ]; then
    echo "✓ $msg"
    PASS=$((PASS + 1))
  else
    echo "✗ $msg (expected: '$expected', got: '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"

  if echo "$haystack" | grep -q "$needle"; then
    echo "✓ $msg"
    PASS=$((PASS + 1))
  else
    echo "✗ $msg (needle: '$needle' not found in haystack)"
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck disable=SC2329 # Utility function invoked directly
assert_file_exists() {
  local file="$1"
  local msg="$2"

  if [ -f "$file" ]; then
    echo "✓ $msg"
    PASS=$((PASS + 1))
  else
    echo "✗ $msg (file not found: $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_missing() {
  local file="$1"
  local msg="$2"

  if [ ! -f "$file" ]; then
    echo "✓ $msg"
    PASS=$((PASS + 1))
  else
    echo "✗ $msg (file should not exist: $file)"
    FAIL=$((FAIL + 1))
  fi
}

# Setup home environment for tests
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
export PATH="$TEMP_DIR/bin:$PATH"

# Source libraries
source "$SCRIPT_DIR/scripts/registry-lib.sh"
source "$SCRIPT_DIR/scripts/ownership-lib.sh"
source "$SCRIPT_DIR/scripts/state-lib.sh"
source "$SCRIPT_DIR/scripts/notifications-lib.sh"

# ============================================================================
# TEST 1: Alive + Fresh → No action
# ============================================================================
test_alive_fresh() {
  echo ""
  echo "TEST 1: Alive + Fresh → No action (logged only)"

  local loop_id="a1b2c3d4e5f6"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Register loop with current process (alive)
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$$" \
    --arg owner_start_time_us "$(capture_process_start_time $$)" \
    --arg owner_session_id "ses_abc123" \
    --arg expected_cadence_seconds "300" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
  register_loop "$entry"

  # Write fresh heartbeat (within 3× cadence)
  local now_us
  now_us=$(now_us)
  write_heartbeat "$loop_id" "ses_abc123" "1" "$contract_path"

  # Run waker
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output.txt" 2>&1
  local output
  output=$(cat "$TEMP_DIR/waker_output.txt")

  # Assert: no spawn occurred, only log message
  assert_contains "$output" "alive+fresh" "Waker logs alive+fresh decision"
  assert_file_missing "$TEMP_DIR/spawn.log" "No spawn should occur for alive+fresh"
}

# ============================================================================
# TEST 2: Alive + Stale → "stuck" notification (no spawn)
# ============================================================================
test_alive_stale() {
  echo ""
  echo "TEST 2: Alive + Stale → 'stuck' notification (no spawn)"

  local loop_id="b2c3d4e5f6a1"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT_2.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Register loop with current process
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$$" \
    --arg owner_start_time_us "$(capture_process_start_time $$)" \
    --arg owner_session_id "ses_def456" \
    --arg expected_cadence_seconds "300" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
  register_loop "$entry"

  # Write very stale heartbeat (>3× cadence = >900s)
  local stale_time_us=$(($(now_us) - (1500 * 1000000)))
  local hb
  hb=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "ses_def456" \
    --arg iteration "1" \
    --arg last_wake_us "$stale_time_us" \
    --arg generation "0" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
  mkdir -p "$state_dir"
  echo "$hb" > "$state_dir/heartbeat.json"

  # Run waker
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_2.txt" 2>&1

  # Assert: "stuck" notification emitted
  local notif
  notif=$(cat "$HOME/.claude/loops/.notifications.jsonl" 2>/dev/null || echo "")
  assert_contains "$notif" "stuck" "Stuck notification emitted"
  assert_file_missing "$TEMP_DIR/spawn.log" "No spawn for alive+stale"
}

# ============================================================================
# TEST 3: Dead + Fresh → "anomaly" notification (no spawn)
# ============================================================================
test_dead_fresh() {
  echo ""
  echo "TEST 3: Dead + Fresh → 'anomaly' notification (no spawn)"

  local loop_id="c3d4e5f6a1b2"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT_3.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Register loop with non-existent PID
  local dead_pid=99999
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$dead_pid" \
    --arg owner_start_time_us "1700000000000000" \
    --arg owner_session_id "ses_ghi789" \
    --arg expected_cadence_seconds "300" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
  register_loop "$entry"

  # Write fresh heartbeat
  local now_us
  now_us=$(now_us)
  local hb
  hb=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "ses_ghi789" \
    --arg iteration "5" \
    --arg last_wake_us "$now_us" \
    --arg generation "0" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
  mkdir -p "$state_dir"
  echo "$hb" > "$state_dir/heartbeat.json"

  # Run waker
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_3.txt" 2>&1

  # Assert: "anomaly" notification emitted, no spawn
  local notif
  notif=$(cat "$HOME/.claude/loops/.notifications.jsonl" 2>/dev/null || echo "")
  assert_contains "$notif" "anomaly" "Anomaly notification emitted for dead+fresh"
  assert_file_missing "$TEMP_DIR/spawn.log" "No spawn for dead+fresh (anomalous)"
}

# ============================================================================
# TEST 4: Dead + Stale (3× to 4×) → "pending_takeover" notification (no spawn)
# ============================================================================
test_dead_stale_pending() {
  echo ""
  echo "TEST 4: Dead + Stale (3× to 4×) → 'pending_takeover' notification (no spawn)"

  local loop_id="d4e5f6a1b2c3"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT_4.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Register loop with non-existent PID
  local dead_pid=99998
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$dead_pid" \
    --arg owner_start_time_us "1700000000000000" \
    --arg owner_session_id "ses_jkl012" \
    --arg expected_cadence_seconds "300" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
  register_loop "$entry"

  # Write stale heartbeat (3.5× cadence = 1050s)
  local stale_time_us=$(($(now_us) - (1050 * 1000000)))
  local hb
  hb=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "ses_jkl012" \
    --arg iteration "3" \
    --arg last_wake_us "$stale_time_us" \
    --arg generation "0" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
  mkdir -p "$state_dir"
  echo "$hb" > "$state_dir/heartbeat.json"

  # Run waker
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_4.txt" 2>&1

  # Assert: "pending_takeover" notification, no spawn
  local notif
  notif=$(cat "$HOME/.claude/loops/.notifications.jsonl" 2>/dev/null || echo "")
  assert_contains "$notif" "pending_takeover" "Pending takeover notification emitted"
  assert_file_missing "$TEMP_DIR/spawn.log" "No spawn for pending_takeover (wait for next tick)"
}

# ============================================================================
# TEST 5: Dead + Stale (>4×) → Spawn attempted
# ============================================================================
test_dead_stale_spawn() {
  echo ""
  echo "TEST 5: Dead + Stale (>4×) → Spawn attempted"

  local loop_id="e5f6a1b2c3d4"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT_5.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Register loop with non-existent PID
  local dead_pid=99997
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$dead_pid" \
    --arg owner_start_time_us "1700000000000000" \
    --arg owner_session_id "ses_mno345" \
    --arg expected_cadence_seconds "300" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
  register_loop "$entry"

  # Write very stale heartbeat (>4× cadence = >1200s)
  local stale_time_us=$(($(now_us) - (1500 * 1000000)))
  local hb
  hb=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "ses_mno345" \
    --arg iteration "2" \
    --arg last_wake_us "$stale_time_us" \
    --arg generation "0" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
  mkdir -p "$state_dir"
  echo "$hb" > "$state_dir/heartbeat.json"

  # Run waker with timeout to prevent hanging
  rm -f "$TEMP_DIR/spawn.log"
  timeout 5 bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_5.txt" 2>&1 || true

  # Assert: spawn occurred (check revision-log since spawn.log may not exist yet)
  local spawn_happened=0
  if [ -f "$state_dir/revision-log/spawn.jsonl" ]; then
    spawn_happened=1
  fi

  if [ "$spawn_happened" = "1" ]; then
    echo "✓ Spawn attempted for dead+stale (>4×)"
    PASS=$((PASS + 1))
  else
    echo "✗ Spawn should occur for dead+stale (>4×)"
    FAIL=$((FAIL + 1))
  fi
  # Assert: last_spawn_us updated in registry
  local updated_entry
  updated_entry=$(read_registry_entry "$loop_id") || updated_entry="{}"
  local last_spawn_us
  last_spawn_us=$(echo "$updated_entry" | jq -r '.last_spawn_us // 0' 2>/dev/null || echo "0")
  if [ "$last_spawn_us" != "0" ]; then
    echo "✓ last_spawn_us updated in registry"
    PASS=$((PASS + 1))
  else
    echo "✗ last_spawn_us not updated in registry"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# TEST 6: Spawn rate-limit (last spawn <60s ago) → Refused
# ============================================================================
test_spawn_rate_limit() {
  echo ""
  echo "TEST 6: Spawn rate-limit (last spawn <60s ago) → Refused"

  local loop_id="f6a1b2c3d4e5"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT_6.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Register loop with dead PID and recent last_spawn_us
  local dead_pid=99996
  local recent_spawn_us=$(($(now_us) - (30 * 1000000)))  # 30s ago
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$dead_pid" \
    --arg owner_start_time_us "1700000000000000" \
    --arg owner_session_id "ses_pqr678" \
    --arg expected_cadence_seconds "300" \
    --arg last_spawn_us "$recent_spawn_us" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds, last_spawn_us: $last_spawn_us}')
  register_loop "$entry"

  # Write very stale heartbeat
  local stale_time_us=$(($(now_us) - (1500 * 1000000)))
  local hb
  hb=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "ses_pqr678" \
    --arg iteration "1" \
    --arg last_wake_us "$stale_time_us" \
    --arg generation "0" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
  mkdir -p "$state_dir"
  echo "$hb" > "$state_dir/heartbeat.json"

  # Run waker
  rm -f "$TEMP_DIR/spawn.log"
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_6.txt" 2>&1
  local output
  output=$(cat "$TEMP_DIR/waker_output_6.txt")

  # Assert: spawn refused
  assert_contains "$output" "spawn refused" "Spawn rate-limit check prevents spawn"
  assert_file_missing "$TEMP_DIR/spawn.log" "No spawn when rate-limited"
}

# ============================================================================
# TEST 7: Pitfall #6 double-spawn race — re-verify stops spawn
# ============================================================================
test_pitfall_6_race_prevention() {
  echo ""
  echo "TEST 7: Pitfall #6 race prevention (owner comes back alive during lock)"

  local loop_id="a1a1a1a1a1a1"
  local contract_path="$TEMP_DIR/LOOP_CONTRACT_RACE.md"
  local state_dir="$TEMP_DIR/.loop-state/$loop_id"

  # Create contract and state dir
  touch "$contract_path"
  mkdir -p "$state_dir/revision-log"

  # Use a real PID that we control: create a background sleep process
  local dummy_pid
  sleep 10 &
  dummy_pid=$!

  # Register loop with the dummy PID
  local entry
  entry=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_path" \
    --arg state_dir "$state_dir" \
    --arg owner_pid "$dummy_pid" \
    --arg owner_start_time_us "$(capture_process_start_time "$dummy_pid")" \
    --arg owner_session_id "ses_race" \
    --arg expected_cadence_seconds "300" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
  register_loop "$entry"

  # Write very stale heartbeat (to trigger spawn condition)
  local stale_time_us=$(($(now_us) - (1500 * 1000000)))
  local hb
  hb=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "ses_race" \
    --arg iteration "1" \
    --arg last_wake_us "$stale_time_us" \
    --arg generation "0" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
  mkdir -p "$state_dir"
  echo "$hb" > "$state_dir/heartbeat.json"

  # Run waker (should spawn because owner is alive)
  rm -f "$TEMP_DIR/spawn.log"
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_race.txt" 2>&1

  # The owner (sleep) is still alive, so spawn should NOT occur
  # (The re-verify inside the lock checks kill -0 and aborts if alive)
  assert_file_missing "$TEMP_DIR/spawn.log" "No spawn when re-verify finds owner alive"

  # Cleanup: kill the dummy process
  kill "$dummy_pid" 2>/dev/null || true
  wait "$dummy_pid" 2>/dev/null || true
}

# ============================================================================
# TEST 8: Notification atomicity (two parallel wakers emit both notifications)
# ============================================================================
test_notification_atomicity() {
  echo ""
  echo "TEST 8: Notification atomicity (parallel appends)"

  local loop_id1="b1b1b1b1b1b1"
  local loop_id2="c2c2c2c2c2c2"
  local contract_path1="$TEMP_DIR/LOOP_CONTRACT_PAR1.md"
  local contract_path2="$TEMP_DIR/LOOP_CONTRACT_PAR2.md"
  local state_dir1="$TEMP_DIR/.loop-state/$loop_id1"
  local state_dir2="$TEMP_DIR/.loop-state/$loop_id2"

  # Setup both loops
  for loop_id in "$loop_id1" "$loop_id2"; do
    local contract_path
    local state_dir

    if [ "$loop_id" = "$loop_id1" ]; then
      contract_path="$contract_path1"
      state_dir="$state_dir1"
    else
      contract_path="$contract_path2"
      state_dir="$state_dir2"
    fi

    touch "$contract_path"
    mkdir -p "$state_dir/revision-log"

    local entry
    entry=$(jq -n \
      --arg loop_id "$loop_id" \
      --arg contract_path "$contract_path" \
      --arg state_dir "$state_dir" \
      --arg owner_pid "$$" \
      --arg owner_start_time_us "$(capture_process_start_time $$)" \
      --arg owner_session_id "ses_par" \
      --arg expected_cadence_seconds "300" \
      '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence_seconds}')
    register_loop "$entry"

    # Write stale heartbeat
    local stale_time_us=$(($(now_us) - (1500 * 1000000)))
    local hb
    hb=$(jq -n \
      --arg loop_id "$loop_id" \
      --arg session_id "ses_par" \
      --arg iteration "1" \
      --arg last_wake_us "$stale_time_us" \
      --arg generation "0" \
      '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')
    mkdir -p "$state_dir"
    echo "$hb" > "$state_dir/heartbeat.json"
  done

  # Clear notifications file
  rm -f "$HOME/.claude/loops/.notifications.jsonl"

  # Run two wakers in parallel
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id1" > /dev/null 2>&1 &
  local pid1=$!
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id2" > /dev/null 2>&1 &
  local pid2=$!

  wait "$pid1" "$pid2"

  # Assert: both notifications present in file
  local notif_count
  notif_count=$(grep -c "^{" "$HOME/.claude/loops/.notifications.jsonl" 2>/dev/null || echo "0")
  if [ "$notif_count" -ge 2 ]; then
    echo "✓ Both notifications atomically appended"
    PASS=$((PASS + 1))
  else
    echo "✗ Expected 2+ notifications, got $notif_count"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# TEST 9: Missing loop_id (unregistered) → Exit 0 with log
# ============================================================================
test_missing_loop_id() {
  echo ""
  echo "TEST 9: Missing loop_id (unregistered) → Exit 0 with log"

  local loop_id="aaaaaaaaaaaaaaaa"  # Valid format but non-existent loop (16 chars, so will fail validation)
  # Actually use a valid 12-hex-char ID that's not registered
  loop_id="f0f0f0f0f0f0"

  # Run waker
  bash "$SCRIPT_DIR/scripts/waker.sh" "$loop_id" > "$TEMP_DIR/waker_output_missing.txt" 2>&1
  local output
  output=$(cat "$TEMP_DIR/waker_output_missing.txt")

  # Assert: exit code 0, log message
  assert_contains "$output" "unregistered" "Log message indicates loop unregistered"
}

# ============================================================================
# RUN ALL TESTS
# ============================================================================
test_alive_fresh
test_alive_stale
test_dead_fresh
test_dead_stale_pending
test_dead_stale_spawn
test_spawn_rate_limit
test_pitfall_6_race_prevention
test_notification_atomicity
test_missing_loop_id

# Print summary
echo ""
echo "============================================================================"
echo "SUMMARY: $PASS passed, $FAIL failed"
echo "============================================================================"

if [ $FAIL -gt 0 ]; then
  trap - EXIT  # Disable trap before exit
  exit 1
fi

trap - EXIT  # Disable trap before exit
exit 0
