#!/usr/bin/env bash
# test-quarantine-xattr.sh — Wave 5 A4 strip_plugin_quarantine_xattrs harness
#
# Verifies:
#   1. Function exists and is exported by hook-install-lib.sh
#   2. Returns 0 cleanly on a clean tree (no xattrs to strip)
#   3. On macOS: actually strips com.apple.quarantine when present
#   4. Stripped count is reported on stdout
#   5. No-op when plugin root doesn't exist (defensive)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/hook-install-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Quarantine Xattr Strip Tests (Wave 5 A4)"
echo "========================================"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo ""
echo "[Case 1] Function is defined and exported"
if declare -F strip_plugin_quarantine_xattrs >/dev/null 2>&1; then
  ok "strip_plugin_quarantine_xattrs declared"
else
  nok "strip_plugin_quarantine_xattrs not declared"
fi

echo ""
echo "[Case 2] Clean tree: returns 0 stripped, exit 0"
mkdir -p "$T/fake-plugin/scripts" "$T/fake-plugin/hooks"
echo "#!/bin/bash" > "$T/fake-plugin/scripts/foo.sh"
echo "#!/bin/bash" > "$T/fake-plugin/hooks/bar.sh"
out=$(strip_plugin_quarantine_xattrs "$T/fake-plugin" 2>/dev/null)
rc=$?
if [ "$rc" = "0" ] && [ "$out" = "0" ]; then
  ok "clean tree returns 0 stripped"
else
  nok "clean tree returned rc=$rc count='$out'"
fi

echo ""
echo "[Case 3] Missing plugin root: no-op, returns 0"
out=$(strip_plugin_quarantine_xattrs "$T/does-not-exist" 2>/dev/null)
rc=$?
if [ "$rc" = "0" ] && [ "$out" = "0" ]; then
  ok "missing dir handled gracefully"
else
  nok "missing dir returned rc=$rc count='$out'"
fi

echo ""
echo "[Case 4] Platform detection"
case "$(uname -s)" in
  Darwin)
    if command -v xattr >/dev/null 2>&1; then
      # Set a real quarantine xattr and verify it's stripped.
      target="$T/fake-plugin/scripts/foo.sh"
      if xattr -w com.apple.quarantine "0083;00000000;Test;" "$target" 2>/dev/null; then
        out=$(strip_plugin_quarantine_xattrs "$T/fake-plugin" 2>/dev/null)
        if [ "$out" = "1" ]; then
          ok "macOS: stripped 1 quarantine xattr"
        else
          nok "macOS: expected 1 stripped, got '$out'"
        fi
        if ! xattr -p com.apple.quarantine "$target" >/dev/null 2>&1; then
          ok "macOS: xattr verifiably removed"
        else
          nok "macOS: xattr still present after strip"
        fi
      else
        echo "  SKIP: cannot set test xattr on this filesystem"
      fi
    else
      echo "  SKIP: xattr command not available"
    fi
    ;;
  *)
    out=$(strip_plugin_quarantine_xattrs "$T/fake-plugin" 2>/dev/null)
    if [ "$out" = "0" ]; then
      ok "non-Darwin: returns 0 (correct no-op)"
    else
      nok "non-Darwin: expected 0, got '$out'"
    fi
    ;;
esac

echo ""
echo "[Case 5] Default plugin_root (auto-derive from BASH_SOURCE)"
out=$(strip_plugin_quarantine_xattrs 2>/dev/null)
rc=$?
if [ "$rc" = "0" ]; then
  ok "default plugin_root resolves and runs cleanly"
else
  nok "default plugin_root failed rc=$rc"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
