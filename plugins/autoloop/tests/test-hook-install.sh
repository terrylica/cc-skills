#!/usr/bin/env bash
# PROCESS-STORM-OK
# test-hook-install.sh — Comprehensive tests for hook install/uninstall (Phase 7: HOOK-01, HOOK-06, HOOK-07)
# Tests idempotent install, uninstall, concurrency safety, and error handling
# shellcheck disable=SC2329

set -euo pipefail

# Source the hook-install library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/hook-install-lib.sh" 2>/dev/null || {
  echo "Failed to source hook-install-lib.sh" >&2
  exit 1
}

# Test environment setup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Override Claude settings path for tests (NEVER touch real ~/.claude/settings.json)
export HOME="$TEMP_DIR"
export CLAUDE_SETTINGS_PATH="$TEMP_DIR/.claude/settings.json"
mkdir -p "$TEMP_DIR/.claude"

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

# Helper: assert_file_exists
assert_file_exists() {
  local filepath="$1"
  local test_name="$2"

  if [ -f "$filepath" ]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name (file not found at $filepath)"
    FAIL=$((FAIL+1))
  fi
}

# Helper: assert_file_not_exists
assert_file_not_exists() {
  local filepath="$1"
  local test_name="$2"

  if [ ! -f "$filepath" ]; then
    echo "✓ PASS: $test_name"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: $test_name (file exists at $filepath)"
    FAIL=$((FAIL+1))
  fi
}

echo "========================================"
echo "PHASE 7 Hook Install/Uninstall Tests"
echo "REQUIREMENTS: HOOK-01, HOOK-06, HOOK-07"
echo "========================================"
echo ""

# Test 1: Install into empty HOME (no settings.json exists)
echo "Test 1: Install into empty HOME (creates settings.json)"
rm -f "$CLAUDE_SETTINGS_PATH"
HOOK_PATH="$PLUGIN_DIR/hooks/heartbeat-tick.sh"
if install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null; then
  assert_file_exists "$CLAUDE_SETTINGS_PATH" "settings.json created"

  # Verify hook is in the file
  INSTALLED=$(is_hook_installed "$CLAUDE_SETTINGS_PATH")
  assert_equals "$INSTALLED" "yes" "Hook marked as installed"

  # Verify JSON structure
  COMMAND=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$CLAUDE_SETTINGS_PATH")
  assert_contains "$COMMAND" "autonomous-loop/hooks/heartbeat-tick.sh" "Hook command correct"
else
  echo "✗ FAIL: Install failed for empty settings.json creation"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 2: Install into existing settings.json with other hooks"
rm -f "$CLAUDE_SETTINGS_PATH"

# Create settings.json with one existing hook
jq -n '
  {
    "hooks": {
      "PostToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/usr/local/bin/existing-hook.sh"
            }
          ]
        }
      ]
    }
  }
' > "$CLAUDE_SETTINGS_PATH" || {
  echo "✗ FAIL: Could not create test fixture"
  FAIL=$((FAIL+1))
}

if install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null; then
  # Verify BOTH hooks exist
  HOOKS_COUNT=$(jq '.hooks.PostToolUse[0].hooks | length' "$CLAUDE_SETTINGS_PATH")
  if [ "$HOOKS_COUNT" = "2" ]; then
    echo "✓ PASS: Both existing and new hooks preserved"
    PASS=$((PASS+1))
  else
    echo "✗ FAIL: Expected 2 hooks, got $HOOKS_COUNT"
    FAIL=$((FAIL+1))
  fi

  # Verify existing hook still there
  EXISTING=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$CLAUDE_SETTINGS_PATH")
  assert_equals "$EXISTING" "/usr/local/bin/existing-hook.sh" "Existing hook preserved exactly"

  # Verify new hook added
  NEW=$(jq -r '.hooks.PostToolUse[0].hooks[1].command' "$CLAUDE_SETTINGS_PATH")
  assert_contains "$NEW" "autonomous-loop/hooks/heartbeat-tick.sh" "New hook appended"
