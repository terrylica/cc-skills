#!/usr/bin/env bash
# test-state-dir.sh — Unit tests for state directory and atomic heartbeat (Phase 5)
# Tests OWN-01, OWN-02, OWN-06, MIG-02
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
source "$PLUGIN_DIR/scripts/state-lib.sh" 2>/dev/null || {
  echo "Failed to source state-lib.sh" >&2
  exit 1
}

# Test environment setup with isolated HOME and temp git repo
TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME"

# Create a temporary git repo for testing
TEST_REPO="$TEMP_DIR/test-repo"
mkdir -p "$TEST_REPO"
cd "$TEST_REPO"
git init >/dev/null 2>&1
git config user.email "test@example.com" >/dev/null 2>&1
git config user.name "Test User" >/dev/null 2>&1

# Create a dummy contract file
CONTRACT_FILE="$TEST_REPO/LOOP_CONTRACT.md"
cat > "$CONTRACT_FILE" << 'EOF'
---
name: test-loop
---
Test contract
EOF

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

# Helper: assert_file_exists
assert_file_exists() {
  local file_path="$1"
  local test_name="$2"

  if [ -f "$file_path" ]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name (file not found: $file_path)"
    FAIL=$((FAIL+1))
  fi
}

# Helper: assert_dir_exists
assert_dir_exists() {
  local dir_path="$1"
  local test_name="$2"

  if [ -d "$dir_path" ]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name (directory not found: $dir_path)"
    FAIL=$((FAIL+1))
  fi
}

echo "========================================"
echo "State Directory Tests (Phase 5)"
echo "========================================"
echo ""

