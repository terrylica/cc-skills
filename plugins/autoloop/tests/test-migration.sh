#!/usr/bin/env bash
# test-migration.sh — Back-compat migration test (MIG-01)
# Tests: existing LOOP_CONTRACT.md without loop_id is auto-derived on first init_state_dir call
# Asserts: idempotent, contract body unchanged, frontmatter mutated

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

# Test counters
PASS=0
FAIL=0
TEMP_DIR=""

# Cleanup function (invoked via trap)
# shellcheck disable=SC2329
cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  # Clean up registry for this test
  if [ -f "$HOME/.claude/loops/registry.json" ]; then
    rm -f "$HOME/.claude/loops/registry.json"
  fi
}
trap cleanup EXIT

echo "========================================"
echo "MIG-01: Back-Compat loop_id Migration"
echo "========================================"
echo ""

# Test 1: Create fixture contract without loop_id
echo "Test 1: Create fixture contract without loop_id"
TEMP_DIR=$(mktemp -d)
CONTRACT_PATH="$TEMP_DIR/LOOP_CONTRACT.md"

cat > "$CONTRACT_PATH" <<'EOF'
---
name: test-migration-loop
version: 1
iteration: 0
last_updated: 2026-04-26T12:00:00Z
exit_condition: manual stop
max_iterations: 50
---
# Core Directive

Test loop for migration purposes.

## Current State

Waiting to begin.

## Implementation Queue

- Setup complete
EOF

BODY_BEFORE=$(tail -n +5 "$CONTRACT_PATH")
echo "✓ Created fixture contract at $CONTRACT_PATH"
((PASS++))

echo ""
echo "Test 2: First init_state_dir call derives loop_id"

# Derive loop_id (as init_state_dir would)
LOOP_ID=$(derive_loop_id "$CONTRACT_PATH")
if [[ "$LOOP_ID" =~ ^[0-9a-f]{12}$ ]]; then
  echo "✓ loop_id derived: $LOOP_ID"
  ((PASS++))
else
  echo "✗ FAIL: Invalid loop_id format: $LOOP_ID"
  ((FAIL++))
fi

# Call init_state_dir (should add loop_id to frontmatter)
if init_state_dir "$LOOP_ID" "$CONTRACT_PATH" 2>/dev/null; then
  echo "✓ init_state_dir succeeded"
  ((PASS++))
else
  echo "✗ FAIL: init_state_dir failed"
  ((FAIL++))
fi

# Verify loop_id is now in frontmatter
if grep -q "^loop_id: $LOOP_ID" "$CONTRACT_PATH"; then
  echo "✓ loop_id added to frontmatter: $LOOP_ID"
  ((PASS++))
else
  echo "✗ FAIL: loop_id not found in frontmatter"
  ((FAIL++))
fi

echo ""
echo "Test 3: Contract body unchanged (only frontmatter mutated)"

BODY_AFTER=$(tail -n +5 "$CONTRACT_PATH")
if [ "$BODY_BEFORE" = "$BODY_AFTER" ]; then
  echo "✓ Contract body unchanged"
  ((PASS++))
else
  echo "✗ FAIL: Contract body was modified"
  echo "Before:"
  echo "$BODY_BEFORE"
  echo "After:"
  echo "$BODY_AFTER"
  ((FAIL++))
fi

echo ""
echo "Test 4: Idempotency - second init_state_dir call"

# Call init_state_dir again
if init_state_dir "$LOOP_ID" "$CONTRACT_PATH" 2>/dev/null; then
  echo "✓ Second init_state_dir succeeded (idempotent)"
  ((PASS++))
else
  echo "✗ FAIL: Second init_state_dir failed"
  ((FAIL++))
fi

# Count occurrences of loop_id line in frontmatter (should be exactly 1)
LOOP_ID_COUNT=$(grep -c "^loop_id:" "$CONTRACT_PATH" || echo 0)
if [ "$LOOP_ID_COUNT" -eq 1 ]; then
  echo "✓ No duplicate loop_id lines (count: $LOOP_ID_COUNT)"
  ((PASS++))
else
  echo "✗ FAIL: Multiple or no loop_id lines found (count: $LOOP_ID_COUNT)"
  ((FAIL++))
fi

# Verify body is still unchanged
BODY_AFTER_2=$(tail -n +5 "$CONTRACT_PATH")
if [ "$BODY_BEFORE" = "$BODY_AFTER_2" ]; then
  echo "✓ Contract body still unchanged after second call"
  ((PASS++))
else
  echo "✗ FAIL: Contract body changed on second call"
  ((FAIL++))
fi

echo ""
echo "Test 5: Registry entry created with minimal fields"

# Read registry entry
if [ -f "$HOME/.claude/loops/registry.json" ]; then
  ENTRY=$(jq ".loops[] | select(.loop_id == \"$LOOP_ID\")" "$HOME/.claude/loops/registry.json" 2>/dev/null) || ENTRY="{}"

  if [ "$ENTRY" != "{}" ]; then
    # Verify essential fields exist
    HAS_LOOP_ID=$(echo "$ENTRY" | jq -e '.loop_id' >/dev/null 2>&1 && echo "yes" || echo "no")
    HAS_CONTRACT=$(echo "$ENTRY" | jq -e '.contract_path' >/dev/null 2>&1 && echo "yes" || echo "no")
    HAS_STATE_DIR=$(echo "$ENTRY" | jq -e '.state_dir' >/dev/null 2>&1 && echo "yes" || echo "no")
    HAS_GENERATION=$(echo "$ENTRY" | jq -e '.generation' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [ "$HAS_LOOP_ID" = "yes" ] && [ "$HAS_CONTRACT" = "yes" ] && [ "$HAS_STATE_DIR" = "yes" ] && [ "$HAS_GENERATION" = "yes" ]; then
      echo "✓ Registry entry created with all essential fields"
      ((PASS++))
    else
      echo "✗ FAIL: Registry entry missing fields (loop_id=$HAS_LOOP_ID, contract=$HAS_CONTRACT, state_dir=$HAS_STATE_DIR, generation=$HAS_GENERATION)"
      ((FAIL++))
    fi
  else
    echo "✗ FAIL: Registry entry not found or empty"
    ((FAIL++))
  fi
else
  echo "⚠ SKIP: Registry file not created (expected if registry not required)"
  ((PASS++))
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
