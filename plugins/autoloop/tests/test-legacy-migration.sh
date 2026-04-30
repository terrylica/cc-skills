#!/usr/bin/env bash
# test-legacy-migration.sh — Wave 3 storage layout primitives
# Coverage: state-lib.sh (slugify, compute_short_hash, derive_v2_contract_path,
#                         migrate_legacy_contract, state_dir_path v2 detection)
#
# Verifies:
#   1. slugify produces stable kebab-case slugs
#   2. compute_short_hash is deterministic given same seeds
#   3. state_dir_path detects .autoloop/<slug>--<hash>/ → sibling state/
#   4. state_dir_path falls back to legacy layout for non-.autoloop paths
#   5. migrate_legacy_contract no-ops when no legacy contract present
#   6. migrate_legacy_contract no-ops when v2 contract already present
#   7. migrate_legacy_contract performs the full move:
#        - creates .autoloop/<slug>--<hash>/CONTRACT.md
#        - moves legacy state dir under it
#        - stamps v2 frontmatter
#        - updates registry
#        - appends .autoloop/ to .gitignore
#   8. migrate_legacy_contract is idempotent (second call = noop)

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
TMP_RAW=$(mktemp -d)
# macOS resolves /var/folders → /private/var/folders via realpath; state_dir_path
# uses pwd -P which returns the resolved form. Match it for assertion stability.
TMP=$(cd "$TMP_RAW" && pwd -P)
HOME_BACKUP="$HOME"
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/loops"
trap 'export HOME="$HOME_BACKUP"; rm -rf "$TMP_RAW"' EXIT

assert_eq() {
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

assert_file() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $desc — does not exist: $path"
    FAIL=$((FAIL + 1))
  fi
}

# ===== Test 1: slugify =====
echo "Test 1: slugify"
assert_eq "kebab-case from spaces" "$(slugify 'My Cool Campaign')" "my-cool-campaign"
assert_eq "punctuation collapsed" "$(slugify 'Foo!! Bar??')" "foo-bar"
assert_eq "leading/trailing dashes trimmed" "$(slugify '__hello__')" "hello"
assert_eq "empty input returns empty" "$(slugify '')" ""
assert_eq "already-slug passthrough" "$(slugify 'odb-research')" "odb-research"

# ===== Test 2: compute_short_hash determinism =====
echo "Test 2: compute_short_hash determinism"
h1=$(compute_short_hash "session-abc" "2026-04-30T00:00:00Z")
h2=$(compute_short_hash "session-abc" "2026-04-30T00:00:00Z")
h3=$(compute_short_hash "session-xyz" "2026-04-30T00:00:00Z")
assert_eq "same seeds → same hash" "$h1" "$h2"
if [ "$h1" != "$h3" ]; then
  echo "  ✓ PASS: different seeds → different hash"
  PASS=$((PASS + 1))
else
  echo "  ✗ FAIL: different seeds collided"
  FAIL=$((FAIL + 1))
fi
assert_eq "hash is 6 hex chars" "${#h1}" "6"

# ===== Test 3: state_dir_path detects .autoloop layout =====
echo "Test 3: state_dir_path .autoloop detection"
mkdir -p "$TMP/proj1/.autoloop/odb-research--abc123"
touch "$TMP/proj1/.autoloop/odb-research--abc123/CONTRACT.md"
v2_state=$(state_dir_path "111111111111" "$TMP/proj1/.autoloop/odb-research--abc123/CONTRACT.md")
assert_eq "v2 contract → sibling state/" "$v2_state" "$TMP/proj1/.autoloop/odb-research--abc123/state"

# ===== Test 4: state_dir_path falls back for legacy =====
echo "Test 4: state_dir_path legacy fallback"
mkdir -p "$TMP/proj2"
cd "$TMP/proj2"
git init -q .
touch LOOP_CONTRACT.md
git add LOOP_CONTRACT.md && git -c user.email=test@test -c user.name=test commit -q -m init
legacy_state=$(state_dir_path "222222222222" "$TMP/proj2/LOOP_CONTRACT.md")
assert_eq "legacy contract → git-toplevel/.loop-state/" "$legacy_state" "$TMP/proj2/.loop-state/222222222222"
cd "$TMP"