else
  echo "✗ FAIL: Install into existing settings failed"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 3: Install twice in a row (idempotent; second is no-op)"
rm -f "$CLAUDE_SETTINGS_PATH"

# First install
install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || {
  echo "✗ FAIL: First install failed"
  FAIL=$((FAIL+1))
}

FIRST_CONTENT=$(cat "$CLAUDE_SETTINGS_PATH")

# Second install (should be no-op)
install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || {
  echo "✗ FAIL: Second install failed"
  FAIL=$((FAIL+1))
}

SECOND_CONTENT=$(cat "$CLAUDE_SETTINGS_PATH")
HOOKS_COUNT=$(jq '.hooks.PostToolUse[0].hooks | length' "$CLAUDE_SETTINGS_PATH")

if [ "$FIRST_CONTENT" = "$SECOND_CONTENT" ] && [ "$HOOKS_COUNT" = "1" ]; then
  echo "✓ PASS: Second install is idempotent (no duplicate entry)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Second install was not idempotent"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 4: Uninstall removes our hook, leaves other PostToolUse entries intact"
rm -f "$CLAUDE_SETTINGS_PATH"

# Create settings.json with two hooks
jq -n '
  {
    "hooks": {
      "PostToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/usr/local/bin/other-hook.sh"
            },
            {
              "type": "command",
              "command": "'"$HOOK_PATH"'"
            }
          ]
        }
      ]
    }
  }
' > "$CLAUDE_SETTINGS_PATH"

uninstall_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || {
  echo "✗ FAIL: Uninstall failed"
  FAIL=$((FAIL+1))
}

HOOKS_AFTER=$(jq '.hooks.PostToolUse[0].hooks | length' "$CLAUDE_SETTINGS_PATH")
REMAINING=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$CLAUDE_SETTINGS_PATH")

if [ "$HOOKS_AFTER" = "1" ] && [ "$REMAINING" = "/usr/local/bin/other-hook.sh" ]; then
  echo "✓ PASS: Uninstall removes our hook, preserves other hooks"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Uninstall didn't work correctly (remaining: $REMAINING, count: $HOOKS_AFTER)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 5: Uninstall when hook not installed (idempotent success)"
rm -f "$CLAUDE_SETTINGS_PATH"

# Create settings.json WITHOUT our hook
jq -n '
  {
    "hooks": {
      "PostToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/usr/local/bin/other-hook.sh"
            }
          ]
        }
      ]
    }
  }
' > "$CLAUDE_SETTINGS_PATH"

EXIT_CODE=0
uninstall_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || EXIT_CODE=$?

if [ "$EXIT_CODE" = "0" ]; then
  echo "✓ PASS: Uninstall when not installed returns success (idempotent)"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected exit code 0, got $EXIT_CODE"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 6: Uninstall when settings.json doesn't exist (idempotent success)"
rm -f "$CLAUDE_SETTINGS_PATH"

EXIT_CODE=0
uninstall_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || EXIT_CODE=$?

if [ "$EXIT_CODE" = "0" ]; then
  echo "✓ PASS: Uninstall when settings.json missing returns success"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected exit code 0, got $EXIT_CODE"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 7: Concurrent install (2 parallel subshells) - final settings has exactly ONE entry"
rm -f "$CLAUDE_SETTINGS_PATH"

# Function to run in background
concurrent_install() {
  install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || true
}

# Start two concurrent installs
concurrent_install &
PID1=$!
concurrent_install &
PID2=$!

# Wait for both to complete
wait $PID1 $PID2

# Verify final state: exactly ONE entry for our hook
HOOKS_COUNT=$(jq '.hooks.PostToolUse[0].hooks | length' "$CLAUDE_SETTINGS_PATH" 2>/dev/null || echo "0")
if [ "$HOOKS_COUNT" = "1" ]; then
  echo "✓ PASS: Concurrent install results in exactly ONE hook entry"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Concurrent install resulted in $HOOKS_COUNT entries (expected 1)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 8: Malformed settings.json (invalid JSON) - install errors loudly"
