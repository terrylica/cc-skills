#!/usr/bin/env bash
# test-reclaim-suggestion.sh — Wave 5 A6 fuzzy-match suggestion harness
#
# Verifies suggest_closest_loops:
#   1. Substring match (typo on a real slug → suggests it)
#   2. Prefix match (first 3 chars match a registered slug)
#   3. Empty registry → no suggestions, no error
#   4. Missing registry file → no suggestions, no error
#   5. Suggests up to N results (max_results respected)
#   6. AL- prefix is normalized away

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
echo "Reclaim Suggestion Tests (Wave 5 A6)"
echo "========================================"

T=$(mktemp -d); export HOME="$T/home"
mkdir -p "$HOME/.claude/loops"
trap 'rm -rf "$T"' EXIT

REG="$HOME/.claude/loops/registry.json"

echo ""
echo "[Case 1] Empty registry → no suggestions"
echo '{"schema_version": 1, "loops": []}' > "$REG"
out=$(suggest_closest_loops "anything" "$REG" 2>/dev/null || echo "")
if [ -z "$out" ]; then
  ok "empty registry returns no suggestions"
else
  nok "empty registry returned: '$out'"
fi

echo ""
echo "[Case 2] Missing registry → no error"
out=$(suggest_closest_loops "x" "$T/missing.json" 2>/dev/null || echo "")
if [ -z "$out" ]; then
  ok "missing registry handled gracefully"
else
  nok "missing registry returned: '$out'"
fi

# Build a registry with 3 distinct campaigns.
cat > "$REG" <<'EOF'
{
  "schema_version": 1,
  "loops": [
    {"loop_id": "111111111111", "campaign_slug": "odb-research", "short_hash": "a1b2c3"},
    {"loop_id": "222222222222", "campaign_slug": "flaky-ci-watcher", "short_hash": "d4e5f6"},
    {"loop_id": "333333333333", "campaign_slug": "telemetry-cleanup", "short_hash": "789abc"}
  ]
}
EOF

echo ""
echo "[Case 3] Substring match: typo of 'odb' suggests odb-research"
out=$(suggest_closest_loops "odb" "$REG" 2>/dev/null)
if echo "$out" | grep -q "odb-research"; then
  ok "substring 'odb' suggests odb-research"
else
  nok "substring 'odb' did not suggest odb-research; got: $out"
fi

echo ""
echo "[Case 4] AL-prefix is normalized: 'AL-flaky' suggests flaky-ci-watcher"
out=$(suggest_closest_loops "AL-flaky" "$REG" 2>/dev/null)
if echo "$out" | grep -q "flaky-ci-watcher"; then
  ok "AL-prefix normalized; 'AL-flaky' matches flaky-ci-watcher"
else
  nok "AL-prefix not normalized; got: $out"
fi

echo ""
echo "[Case 5] Loop_id substring: '11111' suggests the matching loop"
out=$(suggest_closest_loops "11111" "$REG" 2>/dev/null)
if echo "$out" | grep -q "111111111111"; then
  ok "loop_id substring '11111' suggests 111111111111"
else
  nok "loop_id substring did not match; got: $out"
fi

echo ""
echo "[Case 6] max_results=2 returns at most 2 lines"
# Add 4 more loops with the prefix 'odb' to force >2 candidates.
cat > "$REG" <<'EOF'
{
  "schema_version": 1,
  "loops": [
    {"loop_id": "aaaaaaaaaaa1", "campaign_slug": "odb-one", "short_hash": "111111"},
    {"loop_id": "aaaaaaaaaaa2", "campaign_slug": "odb-two", "short_hash": "222222"},
    {"loop_id": "aaaaaaaaaaa3", "campaign_slug": "odb-three", "short_hash": "333333"},
    {"loop_id": "aaaaaaaaaaa4", "campaign_slug": "odb-four", "short_hash": "444444"}
  ]
}
EOF
out=$(suggest_closest_loops "odb" "$REG" 2 2>/dev/null)
line_count=$(echo "$out" | grep -c "AL-")
if [ "$line_count" = "2" ]; then
  ok "max_results=2 returned exactly 2 suggestions"
else
  nok "max_results=2 returned $line_count lines"
fi

echo ""
echo "[Case 7] Empty input → no suggestions, no error"
out=$(suggest_closest_loops "" "$REG" 2>/dev/null || echo "")
if [ -z "$out" ]; then
  ok "empty input handled gracefully"
else
  nok "empty input returned: '$out'"
fi

echo ""
echo "[Case 8] Output format: 'AL-<slug>--<hash>  (<loop_id>)'"
cat > "$REG" <<'EOF'
{
  "schema_version": 1,
  "loops": [
    {"loop_id": "aaaaaaaaaaaa", "campaign_slug": "test-campaign", "short_hash": "deadbe"}
  ]
}
EOF
out=$(suggest_closest_loops "test" "$REG" 2>/dev/null)
if echo "$out" | grep -qE "AL-test-campaign--deadbe[[:space:]]+\(aaaaaaaaaaaa\)"; then
  ok "output format matches 'AL-<slug>--<hash>  (<loop_id>)'"
else
  nok "format wrong; got: $out"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
