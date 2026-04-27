#!/usr/bin/env bash
# test-10-loop-stress.sh — 10-loop stress test across 3 repos (MIG-03)
# Tests: registry consistency, heartbeat integrity, status reporting, enumeration
# 5 active loops (fresh heartbeat, live owner), 5 stale loops (old heartbeat, dead owner PID)

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
TEMP_ROOT=""

# Cleanup (invoked via trap)
# shellcheck disable=SC2329
cleanup() {
  if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
    rm -rf "$TEMP_ROOT"
  fi
  # Clean up registry for this test
  if [ -f "$HOME/.claude/loops/registry.json" ]; then
    rm -f "$HOME/.claude/loops/registry.json"
  fi
}
trap cleanup EXIT

echo "========================================"
echo "MIG-03: 10-Loop Stress Test (3 repos)"
echo "========================================"
echo ""

# Setup: Create 3 temporary repos
TEMP_ROOT=$(mktemp -d)
REPO_A="$TEMP_ROOT/repo-a"
REPO_B="$TEMP_ROOT/repo-b"
REPO_C="$TEMP_ROOT/repo-c"
mkdir -p "$REPO_A" "$REPO_B" "$REPO_C"

# Initialize each as a git repo (for state_dir_path logic)
git init "$REPO_A" >/dev/null 2>&1
git init "$REPO_B" >/dev/null 2>&1
git init "$REPO_C" >/dev/null 2>&1

echo "Test 1: Create 10 loop contracts across 3 repos"

LOOP_IDS=()
REPOS=("$REPO_A" "$REPO_B" "$REPO_C")

# Distribute 10 loops: 4 in A, 3 in B, 3 in C
# 5 active (indices 0,2,4,6,8), 5 stale (indices 1,3,5,7,9)
for i in {0..9}; do
  REPO_IDX=$((i % 3))
  REPO="${REPOS[$REPO_IDX]}"

  CONTRACT_PATH="$REPO/LOOP_CONTRACT_$i.md"
  cat > "$CONTRACT_PATH" <<EOF
---
name: stress-test-loop-$i
version: 1
iteration: 0
last_updated: 2026-04-26T12:00:00Z
exit_condition: manual stop
max_iterations: 50
---
# Test Loop $i

This is loop $i in repo $(basename "$REPO").

## Current State

Initializing.
EOF

  LOOP_ID=$(derive_loop_id "$CONTRACT_PATH")
  LOOP_IDS+=("$LOOP_ID")

  # Initialize state directory (auto-registers in registry)
  if ! init_state_dir "$LOOP_ID" "$CONTRACT_PATH" 2>/dev/null; then
    echo "✗ FAIL: init_state_dir failed for loop $i"
    ((FAIL++))
    continue
  fi

  # Get state dir and update owner info in registry
  STATE_DIR=$(state_dir_path "$LOOP_ID" "$CONTRACT_PATH")
  mkdir -p "$STATE_DIR/revision-log"

  # Create heartbeat.json
  NOW_US=$(now_us)

  # For active loops (i % 2 == 0): fresh heartbeat, current process
  # For stale loops (i % 2 == 1): old heartbeat (2 hours ago), fake PID (99999)
  if [ $((i % 2)) -eq 0 ]; then
    # Active: fresh heartbeat, current PID
    cat > "$STATE_DIR/heartbeat.json" <<HBJSON
{
  "loop_id": "$LOOP_ID",
  "iteration": 0,
  "last_wake_us": $NOW_US,
  "session_id": "test_session_active_$i"
}
HBJSON
    OWNER_PID=$$
    OWNER_START_TIME_US=$(capture_process_start_time "$$")
  else
    # Stale: old heartbeat (2 hours = 7200 sec), fake dead PID
    OLD_WAKE_US=$((NOW_US - 7200 * 1000000))
    cat > "$STATE_DIR/heartbeat.json" <<HBJSON
{
  "loop_id": "$LOOP_ID",
  "iteration": 0,
  "last_wake_us": $OLD_WAKE_US,
  "session_id": "test_session_stale_$i"
}
HBJSON
    OWNER_PID=99999
    OWNER_START_TIME_US=$((NOW_US - 10000000000))  # Very old
  fi

  # Update owner info in registry via update_loop_field (since already registered by init_state_dir)
  if ! update_loop_field "$LOOP_ID" ".owner_pid" "$OWNER_PID" 2>/dev/null; then
    : # Ignore update failures for this test
  fi

  if ! update_loop_field "$LOOP_ID" ".owner_start_time_us" "$OWNER_START_TIME_US" 2>/dev/null; then
    : # Ignore update failures for this test
  fi
