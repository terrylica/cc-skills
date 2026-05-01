#!/usr/bin/env bash
# test-machine-id-and-rotation.sh — Wave 4 hardening harness
#
# Verifies:
#   1. current_machine_id is stable + 12-hex
#   2. register_loop stamps machine_id on new entries
#   3. doctor flags entries with foreign machine_id as RED
#   4. rotate_jsonl_if_large rotates when over threshold, leaves alone when under

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
source "$PLUGIN_DIR/scripts/doctor-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Wave 4 Hardening Tests"
echo "========================================"

T=$(mktemp -d); export HOME="$T/home"
mkdir -p "$HOME/.claude/loops"
trap 'rm -rf "$T"' EXIT

echo ""
echo "[Group 1] current_machine_id"
mid1=$(current_machine_id)
mid2=$(current_machine_id)
if [ "$mid1" = "$mid2" ] && [[ "$mid1" =~ ^[0-9a-f]{12}$ ]]; then
  ok "machine_id is stable + 12-hex"
else
  nok "machine_id unstable or wrong format (got '$mid1' / '$mid2')"
fi

echo ""
echo "[Group 2] register_loop stamps machine_id"
ENTRY=$(jq -nc --arg id "abcdef012345" --arg cp "/tmp/x" --arg sd "/tmp/x-state" \
  --arg owner_pid "1" --arg sid "x" --arg start "1" --arg sat "1" \
  --arg cad "1500" --arg gen "0" --arg label "com.user.claude.loop.abcdef012345" \
  '{loop_id:$id, contract_path:$cp, state_dir:$sd, owner_session_id:$sid,
    owner_pid:($owner_pid|tonumber), owner_start_time_us:($start|tonumber),
    started_at_us:($sat|tonumber), expected_cadence_seconds:($cad|tonumber),
    generation:($gen|tonumber), launchd_label:$label}')

set +e  # allow potential nonzero from register_loop without aborting
register_loop "$ENTRY" >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" = "0" ]; then
  ok "register_loop succeeded"
else
  nok "register_loop failed (rc=$rc)"
fi

stamped_mid=$(jq -r '.loops[0].machine_id // ""' "$HOME/.claude/loops/registry.json")
if [ "$stamped_mid" = "$mid1" ]; then
  ok "machine_id stamped on new entry"
else
  nok "machine_id missing or wrong (got '$stamped_mid')"
fi

echo ""
echo "[Group 3] doctor flags foreign machine_id"
SD="$HOME/loop-state/foreignloop00"
mkdir -p "$SD"
cat > "$HOME/.claude/loops/registry.json" <<EOF
{
  "loops": [
    {"loop_id":"foreignloop0","campaign_slug":"foreign","short_hash":"a1b2c3","contract_path":"$SD/CONTRACT.md","state_dir":"$SD","owner_pid":99999,"owner_session_id":"x","owner_start_time_us":1577836800000000,"generation":0,"machine_id":"deadbeefcafe"}
  ],
  "schema_version": 1
}
EOF
touch "$SD/CONTRACT.md"

set +e
out=$(loop_doctor_report 2>&1)
set -e
if echo "$out" | grep -q "RED: foreign machine_id"; then
  ok "doctor surfaces foreign machine_id as RED"
else
  nok "doctor did not flag foreign machine_id (got: $(echo "$out" | tail -3))"
fi

# JSON output should classify as foreign_machine kind
set +e
json_out=$(loop_doctor_report --json 2>/dev/null || echo '{}')
set -e
if echo "$json_out" | jq -e '.loops[] | select(.kind == "foreign_machine")' >/dev/null 2>&1; then
  ok "JSON output marks entry kind=foreign_machine"
else
  nok "JSON output does not mark kind=foreign_machine"
fi

echo ""
echo "[Group 4] rotate_jsonl_if_large"
LOG="$HOME/test-rotate.log"
# Small file should not rotate
echo "small content" > "$LOG"
rotate_jsonl_if_large "$LOG"
if [ -f "$LOG" ] && [ ! -f "$LOG.1" ]; then
  ok "small file not rotated"
else
  nok "small file was rotated"
fi

# 11MB file should rotate
dd if=/dev/zero of="$LOG" bs=1024 count=11264 2>/dev/null
rotate_jsonl_if_large "$LOG"
if [ -f "$LOG" ] && [ -f "$LOG.1" ]; then
  size=$(stat -f '%z' "$LOG" 2>/dev/null || stat -c '%s' "$LOG")
  if [ "$size" = "0" ]; then
    ok "large file rotated (current is empty, .1 holds prior content)"
  else
    nok "large file rotated but new file not empty (size=$size)"
  fi
else
  nok "large file did not rotate properly"
fi

# Custom threshold (1KB)
LOG2="$HOME/test-rotate2.log"
echo "exactly larger than 100 bytes................................................................................." > "$LOG2"
rotate_jsonl_if_large "$LOG2" 100 2
if [ -f "$LOG2.1" ]; then
  ok "custom threshold (100 bytes) triggers rotation"
else
  nok "custom threshold did not trigger"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
