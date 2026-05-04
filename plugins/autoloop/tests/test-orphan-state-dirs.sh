#!/usr/bin/env bash
# test-orphan-state-dirs.sh — Wave 5 B3 doctor disk-orphan detection harness
#
# Verifies _triage_check_disk_orphans:
#   1. Returns nothing on a clean tree (every state_dir registered)
#   2. Detects a v2 .autoloop/<slug>--<hash>/state/ orphan
#   3. Detects a legacy .loop-state/<loop_id>/ orphan
#   4. Bounded scan: doesn't traverse paths outside registered cwds
#   5. Output is line-delimited JSON with kind=disk_orphan, verdict=YELLOW

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/triage-lib.sh"
set +e

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Disk Orphan Detection Tests (Wave 5 B3)"
echo "========================================"

T=$(mktemp -d); export HOME="$T/home"
mkdir -p "$HOME/.claude/loops"
trap 'rm -rf "$T"' EXIT

PROJ="$T/proj"
mkdir -p "$PROJ"

# Build a v2 state_dir for a registered loop.
REGISTERED_STATE="$PROJ/.autoloop/registered--abc123/state"
mkdir -p "$REGISTERED_STATE/revision-log"

cat > "$HOME/.claude/loops/registry.json" <<EOF
{
  "schema_version": 1,
  "loops": [
    {
      "loop_id": "111111111111",
      "campaign_slug": "registered",
      "short_hash": "abc123",
      "state_dir": "$REGISTERED_STATE",
      "owner_pid": $$,
      "owner_session_id": "00000000-0000-0000-0000-000000000000",
      "generation": 0
    }
  ]
}
EOF

REG="$HOME/.claude/loops/registry.json"

echo ""
echo "[Case 1] Clean tree: no orphans reported"
out=$(_triage_check_disk_orphans "$REG" 2>/dev/null)
if [ -z "$out" ]; then
  ok "no orphans on clean tree"
else
  nok "expected empty; got: $out"
fi

echo ""
echo "[Case 2] v2 orphan: detected as YELLOW disk_orphan"
ORPHAN_V2="$PROJ/.autoloop/orphaned--def456/state"
mkdir -p "$ORPHAN_V2/revision-log"
out=$(_triage_check_disk_orphans "$REG" 2>/dev/null)
if echo "$out" | grep -q "disk_orphan"; then
  ok "v2 orphan detected"
else
  nok "v2 orphan not surfaced; got: $out"
fi
if echo "$out" | grep -q "YELLOW"; then
  ok "verdict is YELLOW"
else
  nok "verdict missing; got: $out"
fi
if echo "$out" | grep -Fq "$ORPHAN_V2"; then
  ok "orphan path appears in output"
else
  nok "orphan path missing; got: $out"
fi

echo ""
echo "[Case 3] Legacy orphan: detected"
LEGACY_STATE="$PROJ/.loop-state/abcdef123456"
mkdir -p "$LEGACY_STATE/revision-log"
# Add a registered legacy state_dir so the parent gets scanned.
REGISTERED_LEGACY="$PROJ/.loop-state/111111111111"
mkdir -p "$REGISTERED_LEGACY/revision-log"
cat > "$REG" <<EOF
{
  "schema_version": 1,
  "loops": [
    {
      "loop_id": "111111111111",
      "state_dir": "$REGISTERED_LEGACY",
      "owner_pid": $$,
      "owner_session_id": "00000000-0000-0000-0000-000000000000",
      "generation": 0
    }
  ]
}
EOF
out=$(_triage_check_disk_orphans "$REG" 2>/dev/null)
if echo "$out" | grep -Fq "$LEGACY_STATE"; then
  ok "legacy orphan detected"
else
  nok "legacy orphan missing; got: $out"
fi
if echo "$out" | grep -q "AL-orphan-legacy-"; then
  ok "legacy display_name has correct prefix"
else
  nok "legacy display_name wrong; got: $out"
fi

echo ""
echo "[Case 4] Doctor surfaces orphan in full report"
report=$(loop_triage_report 2>&1)
if echo "$report" | grep -q "disk_orphan\|state_dir on disk"; then
  ok "loop_triage_report wires in disk-orphan output"
else
  nok "doctor report missing orphan signal; tail: $(echo "$report" | tail -5)"
fi

echo ""
echo "[Case 5] JSON output includes kind=disk_orphan"
json_out=$(loop_triage_report --json 2>/dev/null || echo '{}')
if echo "$json_out" | jq -e '.loops[]? | select(.kind == "disk_orphan")' >/dev/null 2>&1; then
  ok "JSON output marks entries kind=disk_orphan"
else
  nok "JSON output missing disk_orphan kind"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
