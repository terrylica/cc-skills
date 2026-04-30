#!/usr/bin/env bash
# test-loop-id-derivation.sh — Unit tests for loop_id derivation
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

# Test counters
PASS=0
FAIL=0
TEMP_FILES=()

# Cleanup function
cleanup() {
  for f in "${TEMP_FILES[@]}"; do
    rm -f "$f" 2>/dev/null || true
  done
}
trap cleanup EXIT

echo "========================================"
echo "Test 1: Determinism Test"
echo "========================================"

# Create a temporary test file
TEST_FILE=$(mktemp)
TEMP_FILES+=("$TEST_FILE")

# Call derive_loop_id 5 times on same path, collect results
ID1=$(derive_loop_id "$TEST_FILE")
ID2=$(derive_loop_id "$TEST_FILE")
ID3=$(derive_loop_id "$TEST_FILE")
ID4=$(derive_loop_id "$TEST_FILE")
ID5=$(derive_loop_id "$TEST_FILE")

if [ "$ID1" = "$ID2" ] && [ "$ID2" = "$ID3" ] && [ "$ID3" = "$ID4" ] && [ "$ID4" = "$ID5" ]; then
  echo "✓ PASS: All 5 calls return identical loop_id"
  ((PASS++))
else
  echo "✗ FAIL: Loop IDs not deterministic"
  echo "  IDs: $ID1 | $ID2 | $ID3 | $ID4 | $ID5"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 2: Format Test"
echo "========================================"

if [[ "$ID1" =~ ^[0-9a-f]{12}$ ]]; then
  echo "✓ PASS: Loop ID is exactly 12 hexadecimal characters: $ID1"
  ((PASS++))
else
  echo "✗ FAIL: Loop ID format invalid: $ID1"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 3: Collision Resistance Test (10 paths)"
echo "========================================"

ID_LIST=("$ID1")
COLLISION_COUNT=0

for _ in {1..9}; do
  TEMP_FILE=$(mktemp)
  TEMP_FILES+=("$TEMP_FILE")
  ID=$(derive_loop_id "$TEMP_FILE")

  # Check if ID already exists in list
  if [[ " ${ID_LIST[*]} " =~ ' '$ID' ' ]]; then
    echo "✗ COLLISION DETECTED: ID $ID"
    ((COLLISION_COUNT++))
  else
    ID_LIST+=("$ID")
  fi
done

if [ "$COLLISION_COUNT" -eq 0 ]; then
  echo "✓ PASS: 10 distinct paths produced 10 unique IDs"
  ((PASS++))
else
  echo "✗ FAIL: Found $COLLISION_COUNT collisions"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 4: Symlink Resolution Test"
echo "========================================"

TARGET_FILE=$(mktemp)
SYMLINK_FILE="${TARGET_FILE}.link"
TEMP_FILES+=("$TARGET_FILE" "$SYMLINK_FILE")
ln -s "$TARGET_FILE" "$SYMLINK_FILE"

ID_TARGET=$(derive_loop_id "$TARGET_FILE")
ID_SYMLINK=$(derive_loop_id "$SYMLINK_FILE")

if [ "$ID_TARGET" = "$ID_SYMLINK" ]; then
  echo "✓ PASS: Symlink and target resolve to same ID"
  ((PASS++))
else
  echo "✗ FAIL: Symlink and target have different IDs"
  echo "  Target:  $ID_TARGET"
  echo "  Symlink: $ID_SYMLINK"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 5: Nonexistent Path Test"
echo "========================================"

NONEXISTENT="/tmp/definitely-does-not-exist-$RANDOM.md"
EXIT_CODE=0
derive_loop_id "$NONEXISTENT" >/dev/null 2>&1 || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 1 ]; then
  echo "✓ PASS: Nonexistent path returns exit code 1"
  ((PASS++))
else
  echo "✗ FAIL: Nonexistent path returned exit code $EXIT_CODE (expected 1)"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 6: Relative Path Test"
echo "========================================"

TEMP_DIR=$(mktemp -d)
TEMP_FILES+=("$TEMP_DIR")
touch "$TEMP_DIR/contract.md"

ID_RELATIVE=$(derive_loop_id "$TEMP_DIR/contract.md")
ID_ABSOLUTE=$(derive_loop_id "$TEMP_DIR/contract.md")

if [ "$ID_RELATIVE" = "$ID_ABSOLUTE" ]; then
  echo "✓ PASS: Same path resolves consistently"
  ((PASS++))
else
  echo "✗ FAIL: Inconsistent ID derivation"
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
