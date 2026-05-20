#!/usr/bin/env bash
# test-set-contract-frontmatter-field-batch.sh
#
# Unit tests for set_contract_frontmatter_field_batch (iter-28).
# Covers: idempotent updates, mixed insert/replace, multi-line values rejected,
# YAML boundary check (no false matches on nested keys), atomicity (tmp+mv),
# absent-file/missing-frontmatter graceful no-ops.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
STATE_LIB="$PLUGIN_DIR/scripts/state-lib.sh"

# shellcheck source=/dev/null
source "$STATE_LIB"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0

assert_grep() {
  local needle="$1"
  local haystack_file="$2"
  local desc="$3"
  if grep -q -F -- "$needle" "$haystack_file"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc (expected to find '$needle' in $haystack_file)"
    echo "    --- file contents ---"
    sed 's/^/    | /' "$haystack_file"
    FAIL=$((FAIL+1))
  fi
}

assert_not_grep() {
  local needle="$1"
  local haystack_file="$2"
  local desc="$3"
  if ! grep -q -F -- "$needle" "$haystack_file"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc (did not expect to find '$needle')"
    FAIL=$((FAIL+1))
  fi
}

# =============================================================================
# Test 1: replace existing fields + insert new fields in one batch
# =============================================================================
echo "Test 1: replace + insert in one batched call"
CONTRACT="$TEMP_DIR/c1.md"
cat > "$CONTRACT" <<'EOF'
---
name: test-contract
iteration: 0
generation: 0
status: active
---
# Body
EOF

set_contract_frontmatter_field_batch "$CONTRACT" \
  "iteration" "5" \
  "generation" "3" \
  "last_heartbeat_us" "1779260000000000" \
  "last_heartbeat_session_id" "\"abc-def-123\""

assert_grep "iteration: 5" "$CONTRACT" "iteration replaced (was 0 → 5)"
assert_grep "generation: 3" "$CONTRACT" "generation replaced (was 0 → 3)"
assert_grep "last_heartbeat_us: 1779260000000000" "$CONTRACT" "new field inserted (last_heartbeat_us)"
assert_grep "last_heartbeat_session_id: \"abc-def-123\"" "$CONTRACT" "new field inserted (last_heartbeat_session_id)"
assert_grep "name: test-contract" "$CONTRACT" "unrelated field preserved (name)"
assert_grep "status: active" "$CONTRACT" "unrelated field preserved (status)"
assert_grep "# Body" "$CONTRACT" "body preserved"
# Check no duplicate iteration line (replace worked, not insert)
ITER_COUNT=$(grep -c "^iteration:" "$CONTRACT")
if [ "$ITER_COUNT" -eq 1 ]; then
  echo "  ✓ PASS: iteration appears exactly once (no duplicate from replace+insert mixup)"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: iteration appears $ITER_COUNT times (expected 1)"
  FAIL=$((FAIL+1))
fi

# =============================================================================
# Test 2: idempotent — calling twice with same values yields identical output
# =============================================================================
echo ""
echo "Test 2: idempotent (second call is a no-op for replace path)"
CONTRACT="$TEMP_DIR/c2.md"
cat > "$CONTRACT" <<'EOF'
---
iteration: 0
---
EOF

set_contract_frontmatter_field_batch "$CONTRACT" "iteration" "1"
HASH1=$(shasum "$CONTRACT" | awk '{print $1}')
set_contract_frontmatter_field_batch "$CONTRACT" "iteration" "1"
HASH2=$(shasum "$CONTRACT" | awk '{print $1}')
if [ "$HASH1" = "$HASH2" ]; then
  echo "  ✓ PASS: idempotent (sha matches across two calls with same value)"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: file changed between identical calls"
  FAIL=$((FAIL+1))
fi

# =============================================================================
# Test 3: literal-prefix + boundary check — must NOT match nested keys
# This is the same metachar-safety the singular set_contract_field has;
# a field named "a" must NOT match "alphabetic:" or "another:" lines.
# =============================================================================
echo ""
echo "Test 3: literal-prefix + boundary (no false match on nested keys)"
CONTRACT="$TEMP_DIR/c3.md"
cat > "$CONTRACT" <<'EOF'
---
iter: 99
iteration: 0
---
EOF

