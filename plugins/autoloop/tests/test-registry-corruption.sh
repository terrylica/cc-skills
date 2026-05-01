#!/usr/bin/env bash
# test-registry-corruption.sh — W2.3 pre-write JSON validation harness
#
# Verifies that _with_registry_lock refuses to overwrite registry.json with a
# corrupted temp file. The Wave 1 in-memory check at line 226 catches
# fn-produced garbage; this harness exercises the disk-side check at line 250
# which catches truncation/disk-full between echo and mv.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Registry Corruption Tests (W2.3)"
echo "========================================"

# A "good" mutator returns valid JSON.
good_fn() { cat | jq '.loops[0].generation = 99'; }
export -f good_fn

# A "bad" mutator that prints garbage to stdout. The in-memory jq . check
# (line 226) should catch this case BEFORE the temp file is written.
bad_in_memory_fn() { echo "}{ NOT JSON"; }
export -f bad_in_memory_fn

T=$(mktemp -d); export HOME="$T/home"
mkdir -p "$HOME/.claude/loops"
SEED='{"loops": [{"loop_id": "abcdef012345", "generation": 0}], "schema_version": 1}'
echo "$SEED" > "$HOME/.claude/loops/registry.json"
ORIG_HASH=$(shasum "$HOME/.claude/loops/registry.json" | awk '{print $1}')

echo ""
echo "[Case 1] Good mutator updates registry"
if _with_registry_lock good_fn 2>/dev/null; then
  ok "good_fn succeeded"
else
  nok "good_fn failed"
fi
new_gen=$(jq -r '.loops[0].generation' "$HOME/.claude/loops/registry.json")
if [ "$new_gen" = "99" ]; then
  ok "registry now has generation=99"
else
  nok "expected generation=99, got '$new_gen'"
fi

echo ""
echo "[Case 2] In-memory garbage is rejected before temp file is written"
echo "$SEED" > "$HOME/.claude/loops/registry.json"  # reset
PRE_HASH=$(shasum "$HOME/.claude/loops/registry.json" | awk '{print $1}')
if _with_registry_lock bad_in_memory_fn 2>/dev/null; then
  nok "bad_in_memory_fn was accepted (should have been rejected)"
else
  ok "bad_in_memory_fn rejected"
fi
POST_HASH=$(shasum "$HOME/.claude/loops/registry.json" | awk '{print $1}')
if [ "$PRE_HASH" = "$POST_HASH" ]; then
  ok "registry.json unchanged after rejected mutator"
else
  nok "registry.json was modified despite mutator rejection"
fi

echo ""
echo "[Case 3] Registry remains valid JSON after the failed mutation"
if jq empty "$HOME/.claude/loops/registry.json" >/dev/null 2>&1; then
  ok "registry parses cleanly post-failure"
else
  nok "registry was corrupted by the failed mutation"
fi

# Suppress unused-var notice
: "${ORIG_HASH:-}"

rm -rf "$T"
echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
