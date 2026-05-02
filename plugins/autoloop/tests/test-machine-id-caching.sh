#!/usr/bin/env bash
# test-machine-id-caching.sh — Wave 5 C3 cache stability harness
#
# Verifies that current_machine_id():
#   1. Creates the cache file at ~/.claude/loops/.machine-id on first call
#   2. Returns the cached value on subsequent calls (no re-derivation)
#   3. Survives hostname mutation (DHCP rename, Sharing → Computer Name)
#   4. Detects corrupt cache content and recomputes fresh
#   5. Re-stamps after the user explicitly removes the cache file

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Machine ID Caching Tests (Wave 5 C3)"
echo "========================================"

T=$(mktemp -d); export HOME="$T/home"
trap 'rm -rf "$T"' EXIT

CACHE="$HOME/.claude/loops/.machine-id"

echo ""
echo "[Case 1] First call creates cache file"
[ -f "$CACHE" ] && nok "cache existed before first call" || true
mid1=$(current_machine_id)
if [ -f "$CACHE" ]; then
  ok "cache file created at first call"
else
  nok "cache file was NOT created"
fi
if [[ "$mid1" =~ ^[0-9a-f]{12}$ ]]; then
  ok "first call returned 12-hex"
else
  nok "first call returned non-hex: '$mid1'"
fi

echo ""
echo "[Case 2] Subsequent call returns cached value (no re-derive)"
mid2=$(current_machine_id)
if [ "$mid1" = "$mid2" ]; then
  ok "cached value returned identically"
else
  nok "cached value differs: '$mid1' vs '$mid2'"
fi

echo ""
echo "[Case 3] Hostname mutation does NOT change cached value"
# Simulate DHCP/network rename by shadowing the `hostname` binary on PATH.
mkdir -p "$T/bin"
cat > "$T/bin/hostname" <<'EOF'
#!/bin/sh
echo "fake-renamed-host-$$"
EOF
chmod +x "$T/bin/hostname"
ORIG_PATH="$PATH"
export PATH="$T/bin:$PATH"
mid3=$(current_machine_id)
if [ "$mid1" = "$mid3" ]; then
  ok "cache survives hostname mutation (DHCP rename simulated)"
else
  nok "cache invalidated by hostname change: '$mid1' vs '$mid3'"
fi
export PATH="$ORIG_PATH"

echo ""
echo "[Case 4] Corrupt cache content forces fresh compute"
echo "garbage-not-hex" > "$CACHE"
mid4=$(current_machine_id)
if [[ "$mid4" =~ ^[0-9a-f]{12}$ ]]; then
  ok "corrupt cache replaced with valid 12-hex"
else
  nok "corrupt cache returned: '$mid4'"
fi
# After corrupt-recovery, cache should now be valid + match mid4
mid5=$(current_machine_id)
if [ "$mid4" = "$mid5" ]; then
  ok "corrupt-recovered cache stable on next call"
else
  nok "corrupt-recovered cache unstable: '$mid4' vs '$mid5'"
fi

echo ""
echo "[Case 5] Explicit cache removal forces re-stamp"
rm -f "$CACHE"
mid6=$(current_machine_id)
if [ -f "$CACHE" ]; then
  ok "cache file recreated after rm"
else
  nok "cache file NOT recreated"
fi
if [[ "$mid6" =~ ^[0-9a-f]{12}$ ]]; then
  ok "re-stamp returned valid 12-hex"
else
  nok "re-stamp returned: '$mid6'"
fi

echo ""
echo "[Case 6] Empty cache file triggers fresh compute"
: > "$CACHE"
mid7=$(current_machine_id)
if [[ "$mid7" =~ ^[0-9a-f]{12}$ ]]; then
  ok "empty cache replaced with valid 12-hex"
else
  nok "empty cache returned: '$mid7'"
fi

echo ""
echo "[Case 7] Concurrent first-callers do not produce a partial cache file"
rm -f "$CACHE"
# Spawn 5 parallel callers, each in its own subshell.
for _ in 1 2 3 4 5; do
  ( current_machine_id >/dev/null ) &
done
wait
# Final cache must be valid 12-hex (no partial writes thanks to mktemp+mv).
if [ -f "$CACHE" ]; then
  cached=$(head -c 12 "$CACHE" 2>/dev/null || echo "")
  if [[ "$cached" =~ ^[0-9a-f]{12}$ ]]; then
    ok "concurrent first-call produces clean cache"
  else
    nok "concurrent first-call left invalid cache: '$cached'"
  fi
else
  nok "concurrent first-call produced no cache file"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
