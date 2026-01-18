#!/usr/bin/env bash
# sred-integration.sh - Integration tests for SR&ED discovery hook
#
# ADR: 2026-01-18-sred-dynamic-discovery
#
# Usage: ./sred-integration.sh
#
# Tests:
# A. Valid commit with SRED-Claim (should pass)
# B. Missing SRED-Claim (should trigger discovery)
# C. Invalid SRED-Claim format (should block)
# D. Missing SRED-Type (should block)
# E. Fallback project derivation (scope extraction)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="$SCRIPT_DIR/../hooks/sred-commit-guard.ts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

passed=0
failed=0

run_test() {
  local name="$1"
  local input="$2"
  local expected_pattern="$3"
  local should_block="$4"

  echo -n "Test: $name... "

  result=$(echo "$input" | bun "$HOOK_PATH" 2>&1) || true

  if [[ "$should_block" == "true" ]]; then
    if echo "$result" | grep -q "permissionDecision.*deny"; then
      if echo "$result" | grep -q "$expected_pattern"; then
        echo -e "${GREEN}PASSED${NC}"
        ((passed++))
      else
        echo -e "${RED}FAILED${NC} (expected pattern not found: $expected_pattern)"
        echo "Got: $result"
        ((failed++))
      fi
    else
      echo -e "${RED}FAILED${NC} (expected block but allowed)"
      echo "Got: $result"
      ((failed++))
    fi
  else
    if echo "$result" | grep -q "permissionDecision.*deny"; then
      echo -e "${RED}FAILED${NC} (expected allow but blocked)"
      echo "Got: $result"
      ((failed++))
    else
      echo -e "${GREEN}PASSED${NC}"
      ((passed++))
    fi
  fi
}

echo "========================================="
echo "SR&ED Hook Integration Tests"
echo "========================================="
echo ""

# Test A: Valid commit with all trailers
run_test "A: Valid commit with all trailers" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(my-scope): add feature\n\nSRED-Type: experimental-development\nSRED-Claim: MY-SCOPE\""}}' \
  "" \
  "false"

# Test B: Missing SRED-Claim (triggers discovery)
run_test "B: Missing SRED-Claim triggers discovery" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(my-scope): add feature\n\nSRED-Type: experimental-development\""}}' \
  "SRED-Claim" \
  "true"

# Test C: Invalid SRED-Claim format (lowercase)
run_test "C: Invalid SRED-Claim format" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(my-scope): add feature\n\nSRED-Type: experimental-development\nSRED-Claim: my-scope\""}}' \
  "Invalid SRED-Claim format" \
  "true"

# Test D: Missing SRED-Type
run_test "D: Missing SRED-Type" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(my-scope): add feature\n\nSRED-Claim: MY-SCOPE\""}}' \
  "SRED-Type" \
  "true"

# Test E: Invalid SRED-Type
run_test "E: Invalid SRED-Type" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(my-scope): add feature\n\nSRED-Type: invalid-type\nSRED-Claim: MY-SCOPE\""}}' \
  "SRED-Type" \
  "true"

# Test F: Non-git command (should pass through)
run_test "F: Non-git command passes through" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  "" \
  "false"

# Test G: Non-Bash tool (should pass through)
run_test "G: Non-Bash tool passes through" \
  '{"tool_name":"Read","tool_input":{"file_path":"/some/file"}}' \
  "" \
  "false"

# Test H: --no-verify blocked
run_test "H: --no-verify is blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m \"feat: test\""}}' \
  "no-verify" \
  "true"

echo ""
echo "========================================="
echo "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}"
echo "========================================="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
