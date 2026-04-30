#!/usr/bin/env bash
# test-registry-read.sh — Unit tests for registry read helpers
# shellcheck disable=SC2329

set -euo pipefail

# Source the registry library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh" 2>/dev/null || {
  echo "Failed to source registry-lib.sh" >&2
  exit 1
}

# Test environment setup
TEMP_DIR=$(mktemp -d)
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

# Helper: assert_contains
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local test_name="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name"
    echo "  Expected to contain: $needle"
    echo "  Actual: $haystack"
    FAIL=$((FAIL+1))
  fi
}

echo "========================================"
echo "read_registry() Tests"
echo "========================================"
echo ""

# Test 1: Missing registry file
echo "Test 1: Missing registry file"
MISSING_FILE="$TEMP_DIR/nonexistent.json"
RESULT=$(read_registry "$MISSING_FILE")
assert_equals "$RESULT" '{"loops": [], "schema_version": 1}' "Missing file returns empty registry"

echo ""
echo "Test 2: Valid 1-loop registry"
RESULT=$(read_registry "$PLUGIN_DIR/tests/fixtures/registry-1-loop.json")
assert_contains "$RESULT" "a1b2c3d4e5f6" "1-loop fixture read successfully"
assert_contains "$RESULT" "owner_session_id" "Result contains expected field"

echo ""
echo "Test 3: Valid empty registry"
RESULT=$(read_registry "$PLUGIN_DIR/tests/fixtures/registry-empty.json" | jq -c .)
assert_equals "$RESULT" '{"loops":[],"schema_version":1}' "Empty fixture read successfully"

echo ""
echo "Test 4: Malformed JSON handling"
MALFORMED_FILE="$TEMP_DIR/malformed.json"
echo "{ invalid json }" > "$MALFORMED_FILE"
RESULT=$(read_registry "$MALFORMED_FILE" 2>/dev/null)
assert_equals "$RESULT" '{"loops": [], "schema_version": 1}' "Malformed JSON returns empty registry gracefully"

echo ""
echo "========================================"
echo "read_registry_entry() Tests"
echo "========================================"
echo ""

# Test 5: Valid loop_id lookup (exists)
echo "Test 5: Valid loop_id exists in fixture"
RESULT=$(read_registry_entry "a1b2c3d4e5f6" "$PLUGIN_DIR/tests/fixtures/registry-1-loop.json")
assert_contains "$RESULT" "a1b2c3d4e5f6" "Entry found with correct loop_id"
assert_contains "$RESULT" "owner_session_id" "Entry contains owner_session_id field"

echo ""
echo "Test 6: Valid loop_id not in fixture"
RESULT=$(read_registry_entry "ffffffffffffffff" "$PLUGIN_DIR/tests/fixtures/registry-1-loop.json" 2>/dev/null || true)
if [ -z "$RESULT" ] || [ "$RESULT" = "{}" ]; then
  echo "✓ PASS: Nonexistent loop_id returns empty object"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected empty object for nonexistent loop_id"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 7: Invalid loop_id format (too short)"
EXIT_CODE=0
read_registry_entry "abc" "$PLUGIN_DIR/tests/fixtures/registry-1-loop.json" >/dev/null 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 1 ]; then
  echo "✓ PASS: Invalid loop_id format (too short) returns exit code 1"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected exit code 1 for invalid format"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 8: Invalid loop_id format (non-hex)"
EXIT_CODE=0
read_registry_entry "zzzzzzzzzzzz" "$PLUGIN_DIR/tests/fixtures/registry-1-loop.json" >/dev/null 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 1 ]; then
  echo "✓ PASS: Invalid loop_id format (non-hex) returns exit code 1"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected exit code 1 for non-hex loop_id"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 9: Entry lookup in empty registry"
RESULT=$(read_registry_entry "a1b2c3d4e5f6" "$PLUGIN_DIR/tests/fixtures/registry-empty.json")
if [ "$RESULT" = "{}" ]; then
  echo "✓ PASS: Empty registry returns empty object for any loop_id"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected empty object in empty registry"
  FAIL=$((FAIL+1))
fi

echo ""
echo "========================================"
echo "Integration Tests"
echo "========================================"
echo ""

# Test 10: Extract fields from entry
echo "Test 10: Extract and verify fields from entry"
ENTRY=$(read_registry_entry "a1b2c3d4e5f6" "$PLUGIN_DIR/tests/fixtures/registry-1-loop.json")
SESSION=$(echo "$ENTRY" | jq -r '.owner_session_id')
PID=$(echo "$ENTRY" | jq -r '.owner_pid')

if [ "$SESSION" = "claude_abc123def456" ]; then
  echo "✓ PASS: owner_session_id correctly extracted"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: owner_session_id mismatch: $SESSION"
  FAIL=$((FAIL+1))
fi

if [ "$PID" = "12345" ]; then
  echo "✓ PASS: owner_pid correctly extracted"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: owner_pid mismatch: $PID"
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