rm -f "$CLAUDE_SETTINGS_PATH"

# Create malformed JSON
echo "{ invalid json }" > "$CLAUDE_SETTINGS_PATH"

EXIT_CODE=0
install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || EXIT_CODE=$?

if [ "$EXIT_CODE" != "0" ]; then
  echo "✓ PASS: Malformed JSON causes install to fail"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Expected install to fail on malformed JSON"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 9: Backup created on first install"
rm -f "$CLAUDE_SETTINGS_PATH"
rm -f "$TEMP_DIR/.claude/.settings.backup"*

# Create initial settings.json
jq -n '
  {
    "hooks": {
      "PostToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/usr/local/bin/initial-hook.sh"
            }
          ]
        }
      ]
    }
  }
' > "$CLAUDE_SETTINGS_PATH"

ORIGINAL_CONTENT=$(cat "$CLAUDE_SETTINGS_PATH")

# Install (should create backup)
install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || {
  echo "✗ FAIL: Install failed"
  FAIL=$((FAIL+1))
}

# Check if backup exists
BACKUP_FILES=$(find "$TEMP_DIR/.claude" -name ".settings.backup.*" -type f)
if [ -n "$BACKUP_FILES" ]; then
  echo "✓ PASS: Backup file created on first install"
  PASS=$((PASS+1))

  # Verify backup content matches original (compare as normalized JSON)
  BACKUP_FILE=$(find "$TEMP_DIR/.claude" -name ".settings.backup.*" -type f | head -1)
  if [ -f "$BACKUP_FILE" ]; then
    BACKUP_CONTENT=$(cat "$BACKUP_FILE")
    ORIGINAL_NORMALIZED=$(echo "$ORIGINAL_CONTENT" | jq -c .)
    BACKUP_NORMALIZED=$(echo "$BACKUP_CONTENT" | jq -c .)
    if [ "$ORIGINAL_NORMALIZED" = "$BACKUP_NORMALIZED" ]; then
      echo "✓ PASS: Backup contains original content"
      PASS=$((PASS+1))
    else
      echo "✗ FAIL: Backup content doesn't match original"
      FAIL=$((FAIL+1))
    fi
  else
    echo "✗ FAIL: Could not read backup file"
    FAIL=$((FAIL+1))
  fi
else
  echo "✗ FAIL: No backup file created"
  FAIL=$((FAIL+1))
fi

# Second install should NOT create another backup
BACKUP_COUNT_BEFORE=$(find "$TEMP_DIR/.claude" -name ".settings.backup.*" -type f | wc -l)
install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null || true
BACKUP_COUNT_AFTER=$(find "$TEMP_DIR/.claude" -name ".settings.backup.*" -type f | wc -l)

if [ "$BACKUP_COUNT_BEFORE" = "$BACKUP_COUNT_AFTER" ]; then
  echo "✓ PASS: Second install doesn't create duplicate backup"
  PASS=$((PASS+1))
else
  echo "✗ FAIL: Second install created extra backup"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Test 10: is_hook_installed detection"
rm -f "$CLAUDE_SETTINGS_PATH"

# Not installed yet
INSTALLED=$(is_hook_installed "$CLAUDE_SETTINGS_PATH")
assert_equals "$INSTALLED" "no" "is_hook_installed returns 'no' when not installed"

# Install
install_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null

# Now installed
INSTALLED=$(is_hook_installed "$CLAUDE_SETTINGS_PATH")
assert_equals "$INSTALLED" "yes" "is_hook_installed returns 'yes' after install"

# Uninstall
uninstall_hook "$CLAUDE_SETTINGS_PATH" "$HOOK_PATH" 2>/dev/null

# Now not installed
INSTALLED=$(is_hook_installed "$CLAUDE_SETTINGS_PATH")
assert_equals "$INSTALLED" "no" "is_hook_installed returns 'no' after uninstall"

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
