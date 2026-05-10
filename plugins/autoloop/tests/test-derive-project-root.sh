#!/usr/bin/env bash
# test-derive-project-root.sh — Tests for state-lib.sh derive_project_root() (Wave 6).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh"

TEMP_DIR=$(mktemp -d)
# Canonicalize via realpath so test expectations match the cd && pwd -P
# normalization that derive_project_root applies internally. macOS symlinks
# /var/folders → /private/var/folders; without this, Test 2/3/6 fail
# spuriously on the realpath divergence rather than the actual logic.
TEMP_DIR=$(cd "$TEMP_DIR" && pwd -P)
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS+1))
    echo "  PASS: $3"
  else
    FAIL=$((FAIL+1))
    echo "  FAIL: $3"
    echo "    expected: $2"
    echo "    actual:   $1"
  fi
}

# ===== Test 1: v2 layout returns project_root (parent of .autoloop/) =====
echo "Test 1: v2 layout strips .autoloop/<slug>--<hash>/ to recover project_root"
PROJ1="$TEMP_DIR/proj-v2"
mkdir -p "$PROJ1/.autoloop/my-campaign--a1b2c3"
CONTRACT1="$PROJ1/.autoloop/my-campaign--a1b2c3/CONTRACT.md"
touch "$CONTRACT1"
RESULT1=$(derive_project_root "$CONTRACT1" 2>/dev/null)
assert_eq "$RESULT1" "$PROJ1" "v2 contract → project_root"

# ===== Test 2: short_hash must be 6 hex chars =====
echo ""
echo "Test 2: malformed slug-hash directory falls through to git/dir fallback"
PROJ2="$TEMP_DIR/proj-malformed"
mkdir -p "$PROJ2/.autoloop/no-hash-here/"
CONTRACT2="$PROJ2/.autoloop/no-hash-here/CONTRACT.md"
touch "$CONTRACT2"
RESULT2=$(derive_project_root "$CONTRACT2" 2>/dev/null)
# Without the v2 pattern match, falls through to git toplevel (TEMP_DIR isn't
# a git repo) which then falls through to contract_dir itself.
EXPECTED2="$PROJ2/.autoloop/no-hash-here"
assert_eq "$RESULT2" "$EXPECTED2" "malformed v2 falls back to contract dir"

# ===== Test 3: legacy LOOP_CONTRACT.md at non-git path returns its own dir =====
echo ""
echo "Test 3: legacy LOOP_CONTRACT.md (non-git) returns contract dir"
PROJ3="$TEMP_DIR/proj-legacy"
mkdir -p "$PROJ3"
CONTRACT3="$PROJ3/LOOP_CONTRACT.md"
touch "$CONTRACT3"
RESULT3=$(derive_project_root "$CONTRACT3" 2>/dev/null)
assert_eq "$RESULT3" "$PROJ3" "legacy non-git → contract dir"

# ===== Test 4: legacy LOOP_CONTRACT.md inside a git repo returns git toplevel =====
echo ""
echo "Test 4: legacy LOOP_CONTRACT.md inside git repo returns toplevel"
PROJ4="$TEMP_DIR/proj-git-legacy"
mkdir -p "$PROJ4/subdir"
git -C "$PROJ4" init -q 2>/dev/null
CONTRACT4="$PROJ4/subdir/LOOP_CONTRACT.md"
touch "$CONTRACT4"
RESULT4=$(derive_project_root "$CONTRACT4" 2>/dev/null)
# git toplevel is PROJ4 (realpath-resolved on macOS may differ; tolerate).
RESULT4_REAL=$(cd "$RESULT4" && pwd -P 2>/dev/null || echo "$RESULT4")
PROJ4_REAL=$(cd "$PROJ4" && pwd -P)
assert_eq "$RESULT4_REAL" "$PROJ4_REAL" "legacy in git repo → git toplevel"

# ===== Test 5: nonexistent contract_path returns error =====
echo ""
echo "Test 5: nonexistent contract_path errors out"
RESULT5=$(derive_project_root "$TEMP_DIR/does-not-exist/CONTRACT.md" 2>/dev/null) || true
assert_eq "$RESULT5" "" "nonexistent path returns empty stdout"

# ===== Test 6: v2 path with deeper-than-expected nesting =====
echo ""
echo "Test 6: v2 layout with intermediate dirs returns the immediate parent of .autoloop/"
PROJ6="$TEMP_DIR/proj-deep/sub1/sub2"
mkdir -p "$PROJ6/.autoloop/deep-test--bcdef0"
CONTRACT6="$PROJ6/.autoloop/deep-test--bcdef0/CONTRACT.md"
touch "$CONTRACT6"
RESULT6=$(derive_project_root "$CONTRACT6" 2>/dev/null)
RESULT6_REAL=$(cd "$RESULT6" && pwd -P 2>/dev/null || echo "$RESULT6")
PROJ6_REAL=$(cd "$PROJ6" && pwd -P)
assert_eq "$RESULT6_REAL" "$PROJ6_REAL" "deep v2 layout → immediate parent of .autoloop/"

# ===== Summary =====
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
