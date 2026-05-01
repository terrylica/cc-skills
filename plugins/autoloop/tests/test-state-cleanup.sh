#!/usr/bin/env bash
# test-state-cleanup.sh — W2.2 cleanup_state_dir harness
#
# Verifies that cleanup_state_dir:
#   1. Tarballs the state dir before removing it.
#   2. Removes the state dir by default.
#   3. Refuses to operate on paths outside $HOME (safety guard).
#   4. Honors --keep-forensics by archiving without removing.
#   5. Is idempotent on a missing state_dir.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "State Cleanup Tests (W2.2)"
echo "========================================"

T=$(mktemp -d); export HOME="$T/home"
SD="$HOME/loop-state/abcdef012345"

echo ""
echo "[Case 1] Default mode: archive + rm"
mkdir -p "$SD/revision-log"
echo '{"last_wake_us": 1}' > "$SD/heartbeat.json"
echo '{"event":"start"}' > "$SD/revision-log/test.jsonl"

cleanup_state_dir "$SD" >/dev/null 2>&1

if [ ! -d "$SD" ]; then
  ok "state_dir removed"
else
  nok "state_dir still present"
fi

# The tarball lives in the parent.
parent=$(dirname "$SD")
tarballs=$(find "$parent" -maxdepth 1 -name '*-archive-*.tar.gz' 2>/dev/null)
if [ -n "$tarballs" ]; then
  ok "tarball created in parent"
  # Verify tarball contains the heartbeat file.
  if tar -tzf "$tarballs" 2>/dev/null | grep -q 'heartbeat.json'; then
    ok "tarball contains heartbeat.json"
  else
    nok "tarball does not contain heartbeat.json"
  fi
else
  nok "no tarball found"
fi

echo ""
echo "[Case 2] Idempotent: missing state_dir is a no-op"
out=$(cleanup_state_dir "$SD" 2>&1)
if echo "$out" | grep -q "no state_dir to clean"; then
  ok "no-op message printed"
else
  nok "expected no-op, got: $out"
fi

echo ""
echo "[Case 3] Safety guard: refuse paths outside \$HOME"
EXTERNAL=$(mktemp -d)
out=$(cleanup_state_dir "$EXTERNAL" 2>&1 || true)
if echo "$out" | grep -q "refusing to operate"; then
  ok "external path rejected"
else
  nok "external path was NOT rejected. Got: $out"
fi
if [ -d "$EXTERNAL" ]; then
  ok "external dir untouched"
else
  nok "external dir was removed!"
fi
rm -rf "$EXTERNAL"

echo ""
echo "[Case 4] --keep-forensics archives but does NOT remove"
SD2="$HOME/loop-state/fedcba987654"
mkdir -p "$SD2"
echo "data" > "$SD2/file"
cleanup_state_dir "$SD2" --keep-forensics >/dev/null 2>&1
if [ -d "$SD2" ]; then
  ok "state_dir kept"
else
  nok "state_dir was removed despite --keep-forensics"
fi
parent2=$(dirname "$SD2")
tarballs2=$(find "$parent2" -maxdepth 1 -name 'fedcba987654-archive-*.tar.gz' 2>/dev/null)
if [ -n "$tarballs2" ]; then
  ok "tarball created with --keep-forensics"
else
  nok "no tarball created"
fi

echo ""
echo "[Case 5] Empty state_dir argument is a no-op (not an error)"
out=$(cleanup_state_dir "" 2>&1 || true)
if echo "$out" | grep -q "no state_dir to clean"; then
  ok "empty arg no-op"
else
  nok "expected no-op, got: $out"
fi

echo ""
echo "[Case 6] Symlink-traversal attack: symlink under \$HOME pointing outside"
EVIL=$(mktemp -d)
echo "evil-data" > "$EVIL/secret"
SD_LINK="$HOME/loop-state/symlink-attack"
mkdir -p "$(dirname "$SD_LINK")"
ln -s "$EVIL" "$SD_LINK"
out=$(cleanup_state_dir "$SD_LINK" 2>&1 || true)
if [ -f "$EVIL/secret" ]; then
  ok "symlink target outside \$HOME survived (defense held)"
else
  nok "symlink target was deleted — defense BROKE"
fi
if echo "$out" | grep -q "refusing to operate"; then
  ok "explicit refusal message printed"
else
  nok "no refusal message (got: $out)"
fi
rm -rf "$EVIL"

echo ""
echo "[Case 7] Same-second concurrent cleanup must not clobber tarballs"
SDA="$HOME/loop-concurrent-a"; mkdir -p "$SDA"; echo a > "$SDA/data"
SDB="$HOME/loop-concurrent-b"; mkdir -p "$SDB"; echo b > "$SDB/data"
( cleanup_state_dir "$SDA" >/dev/null 2>&1 ) &
( cleanup_state_dir "$SDB" >/dev/null 2>&1 ) &
wait
archive_count=$(find "$HOME" -maxdepth 1 -name 'loop-concurrent-*-archive-*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')
if [ "$archive_count" = "2" ]; then
  ok "two distinct tarballs after concurrent cleanup (random suffix worked)"
else
  nok "expected 2 tarballs, got $archive_count"
fi

rm -rf "$T"
echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