# ===== Test 5: migrate_legacy_contract no-op (no legacy) =====
echo "Test 5: migrate_legacy_contract no-op (no legacy)"
mkdir -p "$TMP/proj3"
out=$(migrate_legacy_contract "$TMP/proj3" "test-session")
assert_eq "no-op returns 'noop'" "$out" "noop"

# ===== Test 6: migrate_legacy_contract no-op (v2 already present) =====
echo "Test 6: migrate_legacy_contract no-op (v2 already present)"
mkdir -p "$TMP/proj4/.autoloop/foo--abc123"
touch "$TMP/proj4/.autoloop/foo--abc123/CONTRACT.md"
touch "$TMP/proj4/LOOP_CONTRACT.md"  # legacy + v2 both present
out=$(migrate_legacy_contract "$TMP/proj4" "test-session")
assert_eq "skips when v2 already exists" "$out" "noop"

# ===== Test 7: migrate_legacy_contract end-to-end =====
echo "Test 7: migrate_legacy_contract full move"
mkdir -p "$TMP/proj5"
cd "$TMP/proj5"
git init -q .
git config user.email test@test
git config user.name test

cat > LOOP_CONTRACT.md <<'EOF'
---
name: My Migration Test
version: 1
loop_id: deadbeefcafe
created_at_utc: "2026-04-30T12:00:00Z"
---

# Body content
EOF
git add LOOP_CONTRACT.md
git commit -q -m init

# Set up legacy state dir
mkdir -p "$TMP/proj5/.loop-state/deadbeefcafe/revision-log"
echo '{"event":"sample"}' > "$TMP/proj5/.loop-state/deadbeefcafe/revision-log/sample.jsonl"

out=$(migrate_legacy_contract "$TMP/proj5" "session-xyz" 2>&1)
echo "$out" | head -3

# Extract the new path
new_path=$(echo "$out" | awk '/^migrated_to_path:/ { print $2 }')
new_loop=$(echo "$out" | awk '/^migrated_to_loop_id:/ { print $2 }')

assert_file "new contract exists" "$new_path"
if [ -f "$TMP/proj5/LOOP_CONTRACT.md" ]; then
  echo "  ✗ FAIL: legacy LOOP_CONTRACT.md should be moved, but still exists"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ PASS: legacy LOOP_CONTRACT.md removed (moved)"
  PASS=$((PASS + 1))
fi

new_dir=$(dirname "$new_path")
assert_file "new state dir exists" "$new_dir/state"
assert_file "revision-log preserved" "$new_dir/state/revision-log/sample.jsonl"

# Verify .autoloop/ added to .gitignore
assert_grep ".autoloop in .gitignore" "$TMP/proj5/.gitignore" '^\.autoloop/$'

# Verify v2 frontmatter on new contract
assert_grep "schema_version: 2" "$new_path" '^schema_version: 2$'
assert_grep "campaign_slug present" "$new_path" '^campaign_slug:'
assert_grep "new loop_id stamped" "$new_path" "^loop_id: $new_loop$"
assert_grep "body content preserved" "$new_path" '^# Body content$'

# Verify dirname pattern: <project_cwd>/.autoloop/my-migration-test--<6hex>
case "$new_dir" in
  "$TMP/proj5/.autoloop/my-migration-test--"[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
    echo "  ✓ PASS: directory follows <slug>--<6hex> pattern"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "  ✗ FAIL: directory pattern wrong: $new_dir"
    FAIL=$((FAIL + 1))
    ;;
esac

# state_dir_path on the new contract should now resolve to the sibling state/
v2_state=$(state_dir_path "$new_loop" "$new_path")
assert_eq "state_dir_path on new contract returns sibling state/" "$v2_state" "$new_dir/state"

# ===== Test 8: idempotence — second migration call is noop =====
echo "Test 8: migrate_legacy_contract idempotent"
out2=$(migrate_legacy_contract "$TMP/proj5" "session-xyz" 2>&1)
assert_eq "second call returns 'noop'" "$out2" "noop"

cd "$TMP"

# ===== Summary =====
echo ""
echo "================================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================================"
[ "$FAIL" -eq 0 ]
