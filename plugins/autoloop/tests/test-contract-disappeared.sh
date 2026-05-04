#!/usr/bin/env bash
# test-contract-disappeared.sh — Wave 5 B1 contract-disappeared harness
#
# Verifies write_heartbeat:
#   1. Succeeds when contract_path exists in registry and on disk
#   2. Refuses + returns 1 when registry has contract_path but file is gone
#   3. Logs a clear error pointing at git restore / clean / rm
#   4. Appends notifications.jsonl entry on first detection
#   5. AUTOLOOP_NO_NOTIFY=1 suppresses the notification side effect
#   6. Empty contract_path in registry (legacy) does NOT trip the check

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh"
set +e  # state-lib sourced from registry-lib pulls in -e; capture failures manually

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Contract-Disappeared Tests (Wave 5 B1)"
echo "========================================"

T=$(mktemp -d); export HOME="$T/home"
mkdir -p "$HOME/.claude/loops"
trap 'rm -rf "$T"' EXIT

LOOP_ID="aabbccddeeff"
CONTRACT="$T/.autoloop/test--abc123/CONTRACT.md"
STATE_DIR="$T/.autoloop/test--abc123/state"
mkdir -p "$STATE_DIR/revision-log"
mkdir -p "$(dirname "$CONTRACT")"
echo "# contract" > "$CONTRACT"

# Build a registry entry pointing at the contract.
cat > "$HOME/.claude/loops/registry.json" <<EOF
{
  "schema_version": 1,
  "loops": [
    {
      "loop_id": "$LOOP_ID",
      "campaign_slug": "test",
      "short_hash": "abc123",
      "contract_path": "$CONTRACT",
      "state_dir": "$STATE_DIR",
      "owner_pid": $$,
      "owner_session_id": "00000000-0000-0000-0000-000000000000",
      "owner_start_time_us": 0,
      "generation": 0
    }
  ]
}
EOF

echo ""
echo "[Case 1] Contract present: write_heartbeat succeeds"
out=$(write_heartbeat "$LOOP_ID" "00000000-0000-0000-0000-000000000000" 1 2>&1)
rc=$?
if [ "$rc" = "0" ]; then
  ok "write_heartbeat succeeds when contract is present"
else
  nok "write_heartbeat returned rc=$rc; output: $out"
fi
if [ -f "$STATE_DIR/heartbeat.json" ]; then
  ok "heartbeat.json was written"
else
  nok "heartbeat.json missing"
fi

echo ""
echo "[Case 2] Contract gone: write_heartbeat refuses + returns 1"
rm -f "$CONTRACT"
out=$(write_heartbeat "$LOOP_ID" "00000000-0000-0000-0000-000000000000" 2 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
  ok "write_heartbeat returns rc=1 on missing contract"
else
  nok "write_heartbeat returned rc=$rc; output: $out"
fi
if echo "$out" | grep -q "contract file" && echo "$out" | grep -q "disappeared"; then
  ok "error mentions 'contract file disappeared'"
else
  nok "diagnostic missing; got: $out"
fi
if echo "$out" | grep -q "git restore"; then
  ok "error suggests likely cause (git restore / clean / rm)"
else
  nok "error doesn't suggest cause; got: $out"
fi
if echo "$out" | grep -q "/autoloop:triage"; then
  ok "error points at recovery via /autoloop:triage"
else
  nok "error doesn't point at recovery; got: $out"
fi

echo ""
echo "[Case 3] Notification appended on detection"
NOTIF="$HOME/.claude/loops/.notifications.jsonl"
if [ -f "$NOTIF" ]; then
  if grep -q "contract_disappeared" "$NOTIF"; then
    ok "notifications.jsonl contains contract_disappeared entry"
  else
    nok "notifications.jsonl present but missing contract_disappeared kind"
  fi
else
  nok "notifications.jsonl was NOT created"
fi

echo ""
echo "[Case 4] AUTOLOOP_NO_NOTIFY=1 suppresses notification side effect"
rm -f "$NOTIF"
export AUTOLOOP_NO_NOTIFY=1
write_heartbeat "$LOOP_ID" "00000000-0000-0000-0000-000000000000" 3 >/dev/null 2>&1 || true
unset AUTOLOOP_NO_NOTIFY
if [ ! -f "$NOTIF" ]; then
  ok "AUTOLOOP_NO_NOTIFY=1 suppressed notification append"
else
  nok "notification appended despite AUTOLOOP_NO_NOTIFY=1"
fi

echo ""
echo "[Case 5] Legacy registry without contract_path: check is skipped"
# Replace registry with a legacy-shape entry that has no contract_path.
LOOP_ID_LEGACY="ddeeffaabbcc"
LEGACY_STATE="$T/legacy-state"
mkdir -p "$LEGACY_STATE/revision-log"
cat > "$HOME/.claude/loops/registry.json" <<EOF
{
  "schema_version": 1,
  "loops": [
    {
      "loop_id": "$LOOP_ID_LEGACY",
      "state_dir": "$LEGACY_STATE",
      "owner_pid": $$,
      "owner_session_id": "00000000-0000-0000-0000-000000000000",
      "owner_start_time_us": 0,
      "generation": 0
    }
  ]
}
EOF
out=$(write_heartbeat "$LOOP_ID_LEGACY" "00000000-0000-0000-0000-000000000000" 1 2>&1)
rc=$?
if [ "$rc" = "0" ]; then
  ok "legacy entry without contract_path skips the check"
else
  nok "legacy entry tripped the check; rc=$rc out=$out"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