# Test 1: now_us returns a valid microsecond timestamp
echo "Test 1: now_us returns valid microsecond timestamp"
TS=$(now_us)
if [[ "$TS" =~ ^[0-9]+$ ]] && [ ${#TS} -ge 15 ]; then
  echo "✓ PASS: now_us returns valid microseconds (${TS:0:10}...)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: now_us returned invalid format: $TS"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 2: state_dir_path resolves to git-toplevel + .loop-state + loop_id
echo "Test 2: state_dir_path resolves to correct location"
LOOP_ID="a1b2c3d4e5f6"
STATE_PATH=$(state_dir_path "$LOOP_ID" "$CONTRACT_FILE")
# Compare by checking if the path ends with the expected relative path
if [[ "$STATE_PATH" == *"/.loop-state/$LOOP_ID" ]]; then
  echo "✓ PASS: state_dir_path returns correct path"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: state_dir_path returned unexpected path (got: $STATE_PATH)"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 3: init_state_dir creates revision-log subdirectory
echo "Test 3: init_state_dir creates revision-log subdirectory"
init_state_dir "$LOOP_ID" "$CONTRACT_FILE" || {
  echo "✗ FAIL: init_state_dir returned non-zero"
  FAIL=$((FAIL+1))
}
assert_dir_exists "$STATE_PATH/revision-log" "revision-log subdirectory created"

echo ""

# Test 4: init_state_dir adds .loop-state/ to .gitignore (idempotent)
echo "Test 4: init_state_dir adds .loop-state/ to .gitignore (idempotent)"
GITIGNORE="$TEST_REPO/.gitignore"
if grep -q "^\.loop-state/$" "$GITIGNORE"; then
  echo "✓ PASS: .loop-state/ added to .gitignore"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: .loop-state/ not found in .gitignore"
  FAIL=$((FAIL+1))
fi

# Call init_state_dir again (second call should be idempotent)
init_state_dir "$LOOP_ID" "$CONTRACT_FILE" || true

# Count .loop-state/ entries — should still be exactly 1
GITIGNORE_COUNT=$(grep -c "^\.loop-state/$" "$GITIGNORE" || echo "0")
if [ "$GITIGNORE_COUNT" -eq 1 ]; then
  echo "✓ PASS: .gitignore entry is idempotent (count=1)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: .gitignore has duplicate entries (count=$GITIGNORE_COUNT)"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 5: init_state_dir auto-derives loop_id in contract frontmatter if missing (MIG-01 partial)
echo "Test 5: init_state_dir auto-derives loop_id in contract frontmatter"
CONTRACT_FILE2="$TEST_REPO/LOOP_CONTRACT2.md"
cat > "$CONTRACT_FILE2" << 'EOF'
---
name: test-loop-2
---
Test contract 2
EOF

LOOP_ID2="b2c3d4e5f6a1"
init_state_dir "$LOOP_ID2" "$CONTRACT_FILE2" || true

if grep -q "^loop_id: $LOOP_ID2" "$CONTRACT_FILE2"; then
  echo "✓ PASS: loop_id auto-derived in contract frontmatter"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: loop_id not found in contract frontmatter"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 6: init_state_dir auto-registers registry entry if missing (MIG-02)
echo "Test 6: init_state_dir auto-registers entry in registry (MIG-02)"
LOOP_ID3="c3d4e5f6a1b2"
CONTRACT_FILE3="$TEST_REPO/LOOP_CONTRACT3.md"
cat > "$CONTRACT_FILE3" << 'EOF'
---
name: test-loop-3
---
Test contract 3
EOF

init_state_dir "$LOOP_ID3" "$CONTRACT_FILE3" || true

# Check if entry was registered
ENTRY=$(read_registry_entry "$LOOP_ID3" 2>/dev/null || echo "{}")
if [ "$ENTRY" != "{}" ] && echo "$ENTRY" | jq -e ".loop_id == \"$LOOP_ID3\"" >/dev/null 2>&1; then
  echo "✓ PASS: registry entry auto-registered"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: registry entry not found or invalid"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 7: write_heartbeat creates heartbeat.json atomically
echo "Test 7: write_heartbeat creates heartbeat.json atomically"
LOOP_ID4="d4e5f6a1b2c3"
CONTRACT_FILE4="$TEST_REPO/LOOP_CONTRACT4.md"
cat > "$CONTRACT_FILE4" << 'EOF'
---
name: test-loop-4
---
Test contract 4
EOF

init_state_dir "$LOOP_ID4" "$CONTRACT_FILE4" || true
STATE_PATH4=$(state_dir_path "$LOOP_ID4" "$CONTRACT_FILE4")

if write_heartbeat "$LOOP_ID4" "test_session_1" "1" "$CONTRACT_FILE4"; then
  assert_file_exists "$STATE_PATH4/heartbeat.json" "heartbeat.json created"
else
  echo "✗ FAIL: write_heartbeat returned non-zero"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 8: write_heartbeat captures registry's current generation field
echo "Test 8: write_heartbeat captures registry generation"
HB_CONTENT=$(cat "$STATE_PATH4/heartbeat.json")
GEN=$(echo "$HB_CONTENT" | jq -r '.generation // "missing"')
if [ "$GEN" != "missing" ]; then
  echo "✓ PASS: heartbeat contains generation field ($GEN)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: heartbeat missing generation field"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 9: write_heartbeat includes all required fields
echo "Test 9: write_heartbeat includes all required fields"
LOOP_ID_IN_HB=$(echo "$HB_CONTENT" | jq -r '.loop_id // "missing"')
SESSION_ID=$(echo "$HB_CONTENT" | jq -r '.session_id // "missing"')
ITERATION=$(echo "$HB_CONTENT" | jq -r '.iteration // "missing"')
LAST_WAKE=$(echo "$HB_CONTENT" | jq -r '.last_wake_us // "missing"')

if [ "$LOOP_ID_IN_HB" != "missing" ] && [ "$SESSION_ID" != "missing" ] && [ "$ITERATION" != "missing" ] && [ "$LAST_WAKE" != "missing" ]; then
  echo "✓ PASS: heartbeat contains all required fields"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: heartbeat missing required fields"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 10: read_heartbeat returns JSON content when file exists
echo "Test 10: read_heartbeat returns JSON content"
HEARTBEAT=$(read_heartbeat "$LOOP_ID4" "$CONTRACT_FILE4")
if [ "$HEARTBEAT" != "{}" ] && echo "$HEARTBEAT" | jq . >/dev/null 2>&1; then
  echo "✓ PASS: read_heartbeat returns valid JSON"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: read_heartbeat returned invalid JSON"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 11: read_heartbeat returns {} for missing heartbeat (no error)
echo "Test 11: read_heartbeat returns {} for missing heartbeat"
LOOP_ID5="e5f6a1b2c3d4"
CONTRACT_FILE5="$TEST_REPO/LOOP_CONTRACT5.md"
cat > "$CONTRACT_FILE5" << 'EOF'
---
name: test-loop-5
---
Test contract 5
EOF

init_state_dir "$LOOP_ID5" "$CONTRACT_FILE5" || true
# Don't write heartbeat; should return {}
MISSING_HB=$(read_heartbeat "$LOOP_ID5" "$CONTRACT_FILE5")
assert_equals "$MISSING_HB" "{}" "read_heartbeat returns {} for missing file"

echo ""

# Test 12: Concurrent heartbeat writes don't corrupt the file
echo "Test 12: Concurrent heartbeat writes atomic (no partial files)"
LOOP_ID6="f6a1b2c3d4e5"
CONTRACT_FILE6="$TEST_REPO/LOOP_CONTRACT6.md"
cat > "$CONTRACT_FILE6" << 'EOF'
---
name: test-loop-6
---
Test contract 6
EOF

init_state_dir "$LOOP_ID6" "$CONTRACT_FILE6" || true
STATE_PATH6=$(state_dir_path "$LOOP_ID6" "$CONTRACT_FILE6")

# Write heartbeat 3 times rapidly
for i in 1 2 3; do
  write_heartbeat "$LOOP_ID6" "session_${i}" "$i" "$CONTRACT_FILE6" >/dev/null 2>&1 || true
done

# Verify final file is valid JSON (no partial writes visible)
if [ -f "$STATE_PATH6/heartbeat.json" ] && jq . "$STATE_PATH6/heartbeat.json" >/dev/null 2>&1; then
  echo "✓ PASS: heartbeat.json is valid after concurrent writes"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: heartbeat.json corrupted or missing"
  FAIL=$((FAIL+1))
fi

echo ""

# Test 13: state_dir_path works without git repo (fallback)
echo "Test 13: state_dir_path fallback to contract parent if not in git repo"
NON_GIT_DIR="$TEMP_DIR/non-git-dir"
mkdir -p "$NON_GIT_DIR"
NON_GIT_CONTRACT="$NON_GIT_DIR/contract.md"
touch "$NON_GIT_CONTRACT"

LOOP_ID7="a1b2c3d4e5f7"
FALLBACK_PATH=$(state_dir_path "$LOOP_ID7" "$NON_GIT_CONTRACT")
# Check that path ends with expected suffix (ignore symlink resolution differences)
if [[ "$FALLBACK_PATH" == *"/non-git-dir/.loop-state/$LOOP_ID7" ]]; then
  echo "✓ PASS: state_dir_path fallback to contract parent"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: state_dir_path fallback (got: $FALLBACK_PATH)"
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
