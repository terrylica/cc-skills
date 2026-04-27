#!/usr/bin/env bash
# test-launchd-plist.sh — Unit and integration tests for launchd plist generation
# Covers WAKE-01, WAKE-02, WAKE-05 (plist syntax, load, unload, idempotency)
# shellcheck disable=SC2329

set -euo pipefail

# Source the launchd library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/launchd-lib.sh" 2>/dev/null || {
  echo "Failed to source launchd-lib.sh" >&2
  exit 1
}

# Test counters and cleanup
PASS=0
FAIL=0
declare -a TEMP_DIRS=()
declare -a TEMP_FILES=()

# Cleanup function
cleanup() {
  # Remove temp directories
  if [ "${#TEMP_DIRS[@]}" -gt 0 ]; then
    for d in "${TEMP_DIRS[@]}"; do
      rm -rf "$d" 2>/dev/null || true
    done
  fi
  # Remove temp files
  if [ "${#TEMP_FILES[@]}" -gt 0 ]; then
    for f in "${TEMP_FILES[@]}"; do
      rm -f "$f" 2>/dev/null || true
    done
  fi
}
trap cleanup EXIT

echo "========================================"
echo "Test 1: plist_label format"
echo "========================================"

LABEL=$(plist_label "a1b2c3d4e5f6")
if [ "$LABEL" = "com.user.claude.loop.a1b2c3d4e5f6" ]; then
  echo "✓ PASS: plist_label returns correct format"
  ((PASS++))
else
  echo "✗ FAIL: plist_label returned '$LABEL'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 2: plist_label rejects invalid format"
echo "========================================"

if ! plist_label "invalid" >/dev/null 2>&1; then
  echo "✓ PASS: plist_label rejects invalid loop_id"
  ((PASS++))
else
  echo "✗ FAIL: plist_label should reject invalid loop_id"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 3: generate_plist creates valid XML"
echo "========================================"

TEST_STATE_DIR=$(mktemp -d)
TEMP_DIRS+=("$TEST_STATE_DIR")

# Create a stub waker script for testing
STUB_WAKER="$TEST_STATE_DIR/waker.sh"
echo '#!/bin/bash' > "$STUB_WAKER"
echo 'echo "stub"' >> "$STUB_WAKER"
chmod +x "$STUB_WAKER"

if generate_plist "a1b2c3d4e5f6" "$TEST_STATE_DIR" "$STUB_WAKER" "300" 2>/dev/null; then
  PLIST_FILE="$TEST_STATE_DIR/waker.plist"
  if [ -f "$PLIST_FILE" ]; then
    echo "✓ PASS: generate_plist creates plist file"
    ((PASS++))
  else
    echo "✗ FAIL: plist file not created"
    ((FAIL++))
  fi
else
  echo "✗ FAIL: generate_plist failed"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 4: generated plist passes plutil -lint"
echo "========================================"

if [[ "$(uname -s)" == "Darwin" ]]; then
  PLIST_FILE="$TEST_STATE_DIR/waker.plist"
  if plutil -lint "$PLIST_FILE" >/dev/null 2>&1; then
    echo "✓ PASS: plist passes plutil -lint validation"
    ((PASS++))
  else
    echo "✗ FAIL: plist fails plutil -lint validation"
    echo "Plist content:"
    cat "$PLIST_FILE"
    ((FAIL++))
  fi
else
  # On non-macOS, use xmllint as a fallback validator
  PLIST_FILE="$TEST_STATE_DIR/waker.plist"
  if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$PLIST_FILE" 2>/dev/null; then
      echo "✓ PASS: plist passes xmllint validation (macOS skipped)"
      ((PASS++))
    else
      echo "✗ FAIL: plist fails xmllint validation"
      ((FAIL++))
    fi
  else
    echo "[SKIP] xmllint not available; cannot validate plist on non-macOS"
  fi
fi

echo ""
echo "========================================"
echo "Test 5: plist contains correct Label"
echo "========================================"

PLIST_FILE="$TEST_STATE_DIR/waker.plist"
if grep -q '<string>com\.user\.claude\.loop\.a1b2c3d4e5f6</string>' "$PLIST_FILE"; then
  echo "✓ PASS: plist contains correct Label"
  ((PASS++))
else
  echo "✗ FAIL: plist does not contain correct Label"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 6: plist contains correct ProgramArguments"
echo "========================================"

if grep -q "<string>$STUB_WAKER</string>" "$PLIST_FILE" && grep -q "<string>a1b2c3d4e5f6</string>" "$PLIST_FILE"; then
  echo "✓ PASS: plist contains correct ProgramArguments"
  ((PASS++))
else
  echo "✗ FAIL: plist does not contain correct ProgramArguments"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 7: plist contains correct StartInterval"
echo "========================================"

if grep -q '<key>StartInterval</key>' "$PLIST_FILE" && grep -q '<integer>300</integer>' "$PLIST_FILE"; then
  echo "✓ PASS: plist contains correct StartInterval"
  ((PASS++))
else
  echo "✗ FAIL: plist does not contain correct StartInterval"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 8: plist with paths containing spaces"