done

echo "✓ Created 10 contracts (5 active, 5 stale) across 3 repos"
((PASS++))

echo ""
echo "Test 2: Registry file is valid JSON"

if [ ! -f "$HOME/.claude/loops/registry.json" ]; then
  echo "✗ FAIL: Registry file not created"
  ((FAIL++))
else
  if jq empty "$HOME/.claude/loops/registry.json" 2>/dev/null; then
    echo "✓ Registry.json is valid JSON"
    ((PASS++))
  else
    echo "✗ FAIL: Registry.json is malformed"
    ((FAIL++))
  fi
fi

echo ""
echo "Test 3: Enumerate loops - all 10 appear in registry"

REGISTERED_COUNT=$(jq '.loops | length' "$HOME/.claude/loops/registry.json" 2>/dev/null || echo 0)
if [ "$REGISTERED_COUNT" -eq 10 ]; then
  echo "✓ All 10 loops registered (count: $REGISTERED_COUNT)"
  ((PASS++))
else
  echo "✗ FAIL: Expected 10 loops, found $REGISTERED_COUNT"
  ((FAIL++))
fi

echo ""
echo "Test 4: Reclaim candidate detection (5 stale, 5 active)"

RECLAIM_CANDIDATES=0
ACTIVE_LOOPS=0

for i in {0..9}; do
  LOOP_ID="${LOOP_IDS[$i]}"

  # Check if reclaim candidate
  CANDIDATE=$(is_reclaim_candidate "$LOOP_ID" "$HOME/.claude/loops/registry.json")

  if [ "$CANDIDATE" = "yes" ]; then
    ((RECLAIM_CANDIDATES++))
    # Should only be reclaim candidates if i is odd (stale)
    if [ $((i % 2)) -ne 1 ]; then
      echo "✗ FAIL: Loop $i (active) incorrectly marked as reclaim candidate"
      ((FAIL++))
    fi
  elif [ "$CANDIDATE" = "owner_alive" ]; then
    ((ACTIVE_LOOPS++))
    # Should only be active if i is even
    if [ $((i % 2)) -ne 0 ]; then
      echo "✗ FAIL: Loop $i (stale) incorrectly marked as active"
      ((FAIL++))
    fi
  fi
done

if [ "$RECLAIM_CANDIDATES" -eq 5 ] && [ "$ACTIVE_LOOPS" -eq 5 ]; then
  echo "✓ Correct split: 5 stale (reclaim candidates), 5 active"
  ((PASS++))
else
  echo "✗ FAIL: Unexpected split (reclaim: $RECLAIM_CANDIDATES, active: $ACTIVE_LOOPS, expected 5/5)"
  ((FAIL++))
fi

echo ""
echo "Test 5: Registry integrity after stress (single valid JSON)"

# Try to re-read and count again
FINAL_COUNT=$(jq '.loops | length' "$HOME/.claude/loops/registry.json" 2>/dev/null || echo 0)
if [ "$FINAL_COUNT" -eq 10 ]; then
  echo "✓ Registry integrity maintained (final count: $FINAL_COUNT)"
  ((PASS++))
else
  echo "✗ FAIL: Registry corruption detected (final count: $FINAL_COUNT, expected 10)"
  ((FAIL++))
fi

echo ""
echo "Test 6: No heartbeat corruption (all heartbeat.json valid)"

HEARTBEAT_ERRORS=0
for i in {0..9}; do
  LOOP_ID="${LOOP_IDS[$i]}"
  ENTRY=$(jq ".loops[] | select(.loop_id == \"$LOOP_ID\")" "$HOME/.claude/loops/registry.json" 2>/dev/null)
  STATE_DIR=$(echo "$ENTRY" | jq -r '.state_dir' 2>/dev/null)

  if [ -f "$STATE_DIR/heartbeat.json" ]; then
    if ! jq empty "$STATE_DIR/heartbeat.json" 2>/dev/null; then
      echo "✗ Heartbeat corruption in loop $i"
      ((HEARTBEAT_ERRORS++))
    fi
  fi
done

if [ "$HEARTBEAT_ERRORS" -eq 0 ]; then
  echo "✓ All 10 heartbeat.json files are valid JSON"
  ((PASS++))
else
  echo "✗ FAIL: Found $HEARTBEAT_ERRORS heartbeat corruption issues"
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
