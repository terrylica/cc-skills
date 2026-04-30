#!/usr/bin/env bash
# test-provenance-roundtrip.sh — v2 schema mirror correctness
# Coverage: state-lib.sh (set_contract_field, init_contract_frontmatter_v2)
#
# Verifies:
#   1. set_contract_field inserts a missing field before the closing ---
#   2. set_contract_field replaces an existing field's value (idempotent)
#   3. set_contract_field never touches body content
#   4. init_contract_frontmatter_v2 stamps all v2 birth fields
#   5. init_contract_frontmatter_v2 is idempotent — second call is a no-op on
#      already-populated fields
#   6. campaign_slug is derived from `name:` via slugify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_LIB="$SCRIPT_DIR/../scripts/state-lib.sh"
REGISTRY_LIB="$SCRIPT_DIR/../scripts/registry-lib.sh"

if [ ! -f "$STATE_LIB" ] || [ ! -f "$REGISTRY_LIB" ]; then
  echo "ERROR: required libs not found"
  exit 1
fi

# shellcheck source=/dev/null
source "$REGISTRY_LIB"
# shellcheck source=/dev/null
source "$STATE_LIB"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $desc"
    echo "      expected: '$expected'"
    echo "      actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local desc="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $desc — pattern not found: '$pattern' in $file"
    FAIL=$((FAIL + 1))
  fi
}

# ===== Test 1: set_contract_field inserts missing field =====
echo "Test 1: set_contract_field — insert missing field"
cat > "$TMP/c1.md" <<'EOF'
---
name: test-loop
version: 1
---

# Body

Body content here.
EOF

set_contract_field "$TMP/c1.md" "loop_id" "abc123def456"
assert_grep "loop_id inserted" "$TMP/c1.md" "^loop_id: abc123def456$"
assert_grep "name preserved" "$TMP/c1.md" "^name: test-loop$"
assert_grep "body preserved" "$TMP/c1.md" "^Body content here\.$"

# ===== Test 2: set_contract_field replaces existing field =====
echo "Test 2: set_contract_field — replace existing field (idempotent)"
set_contract_field "$TMP/c1.md" "loop_id" "999fff000111"
assert_grep "loop_id replaced" "$TMP/c1.md" "^loop_id: 999fff000111$"
count=$(grep -c "^loop_id:" "$TMP/c1.md" || true)
assert "loop_id appears exactly once" "$count" "1"

# ===== Test 3: set_contract_field — no-op when contract missing =====
echo "Test 3: set_contract_field — no-op when contract missing"
set_contract_field "$TMP/does-not-exist.md" "foo" "bar"
echo "  ✓ PASS: did not error on missing file"
PASS=$((PASS + 1))

# ===== Test 4: init_contract_frontmatter_v2 stamps birth fields =====
echo "Test 4: init_contract_frontmatter_v2 — stamps birth record"
cat > "$TMP/c2.md" <<'EOF'
---
name: My Cool Campaign
version: 1
---

# Body
EOF

mkdir -p "$TMP/state-c2"
init_contract_frontmatter_v2 "$TMP/c2.md" "fedcba987654" "$TMP/state-c2"

assert_grep "schema_version stamped" "$TMP/c2.md" "^schema_version: 2$"
assert_grep "loop_id stamped" "$TMP/c2.md" "^loop_id: fedcba987654$"
assert_grep "campaign_slug from name (slugified)" "$TMP/c2.md" '^campaign_slug: "my-cool-campaign"$'
assert_grep "created_at_utc stamped (ISO format)" "$TMP/c2.md" '^created_at_utc: "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z"$'
assert_grep "state_dir stamped" "$TMP/c2.md" "^state_dir: \"$TMP/state-c2\"$"
assert_grep "revision_log_path stamped" "$TMP/c2.md" "^revision_log_path: \"$TMP/state-c2/revision-log\"$"
assert_grep "expected_cadence default" "$TMP/c2.md" '^expected_cadence: "hourly"$'
assert_grep "status default" "$TMP/c2.md" '^status: "active"$'

# ===== Test 5: idempotence — re-running init does not duplicate or rewrite =====
echo "Test 5: init_contract_frontmatter_v2 — idempotent"
cp "$TMP/c2.md" "$TMP/c2-before.md"
sleep 1  # ensure timestamps would differ if rewritten
init_contract_frontmatter_v2 "$TMP/c2.md" "fedcba987654" "$TMP/state-c2"

# created_at_utc must match the first stamp (not re-written)
before_ts=$(awk '/^created_at_utc:/ { print; exit }' "$TMP/c2-before.md")
after_ts=$(awk '/^created_at_utc:/ { print; exit }' "$TMP/c2.md")
assert "created_at_utc not rewritten on second call" "$after_ts" "$before_ts"

count=$(grep -c "^loop_id:" "$TMP/c2.md" || true)
assert "loop_id appears exactly once after idempotent re-run" "$count" "1"

count=$(grep -c "^schema_version:" "$TMP/c2.md" || true)
assert "schema_version appears exactly once after idempotent re-run" "$count" "1"

# ===== Test 6: schema_version=1 → upgraded to 2 =====
echo "Test 6: init_contract_frontmatter_v2 — upgrades schema_version 1 → 2"
cat > "$TMP/c3.md" <<'EOF'
---
name: legacy-loop
version: 1
schema_version: 1
---

# Body
EOF
init_contract_frontmatter_v2 "$TMP/c3.md" "111222333444" "$TMP/state-c3"
assert_grep "schema_version upgraded to 2" "$TMP/c3.md" "^schema_version: 2$"
count=$(grep -c "^schema_version:" "$TMP/c3.md" || true)
assert "schema_version appears exactly once after upgrade" "$count" "1"

# ===== Summary =====
echo ""
echo "================================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================================"
[ "$FAIL" -eq 0 ]