echo "========================================"

TEST_STATE_DIR_SPACES=$(mktemp -d)
TEMP_DIRS+=("$TEST_STATE_DIR_SPACES")
TEST_STATE_DIR_SPACES="$TEST_STATE_DIR_SPACES/path with spaces"
mkdir -p "$TEST_STATE_DIR_SPACES"

STUB_WAKER_SPACES="$TEST_STATE_DIR_SPACES/waker.sh"
echo '#!/bin/bash' > "$STUB_WAKER_SPACES"
chmod +x "$STUB_WAKER_SPACES"

if generate_plist "b2c3d4e5f6a7" "$TEST_STATE_DIR_SPACES" "$STUB_WAKER_SPACES" "300" 2>/dev/null; then
  PLIST_FILE_SPACES="$TEST_STATE_DIR_SPACES/waker.plist"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if plutil -lint "$PLIST_FILE_SPACES" >/dev/null 2>&1; then
      echo "✓ PASS: plist with spaces in path passes plutil -lint"
      ((PASS++))
    else
      echo "✗ FAIL: plist with spaces fails plutil -lint"
      ((FAIL++))
    fi
  else
    echo "[SKIP] plutil not available; testing with xmllint"
    if command -v xmllint >/dev/null 2>&1 && xmllint --noout "$PLIST_FILE_SPACES" 2>/dev/null; then
      echo "✓ PASS: plist with spaces passes xmllint"
      ((PASS++))
    fi
  fi
else
  echo "✗ FAIL: generate_plist failed with spaces in path"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 9: plist with special XML characters"
echo "========================================"

TEST_STATE_DIR_SPECIAL=$(mktemp -d)
TEMP_DIRS+=("$TEST_STATE_DIR_SPECIAL")
TEST_STATE_DIR_SPECIAL="$TEST_STATE_DIR_SPECIAL/path&special<>"
mkdir -p "$TEST_STATE_DIR_SPECIAL"

STUB_WAKER_SPECIAL="$TEST_STATE_DIR_SPECIAL/waker.sh"
echo '#!/bin/bash' > "$STUB_WAKER_SPECIAL"
chmod +x "$STUB_WAKER_SPECIAL"

if generate_plist "c3d4e5f6a7b8" "$TEST_STATE_DIR_SPECIAL" "$STUB_WAKER_SPECIAL" "300" 2>/dev/null; then
  PLIST_FILE_SPECIAL="$TEST_STATE_DIR_SPECIAL/waker.plist"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if plutil -lint "$PLIST_FILE_SPECIAL" >/dev/null 2>&1; then
      echo "✓ PASS: plist with special characters passes plutil -lint"
      ((PASS++))
    else
      echo "✗ FAIL: plist with special characters fails plutil -lint"
      ((FAIL++))
    fi
  else
    echo "[SKIP] plutil not available"
  fi
else
  echo "✗ FAIL: generate_plist failed with special characters"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 10: plist with very long path"
echo "========================================"

TEST_STATE_DIR_LONG=$(mktemp -d)
TEMP_DIRS+=("$TEST_STATE_DIR_LONG")
# Create a path >100 chars
TEST_STATE_DIR_LONG="$TEST_STATE_DIR_LONG/very/long/path/to/test/directory/with/many/subdirectories/to/exceed/100/characters/total"
mkdir -p "$TEST_STATE_DIR_LONG"

STUB_WAKER_LONG="$TEST_STATE_DIR_LONG/waker.sh"
echo '#!/bin/bash' > "$STUB_WAKER_LONG"
chmod +x "$STUB_WAKER_LONG"

if generate_plist "d4e5f6a7b8c9" "$TEST_STATE_DIR_LONG" "$STUB_WAKER_LONG" "600" 2>/dev/null; then
  PLIST_FILE_LONG="$TEST_STATE_DIR_LONG/waker.plist"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if plutil -lint "$PLIST_FILE_LONG" >/dev/null 2>&1; then
      echo "✓ PASS: plist with long path passes plutil -lint"
      ((PASS++))
    else
      echo "✗ FAIL: plist with long path fails plutil -lint"
      ((FAIL++))
    fi
  else
    echo "[SKIP] plutil not available"
  fi
else
  echo "✗ FAIL: generate_plist failed with long path"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 11: load_plist and unload_plist on macOS"
echo "========================================"

