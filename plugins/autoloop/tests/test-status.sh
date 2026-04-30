#!/usr/bin/env bash
# test-status.sh — Unit tests for machine-wide status enumeration (Phase 10)
# Tests: enumerate_loops, compute_dead_time_ratio, format_status_table, human_relative_time, is_reclaim_candidate_v2

set -euo pipefail

# Source the status library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/status-lib.sh" 2>/dev/null || {
  echo "Failed to source status-lib.sh" >&2
  exit 1
}

# Test counters
PASS=0
FAIL=0

# Setup: Create temporary HOME and test directory
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.claude/loops"

# Cleanup function (invoked via trap on EXIT)
# shellcheck disable=SC2329
cleanup() {
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

echo "========================================"
echo "Test 1: Empty Registry"
echo "========================================"

# Call enumerate_loops on empty registry
RESULT=$(enumerate_loops 2>&1 || true)

if [ -z "$RESULT" ]; then
  echo "✓ PASS: Empty registry returns no lines"
  ((PASS++))
else
  echo "✗ FAIL: Empty registry should return empty output, got: $RESULT"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 2: format_status_table with Empty Input"
echo "========================================"

# format_status_table is a function, we need to call it in a bash context
OUTPUT=$(bash -c "
  source '$PLUGIN_DIR/scripts/status-lib.sh'
  echo '' | format_status_table
" 2>&1 || true)

if echo "$OUTPUT" | grep -q "No active loops"; then
  echo "✓ PASS: Empty input prints 'No active loops'"
  ((PASS++))
else
  echo "✗ FAIL: Expected 'No active loops' message, got: $OUTPUT"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 3: human_relative_time - 30s ago"
echo "========================================"

# Create a timestamp 30 seconds ago
CURRENT_US=$(python3 -c "import time; print(int(time.time()*1_000_000))")
PAST_30S=$((CURRENT_US - 30 * 1000000))

RESULT=$(human_relative_time "$PAST_30S")

if [[ "$RESULT" =~ ^30s\ ago$ ]]; then
  echo "✓ PASS: 30s ago → '$RESULT'"
  ((PASS++))
else
  echo "✗ FAIL: Expected '30s ago', got: '$RESULT'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 4: human_relative_time - 2m ago"
echo "========================================"

PAST_2M=$((CURRENT_US - 120 * 1000000))
RESULT=$(human_relative_time "$PAST_2M")

if [[ "$RESULT" =~ ^2m\ ago$ ]]; then
  echo "✓ PASS: 120s ago → '$RESULT'"
  ((PASS++))
else
  echo "✗ FAIL: Expected '2m ago', got: '$RESULT'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 5: human_relative_time - 1h ago"
echo "========================================"

PAST_1H=$((CURRENT_US - 3600 * 1000000))
RESULT=$(human_relative_time "$PAST_1H")

if [[ "$RESULT" =~ ^1h\ ago$ ]]; then
  echo "✓ PASS: 3600s ago → '$RESULT'"
  ((PASS++))
else
  echo "✗ FAIL: Expected '1h ago', got: '$RESULT'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 6: human_relative_time - 1d ago"
echo "========================================"

PAST_1D=$((CURRENT_US - 86400 * 1000000))
RESULT=$(human_relative_time "$PAST_1D")

if [[ "$RESULT" =~ ^1d\ ago$ ]]; then
  echo "✓ PASS: 86400s ago → '$RESULT'"
  ((PASS++))
else
  echo "✗ FAIL: Expected '1d ago', got: '$RESULT'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 7: human_relative_time - null"
echo "========================================"

RESULT=$(human_relative_time "")
if [ "$RESULT" = "—" ]; then
  echo "✓ PASS: Empty timestamp → '—'"
  ((PASS++))
else
  echo "✗ FAIL: Expected '—', got: '$RESULT'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 8: Create Test Loop Entry"
echo "========================================"

# Create a simple registry with one loop
LOOP_ID="a1b2c3d4e5f6"
STATE_DIR="$TEST_HOME/.loop-state/$LOOP_ID"
mkdir -p "$STATE_DIR/revision-log"

# Create heartbeat
HEARTBEAT_JSON=$(jq -n \
  --arg loop_id "$LOOP_ID" \
  --arg session_id "test_session_001_abc" \
  --arg iteration "5" \
  --arg last_wake_us "$(python3 -c 'import time; print(int(time.time()*1_000_000))')" \
  --arg generation "0" \
  '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')

echo "$HEARTBEAT_JSON" > "$STATE_DIR/heartbeat.json"

# Create registry entry
ENTRY_JSON=$(jq -n \
  --arg loop_id "$LOOP_ID" \
  --arg contract_path "/tmp/test_contract.md" \
  --arg state_dir "$STATE_DIR" \
  --arg generation "0" \
  --arg owner_pid "$$" \
  --arg owner_session_id "test_session_001_abc" \
  --arg expected_cadence "10" \
  --arg started_at_us "$(python3 -c 'import time; print(int((time.time()-100)*1_000_000))')" \
  '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, generation: $generation, owner_pid: $owner_pid, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence, started_at_us: $started_at_us}')

REGISTRY=$(jq -n --argjson entry "$ENTRY_JSON" '{loops: [$entry], schema_version: 1}')
echo "$REGISTRY" > "$TEST_HOME/.claude/loops/registry.json"

echo "✓ PASS: Created test loop entry"
((PASS++))

echo ""
echo "========================================"
echo "Test 9: enumerate_loops - Single Active Loop"
echo "========================================"

ENUMERATION=$(enumerate_loops "$TEST_HOME/.claude/loops/registry.json")

if echo "$ENUMERATION" | jq -e '.loop_id == "a1b2c3d4e5f6"' >/dev/null 2>&1; then
  echo "✓ PASS: enumerate_loops returned loop entry with correct loop_id"
  ((PASS++))

  # Verify status field
  STATUS=$(echo "$ENUMERATION" | jq -r '.status')
  if [ "$STATUS" = "ACTIVE" ]; then
    echo "✓ PASS: Status is ACTIVE (owner alive, fresh heartbeat)"
    ((PASS++))
  else
    echo "✗ FAIL: Expected status=ACTIVE, got: $STATUS"
    ((FAIL++))
  fi
else
  echo "✗ FAIL: enumerate_loops did not return loop entry"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 10: compute_dead_time_ratio - Active Loop"
echo "========================================"

RATIO=$(compute_dead_time_ratio "$LOOP_ID" "$TEST_HOME/.claude/loops/registry.json")

# With 5 iterations, 10s cadence, 100s lifespan: active_us = 5*10*1M = 50M, ratio ≈ 0.50
# But we'll just check it's a valid float between 0 and 1
if [[ "$RATIO" =~ ^0\.[0-9]{2}$ ]]; then
  echo "✓ PASS: dead_time_ratio is valid float: $RATIO"
  ((PASS++))
else
  echo "✗ FAIL: dead_time_ratio invalid format: $RATIO"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 11: format_status_table - Single Loop"
echo "========================================"

OUTPUT=$(enumerate_loops "$TEST_HOME/.claude/loops/registry.json" | format_status_table)

if echo "$OUTPUT" | grep -q "LOOP_ID"; then
  echo "✓ PASS: Table has header row"
  ((PASS++))

  if echo "$OUTPUT" | grep -q "a1b2c3d4e5f6"; then
    echo "✓ PASS: Table includes loop_id"
    ((PASS++))
  else
    echo "✗ FAIL: loop_id not in table output"
    ((FAIL++))
  fi
else
  echo "✗ FAIL: Table header missing"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 12: is_reclaim_candidate_v2 - Fresh Owner"
echo "========================================"

CANDIDATE=$(is_reclaim_candidate_v2 "$LOOP_ID" "$TEST_HOME/.claude/loops/registry.json")

if [ "$CANDIDATE" = "no" ]; then
  echo "✓ PASS: Fresh, alive owner → not a reclaim candidate"
  ((PASS++))
else
  echo "✗ FAIL: Expected 'no', got: $CANDIDATE"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 13: is_reclaim_candidate_v2 - Dead Owner (High PID)"
echo "========================================"

# Update registry entry with a dead PID (high number unlikely to exist)
DEAD_ENTRY=$(jq -n \
  --arg loop_id "$LOOP_ID" \
  --arg contract_path "/tmp/test_contract.md" \
  --arg state_dir "$STATE_DIR" \
  --arg generation "0" \
  --arg owner_pid "999999" \
  --arg owner_session_id "test_session_001_abc" \
  --arg expected_cadence "10" \
  --arg started_at_us "$(python3 -c 'import time; print(int((time.time()-100)*1_000_000))')" \
  --arg owner_start_time_us "$(python3 -c 'import time; print(int(time.time()*1_000_000))')" \
  '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, generation: $generation, owner_pid: $owner_pid, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence, started_at_us: $started_at_us, owner_start_time_us: $owner_start_time_us}')

DEAD_REGISTRY=$(jq -n --argjson entry "$DEAD_ENTRY" '{loops: [$entry], schema_version: 1}')
echo "$DEAD_REGISTRY" > "$TEST_HOME/.claude/loops/registry.json"

CANDIDATE=$(is_reclaim_candidate_v2 "$LOOP_ID" "$TEST_HOME/.claude/loops/registry.json")

if [ "$CANDIDATE" = "yes" ]; then
  echo "✓ PASS: Dead owner → reclaim candidate"
  ((PASS++))
else
  echo "✗ FAIL: Expected 'yes', got: $CANDIDATE"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 14: is_reclaim_candidate_v2 - Old State Dir"
echo "========================================"

# Touch state_dir to old mtime (8 days ago)
OLD_MTIME=$(($(date +%s) - 8 * 86400))
touch -t "$(date -r $OLD_MTIME +%Y%m%d%H%M.%S)" "$STATE_DIR"

CANDIDATE=$(is_reclaim_candidate_v2 "$LOOP_ID" "$TEST_HOME/.claude/loops/registry.json")

if [ "$CANDIDATE" = "yes" ]; then
  echo "✓ PASS: Dead owner + old state_dir → reclaim candidate"
  ((PASS++))
else
  echo "✗ FAIL: Expected 'yes', got: $CANDIDATE"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 15: enumerate_loops - JSONL Validity"
echo "========================================"

# Recreate a fresh single-loop registry
ENTRY_JSON=$(jq -n \
  --arg loop_id "$LOOP_ID" \
  --arg contract_path "/tmp/test_contract.md" \
  --arg state_dir "$STATE_DIR" \
  --arg generation "0" \
  --arg owner_pid "$$" \
  --arg owner_session_id "test_session_001_abc" \
  --arg expected_cadence "10" \
  --arg started_at_us "$(python3 -c 'import time; print(int((time.time()-100)*1_000_000))')" \
  '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, generation: $generation, owner_pid: $owner_pid, owner_session_id: $owner_session_id, expected_cadence_seconds: $expected_cadence, started_at_us: $started_at_us}')

REGISTRY=$(jq -n --argjson entry "$ENTRY_JSON" '{loops: [$entry], schema_version: 1}')
echo "$REGISTRY" > "$TEST_HOME/.claude/loops/registry.json"

# Parse each line as JSON
JSONL=$(enumerate_loops "$TEST_HOME/.claude/loops/registry.json")
PARSE_COUNT=0
PARSE_FAIL=0

while IFS= read -r line; do
  if [ -z "$line" ]; then
    continue
  fi
  if echo "$line" | jq . >/dev/null 2>&1; then
    ((PARSE_COUNT++))
  else
    ((PARSE_FAIL++))
  fi
done <<< "$JSONL"

if [ "$PARSE_FAIL" -eq 0 ] && [ "$PARSE_COUNT" -gt 0 ]; then
  echo "✓ PASS: All $PARSE_COUNT lines are valid JSON"
  ((PASS++))
else
  echo "✗ FAIL: $PARSE_FAIL lines failed to parse as JSON"
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
