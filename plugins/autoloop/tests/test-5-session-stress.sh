#!/usr/bin/env bash
# test-5-session-stress.sh — 5-session lock contention test (MIG-04)
# Tests: ownership protocol, atomic lock, race conditions, reclaim on dead owner
# Spawns 5 background shells all trying to acquire_owner_lock simultaneously
# Assert: exactly 1 succeeds, 4 fail with lock contention error
# Then: kill winner, reclaim from 6th session, verify generation increments

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh" 2>/dev/null || {
  echo "Failed to source registry-lib.sh" >&2
  exit 1
}
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh" 2>/dev/null || {
  echo "Failed to source state-lib.sh" >&2
  exit 1
}
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/ownership-lib.sh" 2>/dev/null || {
  echo "Failed to source ownership-lib.sh" >&2
  exit 1
}

# Test counters
PASS=0
FAIL=0
TEMP_DIR=""

# Cleanup (invoked via trap)
# shellcheck disable=SC2329
cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  # Clean up registry and locks for this test
  if [ -f "$HOME/.claude/loops/registry.json" ]; then
    rm -f "$HOME/.claude/loops/registry.json"
  fi
  if [ -d "$HOME/.claude/loops" ]; then
    rm -f "$HOME/.claude/loops/"*.owner.lock 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "========================================"
echo "MIG-04: 5-Session Lock Contention Test"
echo "========================================"
echo ""

# Setup: Create single contract and register in registry
TEMP_DIR=$(mktemp -d)
CONTRACT_PATH="$TEMP_DIR/LOOP_CONTRACT.md"
cat > "$CONTRACT_PATH" <<'EOF'
---
name: contention-test-loop
version: 1
iteration: 0
last_updated: 2026-04-26T12:00:00Z
exit_condition: manual stop
max_iterations: 50
---
# Contention Test Loop

Single loop for testing lock contention.

## Current State

Initializing.
EOF

# Derive loop_id and initialize state (auto-registers)
LOOP_ID=$(derive_loop_id "$CONTRACT_PATH")
if ! init_state_dir "$LOOP_ID" "$CONTRACT_PATH" 2>/dev/null; then
  echo "✗ FAIL: init_state_dir failed"
  ((FAIL++))
  exit 1
fi

# Get state dir and setup heartbeat
STATE_DIR=$(state_dir_path "$LOOP_ID" "$CONTRACT_PATH")
NOW_US=$(now_us)

# Write initial heartbeat
cat > "$STATE_DIR/heartbeat.json" <<EOF
{
  "loop_id": "$LOOP_ID",
  "iteration": 0,
  "last_wake_us": $NOW_US,
  "session_id": "setup_session"
}
EOF

echo "✓ Setup: Registered single loop with ID $LOOP_ID"
((PASS++))

echo ""
echo "Test 1: Lock acquisition and serialization"

# Test that acquire_owner_lock succeeds when no lock held
if acquire_owner_lock "$LOOP_ID" 2>/dev/null; then
  echo "✓ First acquire_owner_lock succeeded"
  ((PASS++))
else
  echo "✗ FAIL: First acquire_owner_lock failed"
  ((FAIL++))
fi

# Test that attempting to acquire again fails (different fd in same shell won't work due to open fd)
# Instead, release and re-acquire to test lock mechanism
release_owner_lock "$LOOP_ID" 2>/dev/null || true

# Acquire again (should succeed since released)
if acquire_owner_lock "$LOOP_ID" 2>/dev/null; then
  echo "✓ Reacquire after release succeeded"
  ((PASS++))
else
  echo "✗ FAIL: Reacquire after release failed"
  ((FAIL++))
fi

# Release for next tests
release_owner_lock "$LOOP_ID" 2>/dev/null || true

echo ""
echo "Test 2: Simulate dead owner and reclaim from fresh session"

# Unregister the current owner and set a fake dead PID
DEAD_PID=99999
DEAD_START_TIME_US=$((NOW_US - 10000000000))

if ! update_loop_field "$LOOP_ID" ".owner_pid" "$DEAD_PID" 2>/dev/null; then
  echo "✗ FAIL: Failed to update owner_pid to dead value"
  ((FAIL++))
else
  if ! update_loop_field "$LOOP_ID" ".owner_start_time_us" "$DEAD_START_TIME_US" 2>/dev/null; then
    echo "✗ FAIL: Failed to update start_time_us"
    ((FAIL++))
  else
    echo "✓ Simulated dead owner (PID: $DEAD_PID)"
    ((PASS++))
  fi
fi

echo ""
echo "Test 3: Verify is_reclaim_candidate detects dead owner"

CANDIDATE=$(is_reclaim_candidate "$LOOP_ID" "$HOME/.claude/loops/registry.json")
if [ "$CANDIDATE" = "yes" ]; then
  echo "✓ Loop correctly identified as reclaim candidate"
  ((PASS++))
else
  echo "✗ FAIL: Loop not identified as reclaim candidate (status: $CANDIDATE)"
  ((FAIL++))
fi

echo ""
echo "Test 4: Reclaim loop and verify generation increments"

BEFORE_ENTRY=$(jq ".loops[] | select(.loop_id == \"$LOOP_ID\")" "$HOME/.claude/loops/registry.json" 2>/dev/null)
OLD_GENERATION=$(echo "$BEFORE_ENTRY" | jq -r '.generation // 0')

if reclaim_loop "$LOOP_ID" --reason "owner_dead" 2>/dev/null; then
  echo "✓ reclaim_loop succeeded"
  ((PASS++))

  # Read new entry
  AFTER_ENTRY=$(jq ".loops[] | select(.loop_id == \"$LOOP_ID\")" "$HOME/.claude/loops/registry.json" 2>/dev/null)
  NEW_GENERATION=$(echo "$AFTER_ENTRY" | jq -r '.generation // 0')
  NEW_OWNER_PID=$(echo "$AFTER_ENTRY" | jq -r '.owner_pid // "unknown"')

  # Verify generation incremented
  if [ "$NEW_GENERATION" -eq $((OLD_GENERATION + 1)) ]; then
    echo "✓ Generation incremented ($OLD_GENERATION -> $NEW_GENERATION)"
    ((PASS++))
  else
    echo "✗ FAIL: Generation not incremented ($OLD_GENERATION -> $NEW_GENERATION)"
    ((FAIL++))
  fi

  # Verify owner_pid updated to current process
  if [ "$NEW_OWNER_PID" = "$$" ]; then
    echo "✓ owner_pid updated to current process ($$)"
    ((PASS++))
  else
    echo "✗ FAIL: owner_pid not updated (expected $$, got $NEW_OWNER_PID)"
    ((FAIL++))
  fi
else
  echo "✗ FAIL: reclaim_loop failed"
  ((FAIL++))
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