if [[ "$(uname -s)" == "Darwin" ]]; then
  # Create a temporary home for testing (to avoid touching real LaunchAgents)
  TEMP_HOME=$(mktemp -d)
  TEMP_DIRS+=("$TEMP_HOME")
  mkdir -p "$TEMP_HOME/Library/LaunchAgents"

  TEST_STATE_DIR_LOAD=$(mktemp -d)
  TEMP_DIRS+=("$TEST_STATE_DIR_LOAD")

  STUB_WAKER_LOAD="$TEST_STATE_DIR_LOAD/test-waker.sh"
  echo '#!/bin/bash' > "$STUB_WAKER_LOAD"
  echo 'exit 0' >> "$STUB_WAKER_LOAD"
  chmod +x "$STUB_WAKER_LOAD"

  # Generate plist
  if generate_plist "e5f6a7b8c9d0" "$TEST_STATE_DIR_LOAD" "$STUB_WAKER_LOAD" "300" 2>/dev/null; then
    # Override HOME for launchctl operations and test load
    export HOME="$TEMP_HOME"
    if load_plist "e5f6a7b8c9d0" "$TEST_STATE_DIR_LOAD" 2>/dev/null; then
      # Check if plist is loaded
      if [ "$(is_plist_loaded "e5f6a7b8c9d0")" = "yes" ]; then
        echo "✓ PASS: load_plist successful and is_plist_loaded confirms"
        ((PASS++))

        # Now unload and verify
        if unload_plist "e5f6a7b8c9d0" "$TEST_STATE_DIR_LOAD" 2>/dev/null; then
          if [ "$(is_plist_loaded "e5f6a7b8c9d0")" = "no" ]; then
            echo "✓ PASS: unload_plist successful and is_plist_loaded confirms unload"
            ((PASS++))
          else
            echo "✗ FAIL: is_plist_loaded still shows loaded after unload"
            ((FAIL++))
          fi
        else
          echo "✗ FAIL: unload_plist failed"
          ((FAIL++))
        fi
      else
        echo "✗ FAIL: is_plist_loaded shows not loaded after load_plist"
        ((FAIL++))
      fi
    else
      echo "✗ FAIL: load_plist failed"
      ((FAIL++))
    fi
  else
    echo "✗ FAIL: generate_plist failed for load test"
    ((FAIL++))
  fi
else
  echo "[SKIP] load/unload tests require macOS; skipped on $(uname -s)"
fi

echo ""
echo "========================================"
echo "Test 12: unload_plist when not loaded is idempotent"
echo "========================================"

if [[ "$(uname -s)" == "Darwin" ]]; then
  TEST_STATE_DIR_UNLOAD=$(mktemp -d)
  TEMP_DIRS+=("$TEST_STATE_DIR_UNLOAD")

  STUB_WAKER_UNLOAD="$TEST_STATE_DIR_UNLOAD/test-waker.sh"
  echo '#!/bin/bash' > "$STUB_WAKER_UNLOAD"
  chmod +x "$STUB_WAKER_UNLOAD"

  # Generate plist but don't load it
  if generate_plist "f6a7b8c9d0e1" "$TEST_STATE_DIR_UNLOAD" "$STUB_WAKER_UNLOAD" "300" 2>/dev/null; then
    # Try to unload without loading first (should succeed idempotently)
    if unload_plist "f6a7b8c9d0e1" "$TEST_STATE_DIR_UNLOAD" 2>/dev/null; then
      echo "✓ PASS: unload_plist on non-loaded plist is idempotent"
      ((PASS++))
    else
      echo "✗ FAIL: unload_plist failed on non-loaded plist"
      ((FAIL++))
    fi
  else
    echo "✗ FAIL: generate_plist failed"
    ((FAIL++))
  fi
else
  echo "[SKIP] unload idempotency test requires macOS"
fi

echo ""
echo "========================================"
echo "Test 13: load_plist rejects invalid plist"
echo "========================================"

if [[ "$(uname -s)" == "Darwin" ]]; then
  TEST_STATE_DIR_INVALID=$(mktemp -d)
  TEMP_DIRS+=("$TEST_STATE_DIR_INVALID")

  # Create a deliberately broken plist (unbalanced tag)
  INVALID_PLIST="$TEST_STATE_DIR_INVALID/waker.plist"
  cat > "$INVALID_PLIST" <<'INVALID_END'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.user.claude.loop.invalid</string
	<!-- Missing closing > on string tag -->
</dict>
</plist>
INVALID_END

  if ! load_plist "a1b2c3d4e5f6" "$TEST_STATE_DIR_INVALID" 2>/dev/null; then
    echo "✓ PASS: load_plist rejects invalid plist"
    ((PASS++))
  else
    echo "✗ FAIL: load_plist should reject invalid plist"
    ((FAIL++))
  fi
else
  echo "[SKIP] invalid plist test requires macOS"
fi

echo ""
echo "========================================"
echo "Test 14: is_plist_loaded returns no for non-existent"
echo "========================================"

RESULT=$(is_plist_loaded "nonexist01")
if [ "$RESULT" = "no" ]; then
  echo "✓ PASS: is_plist_loaded returns 'no' for non-existent loop_id"
  ((PASS++))
else
  echo "✗ FAIL: is_plist_loaded should return 'no', got '$RESULT'"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Test 15: is_plist_loaded rejects invalid loop_id"
echo "========================================"

RESULT=$(is_plist_loaded "invalid_id")
if [ "$RESULT" = "no" ]; then
  echo "✓ PASS: is_plist_loaded returns 'no' for invalid loop_id"
  ((PASS++))
else
  echo "✗ FAIL: is_plist_loaded should return 'no' for invalid format"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
  echo "All tests passed!"
  exit 0
else
  echo "Some tests failed."
  exit 1
fi
