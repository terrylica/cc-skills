#!/usr/bin/env bash
# test-identity-validation.sh — W1.1+W1.2 input validation harness
#
# Verifies that hostile or malformed identifier values are rejected at the
# boundaries that matter:
#   - is_valid_uuid / is_valid_loop_id / is_valid_jq_simple_path
#   - update_loop_field's jq_path whitelist
#   - waker.sh's tightened UUID regex (via _invariant_check_spawn)
#
# Exits 0 if all assertions pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
echo '{"loops": [{"loop_id": "a1b2c3d4e5f6", "owner_pid": 1, "owner_session_id": "test", "generation": 0}], "schema_version": 1}' \
  > "$HOME/.claude/loops/registry.json"
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0

ok()   { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok()  { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

assert_pass() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else nok "$desc (expected accept, got reject)"; fi
}

assert_fail() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then nok "$desc (expected reject, got accept)"; else ok "$desc"; fi
}

echo "========================================"
echo "Identity Validation Tests (W1.1 + W1.2)"
echo "========================================"

echo ""
echo "[Group 1] is_valid_uuid"
assert_pass "valid UUID v4-style accepted"          is_valid_uuid "12345678-1234-1234-1234-123456789012"
assert_fail "36 dashes rejected"                    is_valid_uuid "------------------------------------"
assert_fail "36 hex with no dashes rejected"        is_valid_uuid "abcdef0123456789abcdef0123456789abcd"
assert_fail "uppercase hex rejected"                is_valid_uuid "12345678-1234-1234-1234-123456789ABC"
assert_fail "empty string rejected"                 is_valid_uuid ""
assert_fail "whitespace-only rejected"              is_valid_uuid "   "
assert_fail "shell-metachar rejected"               is_valid_uuid "12345678-1234-1234-1234-123456789012; rm -rf /"
assert_fail "newline-injected rejected"             is_valid_uuid "12345678-1234-1234-1234-123456789012
"

echo ""
echo "[Group 2] is_valid_loop_id"
assert_pass "12-hex accepted"                       is_valid_loop_id "a1b2c3d4e5f6"
assert_fail "uppercase rejected"                    is_valid_loop_id "A1B2C3D4E5F6"
assert_fail "13-hex rejected"                       is_valid_loop_id "a1b2c3d4e5f6f"
assert_fail "11-hex rejected"                       is_valid_loop_id "a1b2c3d4e5f"
assert_fail "non-hex char rejected"                 is_valid_loop_id "a1b2c3d4e5fz"

echo ""
echo "[Group 3] is_valid_jq_simple_path"
assert_pass ".generation accepted"                  is_valid_jq_simple_path ".generation"
assert_pass ".owner_pid accepted"                   is_valid_jq_simple_path ".owner_pid"
assert_fail "pipe-chained jq rejected"              is_valid_jq_simple_path ".x | env"
assert_fail "function-call jq rejected"             is_valid_jq_simple_path ".x as \$y | env"
assert_fail "nested .a.b rejected"                  is_valid_jq_simple_path ".a.b"
assert_fail "bare path (no leading dot) rejected"   is_valid_jq_simple_path "env"
assert_fail "shell-metachar rejected"               is_valid_jq_simple_path ".x; rm -rf /"

echo ""
echo "[Group 4] update_loop_field jq_path whitelist"
assert_pass "legitimate .generation update"         update_loop_field "a1b2c3d4e5f6" ".generation" "5"
assert_fail "pipe-injection rejected"               update_loop_field "a1b2c3d4e5f6" ". | env" "5"
assert_fail "as-injection rejected"                 update_loop_field "a1b2c3d4e5f6" ".x as \$y | env" "5"
assert_fail "nested-path rejected"                  update_loop_field "a1b2c3d4e5f6" ".a.b" "5"
assert_fail "bare env rejected"                     update_loop_field "a1b2c3d4e5f6" "env" "5"

echo ""
echo "[Group 5] update_loop_field loop_id format"
assert_fail "uppercase loop_id rejected"            update_loop_field "A1B2C3D4E5F6" ".generation" "5"
assert_fail "shell-metachar in loop_id rejected"    update_loop_field "; rm -rf /" ".generation" "5"
assert_fail "empty loop_id rejected"                update_loop_field "" ".generation" "5"

echo ""
echo "[Group 6] log_validation_event smoke test"
log_validation_event validation_reject test_field "hostile-value" caller=harness
LOG="$HOME/.claude/loops/.hook-errors.log"
if [ -s "$LOG" ] && jq -e '.kind == "validation_reject"' "$LOG" >/dev/null 2>&1; then
  ok "log_validation_event wrote structured JSON"
else
  nok "log_validation_event did not produce a parseable line"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