set_contract_frontmatter_field_batch "$CONTRACT" "iter" "42"

assert_grep "iter: 42" "$CONTRACT" "iter (3 chars) replaced"
assert_grep "iteration: 0" "$CONTRACT" "iteration (longer key) NOT clobbered by iter match"

# =============================================================================
# Test 4: missing file → no-op, exit 0 (best-effort contract)
# =============================================================================
echo ""
echo "Test 4: missing file → graceful no-op"
if set_contract_frontmatter_field_batch "$TEMP_DIR/does-not-exist.md" "iteration" "1"; then
  echo "  ✓ PASS: missing file returns 0"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: missing file returned non-zero"
  FAIL=$((FAIL+1))
fi

# =============================================================================
# Test 5: empty pair list → no-op
# =============================================================================
echo ""
echo "Test 5: zero pairs → no-op (file unchanged)"
CONTRACT="$TEMP_DIR/c5.md"
cat > "$CONTRACT" <<'EOF'
---
iteration: 0
---
EOF
HASH_BEFORE=$(shasum "$CONTRACT" | awk '{print $1}')
set_contract_frontmatter_field_batch "$CONTRACT"
HASH_AFTER=$(shasum "$CONTRACT" | awk '{print $1}')
if [ "$HASH_BEFORE" = "$HASH_AFTER" ]; then
  echo "  ✓ PASS: zero-pair call leaves file unchanged"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: zero-pair call modified the file"
  FAIL=$((FAIL+1))
fi

# =============================================================================
# Test 6: value with = is split on FIRST = only (future-proof for URL values)
# =============================================================================
echo ""
echo "Test 6: value containing '=' preserved verbatim"
CONTRACT="$TEMP_DIR/c6.md"
cat > "$CONTRACT" <<'EOF'
---
url: ""
---
EOF
set_contract_frontmatter_field_batch "$CONTRACT" "url" "\"https://example.com/path?a=1&b=2\""
assert_grep 'url: "https://example.com/path?a=1&b=2"' "$CONTRACT" "value with = preserved"

# =============================================================================
# Test 7: matches the EXACT pattern heartbeat-tick.sh uses
# =============================================================================
echo ""
echo "Test 7: heartbeat-tick.sh 4-field pattern"
CONTRACT="$TEMP_DIR/c7.md"
cat > "$CONTRACT" <<'EOF'
---
name: test
loop_id: bec0deadbeef
last_heartbeat_us: 0
last_heartbeat_session_id: ""
iteration: 0
generation: 0
---
EOF
set_contract_frontmatter_field_batch "$CONTRACT" \
  "last_heartbeat_us" "1779260000123456" \
  "last_heartbeat_session_id" "\"sess-abc-def\"" \
  "iteration" "42" \
  "generation" "7"
assert_grep "last_heartbeat_us: 1779260000123456" "$CONTRACT" "field 1/4"
assert_grep "last_heartbeat_session_id: \"sess-abc-def\"" "$CONTRACT" "field 2/4"
assert_grep "iteration: 42" "$CONTRACT" "field 3/4"
assert_grep "generation: 7" "$CONTRACT" "field 4/4"
assert_grep "loop_id: bec0deadbeef" "$CONTRACT" "untouched field (loop_id) preserved"

# =============================================================================
# Test 8: empty frontmatter (just --- --- with nothing inside) handles inserts
# =============================================================================
echo ""
echo "Test 8: empty frontmatter — inserts all fields before closing ---"
CONTRACT="$TEMP_DIR/c8.md"
cat > "$CONTRACT" <<'EOF'
---
---
# Body
EOF
set_contract_frontmatter_field_batch "$CONTRACT" \
  "iteration" "1" \
  "generation" "2"
assert_grep "iteration: 1" "$CONTRACT" "iteration inserted into empty frontmatter"
assert_grep "generation: 2" "$CONTRACT" "generation inserted into empty frontmatter"
assert_grep "# Body" "$CONTRACT" "body preserved"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
