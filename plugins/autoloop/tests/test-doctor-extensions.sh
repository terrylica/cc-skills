#!/usr/bin/env bash
# test-doctor-extensions.sh — W2.1 doctor harness
#
# Verifies the three new fleet-level checks added to loop_doctor_report:
#   1. registry_corrupt detection (RED in --json fleet object; RED line in human output)
#   2. .hook-errors.log surfacing (count + 3 newest samples in --json)
#   3. rapid-reclaim signal (loops_with_rapid_reclaim_24h)
#
# Each case isolates HOME under mktemp -d so it doesn't read the user's real
# registry or provenance files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/doctor-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

setup_isolated_home() {
  local t
  t=$(mktemp -d)
  echo "$t"
}

echo "========================================"
echo "Doctor Extensions Tests (W2.1)"
echo "========================================"

# ---- Case 1: registry_corrupt detection ----
echo ""
echo "[Case 1] Corrupt registry surfaces as RED + fleet.registry_corrupt=true"
T1=$(setup_isolated_home)
export HOME="$T1/home"
mkdir -p "$HOME/.claude/loops"
echo "}{ NOT JSON" > "$HOME/.claude/loops/registry.json"

# Human output should print the RED line.
human=$(loop_doctor_report 2>&1 || true)
if echo "$human" | grep -q "RED:.*registry.json is NOT valid JSON"; then
  ok "human output flags corrupt registry as RED"
else
  nok "human output missed RED warning. Got: $(echo "$human" | head -1)"
fi

# JSON output should set fleet.registry_corrupt=true.
json=$(loop_doctor_report --json 2>/dev/null || echo '{}')
if echo "$json" | jq -e '.fleet.registry_corrupt == true' >/dev/null 2>&1; then
  ok "JSON output: fleet.registry_corrupt == true"
else
  nok "JSON output did not set fleet.registry_corrupt=true. Got: $(echo "$json" | jq -c '.fleet // {}')"
fi
rm -rf "$T1"

# ---- Case 2: hook_errors_recent_1h count + samples ----
echo ""
echo "[Case 2] .hook-errors.log entries in last 1h are surfaced"
T2=$(setup_isolated_home)
export HOME="$T2/home"
mkdir -p "$HOME/.claude/loops"
echo '{"loops": [], "schema_version": 1}' > "$HOME/.claude/loops/registry.json"

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
for i in 1 2 3 4 5; do
  jq -nc --arg ts "$NOW_ISO" --arg val "bogus-$i" \
    "{ts:\$ts, kind:\"validation_reject\", field:\"session_id\", value_truncated:\$val, pid:\"$$\", extra:{}}" \
    >> "$HOME/.claude/loops/.hook-errors.log"
done
# Plus one OLD entry (>1h ago) that should NOT be counted.
jq -nc --arg ts "2020-01-01T00:00:00Z" \
  '{ts:$ts, kind:"validation_reject", field:"session_id", value_truncated:"old", pid:"0", extra:{}}' \
  >> "$HOME/.claude/loops/.hook-errors.log"

json=$(loop_doctor_report --json 2>/dev/null || echo '{}')
recent=$(echo "$json" | jq -r '.fleet.hook_errors_recent_1h // 0')
samples_count=$(echo "$json" | jq '.fleet.hook_errors_samples | length' 2>/dev/null || echo 0)

if [ "$recent" = "5" ]; then
  ok "fleet.hook_errors_recent_1h == 5 (old entry excluded)"
else
  nok "expected 5, got '$recent'"
fi

if [ "$samples_count" = "3" ]; then
  ok "fleet.hook_errors_samples has 3 entries (newest)"
else
  nok "expected 3 samples, got $samples_count"
fi

# Sanity: the samples should not include the 2020 entry.
old_in_samples=$(echo "$json" | jq -r '[.fleet.hook_errors_samples[] | select(.value_truncated == "old")] | length' 2>/dev/null)
if [ "$old_in_samples" = "0" ]; then
  ok "old entry not in samples"
else
  nok "old entry leaked into samples"
fi
rm -rf "$T2"

# ---- Case 3: rapid_reclaim_count surfaces loops with >3 superseded files in 24h ----
echo ""
echo "[Case 3] >3 superseded-*.json files in 24h → loops_with_rapid_reclaim_24h"
T3=$(setup_isolated_home)
export HOME="$T3/home"
mkdir -p "$HOME/.claude/loops"
SD="$HOME/loop-state/abcdef012345"
mkdir -p "$SD/revision-log"
# 4 fresh superseded files
for i in 1 2 3 4; do
  touch "$SD/revision-log/superseded-session-$i.json"
done

cat > "$HOME/.claude/loops/registry.json" <<EOF
{
  "loops": [
    {"loop_id":"abcdef012345","contract_path":"$SD/CONTRACT.md","state_dir":"$SD","owner_pid":1,"owner_session_id":"x","owner_start_time_us":1577836800000000,"generation":4}
  ],
  "schema_version": 1
}
EOF
touch "$SD/CONTRACT.md"

json=$(loop_doctor_report --json 2>/dev/null || echo '{}')
rrc=$(echo "$json" | jq -r '.fleet.loops_with_rapid_reclaim_24h // 0')
if [ "$rrc" = "1" ]; then
  ok "fleet.loops_with_rapid_reclaim_24h == 1"
else
  nok "expected 1 rapid-reclaim loop, got '$rrc'"
fi
rm -rf "$T3"

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
