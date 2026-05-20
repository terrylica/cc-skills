#!/usr/bin/env bash
# test-mktemp-bsd-portable-uniqueness.sh
#
# Regression guard for iter-29 BSD-portable mktemp fix.
#
# Catches the class of bug fixed in iter-29: BSD mktemp on macOS doesn't
# expand XXXXXX when the template ends in a suffix like `.json`. The
# pre-iter-29 pattern `mktemp -p "$DIR" prefix.XXXXXX.json` therefore
# produced a literal `prefix.XXXXXX.json` filename — every "atomic"
# tempfile had the SAME name. Under concurrent writes (multiple sessions,
# hook-install retries, etc.) this would clobber tempfiles mid-write.
#
# The test verifies that:
#   1. portable.sh::mktemp_for_atomic_rename produces UNIQUE filenames
#      across rapid back-to-back calls.
#   2. The inline form `mktemp "$DIR/prefix.XXXXXX"` (used in state-lib.sh
#      and hook-install-lib.sh) also produces unique filenames.
#   3. Both forms work on BOTH BSD (macOS) and GNU (Linux) — confirmed by
#      requiring no `--suffix` flag or `-p` flag (GNU-only options).
#   4. Negative control: the OLD broken form `mktemp -p $DIR prefix.XXXXXX.json`
#      collapses to a literal filename (demonstrates we'd actually catch a
#      regression).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORTABLE_LIB="$PLUGIN_DIR/scripts/portable.sh"

# shellcheck source=/dev/null
source "$PORTABLE_LIB"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

assert_unique() {
  local count="$1"
  local label="$2"
  local unique
  # `find -maxdepth 1 -type f -mindepth 1` lists only regular files in
  # TEST_DIR (no recursion, no `.` self-entry). Counts via `wc -l` of NUL-
  # safe `-print` output. The shellcheck-blessed alternative to `ls -1`.
  unique=$(find "$TEST_DIR" -mindepth 1 -maxdepth 1 -type f -print | wc -l | tr -d ' ')
  if [ "$unique" = "$count" ]; then
    echo "  ✓ PASS: $label ($unique unique files from $count calls)"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $label (expected $count unique files; got $unique)"
    echo "    files in $TEST_DIR:"
    find "$TEST_DIR" -mindepth 1 -maxdepth 1 -type f -print | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi
}

# =============================================================================
# Test 1: portable.sh::mktemp_for_atomic_rename produces unique names
# =============================================================================
echo "Test 1: mktemp_for_atomic_rename uniqueness across 5 rapid calls"
rm -f "$TEST_DIR"/*
for _ in 1 2 3 4 5; do
  mktemp_for_atomic_rename "$TEST_DIR" "heartbeat" >/dev/null
done
assert_unique 5 "mktemp_for_atomic_rename produced 5 distinct tempfiles"

# =============================================================================
# Test 2: inline form `mktemp "$DIR/prefix.XXXXXX"` produces unique names
# (this is the form used directly in state-lib.sh and hook-install-lib.sh)
# =============================================================================
echo ""
echo "Test 2: inline form mktemp \"\$DIR/prefix.XXXXXX\" uniqueness"
rm -f "$TEST_DIR"/*
for _ in 1 2 3 4 5; do
  mktemp "$TEST_DIR/heartbeat.XXXXXX" >/dev/null
done
assert_unique 5 "inline mktemp \$DIR/prefix.XXXXXX produced 5 distinct tempfiles"

# =============================================================================
# Test 3: filenames match the expected X-randomized pattern
# (catches the regression where X's would be literal — the iter-29 bug shape)
# =============================================================================
echo ""
echo "Test 3: filenames match expected randomized pattern"
rm -f "$TEST_DIR"/*
mktemp_for_atomic_rename "$TEST_DIR" "heartbeat" >/dev/null
# `find` + `head -1` instead of `ls -1` — handles weird filenames safely
# (per shellcheck SC2012). Returns ABSOLUTE path; strip dir to get name.
file_path=$(find "$TEST_DIR" -mindepth 1 -maxdepth 1 -type f -print | head -1)
file=$(basename "$file_path")
# Expected: heartbeat.XXXXXX where each X is randomized (alnum)
if echo "$file" | grep -qE '^heartbeat\.[A-Za-z0-9]{6,}$'; then
  echo "  ✓ PASS: filename '$file' matches heartbeat.<6+ alnum chars>"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: filename '$file' does NOT match heartbeat.<alnum>"
  echo "    Suspect: BSD mktemp may have produced literal XXXXXX"
  FAIL=$((FAIL+1))
fi

# Negative control: file MUST NOT be literally "heartbeat.XXXXXX"
if [ "$file" != "heartbeat.XXXXXX" ]; then
  echo "  ✓ PASS: filename is not literally 'heartbeat.XXXXXX' (no regression)"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: filename is literally 'heartbeat.XXXXXX' — iter-29 fix regressed!"
  FAIL=$((FAIL+1))
fi

# =============================================================================
# Test 4: negative control — confirm the OLD broken form still fails
# This demonstrates the test would have CAUGHT the original bug if it had
# existed before the fix. Skip on Linux (GNU mktemp doesn't have this bug).
# =============================================================================
echo ""
echo "Test 4: negative control — BSD broken form fails on macOS as expected"
if [ "$(uname)" = "Darwin" ]; then
  rm -f "$TEST_DIR"/*
  # Use the OLD pattern that iter-29 fixed.
  mktemp -p "$TEST_DIR" prefix.XXXXXX.json 2>/dev/null >/dev/null || true
  mktemp -p "$TEST_DIR" prefix.XXXXXX.json 2>/dev/null >/dev/null || true
  # BSD: produces literal "prefix.XXXXXX.json"; second call may error
  # (file exists) or overwrite. Either way, we should see exactly ONE file
  # with the LITERAL name.
  if [ -f "$TEST_DIR/prefix.XXXXXX.json" ]; then
    echo "  ✓ PASS: confirmed BSD mktemp -p with .json suffix produces literal XXXXXX"
    echo "          (this is the bug iter-29 fixed; the new code at the call sites avoids it)"
    PASS=$((PASS+1))
  else
    echo "  ⚠ INCONCLUSIVE: BSD mktemp behavior changed since iter-29 audit"
    echo "    files in $TEST_DIR:"
    find "$TEST_DIR" -mindepth 1 -maxdepth 1 -print | sed 's/^/      /'
    # Not a failure — if BSD mktemp gets fixed upstream, our fix becomes
    # belt-and-suspenders. But surface it for the operator.
  fi
else
  echo "  ⊘ SKIP: negative control only meaningful on macOS BSD (uname=$(uname))"
fi

# =============================================================================
# Test 5: stress — 100 rapid calls must produce 100 unique filenames
# =============================================================================
echo ""
echo "Test 5: 100 rapid calls produce 100 unique filenames"
rm -f "$TEST_DIR"/*
for _ in $(seq 1 100); do
  mktemp_for_atomic_rename "$TEST_DIR" "stress" >/dev/null
done
assert_unique 100 "100-call stress test"

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
