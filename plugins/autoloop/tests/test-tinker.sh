#!/usr/bin/env bash
# test-tinker.sh — Tests for tinker-lib.sh diagnose + repair flows.
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DOCTOR_LIB="$PLUGIN_DIR/scripts/tinker-lib.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
mkdir -p "$HOME/Library/LaunchAgents"
export AUTOLOOP_PLUGIN_ROOT="$PLUGIN_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0
assert_eq() {
  if [ "$1" = "$2" ]; then
    echo "  ✓ PASS: $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $3"
    echo "    expected: $1"
    echo "    actual:   $2"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if echo "$2" | grep -qF "$1"; then
    echo "  ✓ PASS: $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $3"
    echo "    expected substring: $1"
    echo "    actual: $2"
    FAIL=$((FAIL + 1))
  fi
}

# Source the lib (also pulls in registry-lib, hook-install-lib, launchd-lib)
# shellcheck source=/dev/null
source "$DOCTOR_LIB"

# ============================================================================
# Test group 1 — diagnose_loop on missing-everything substrate
# ============================================================================
echo "Test 1: diagnose_loop on empty registry (loop_id not registered)"
LOOP_ID="aaaaaaaaaaaa"
echo '{"loops":[]}' > "$HOME/.claude/loops/registry.json"

DIAG=$(diagnose_loop "$LOOP_ID" 2>/dev/null)
RP=$(echo "$DIAG" | jq -r '.registry_present')
assert_eq "false" "$RP" "registry_present is false when loop not registered"

# ============================================================================
# Test group 2 — F1 detection (registered loop, no plist)
# ============================================================================
echo "Test 2: F1_missing_plist detected when registry has entry but no plist"
LOOP_ID="bbbbbbbbbbbb"
NOW_US="$(python3 -c 'import time; print(int(time.time()*1_000_000))')"
SESSION_UUID="11111111-2222-3333-4444-555555555555"
mkdir -p "$HOME/.claude/loops"
jq -n \
  --arg loop_id "$LOOP_ID" \
  --arg sid "$SESSION_UUID" \
  --arg now_us "$NOW_US" \
  --arg state_dir "$TEMP_DIR/state" \
  --arg contract "$TEMP_DIR/CONTRACT.md" \
  '{loops: [{loop_id: $loop_id, contract_path: $contract, state_dir: $state_dir,
    owner_session_id: $sid, owner_pid: 0, owner_start_time_us: $now_us,
    launchd_label: ("com.user.claude.loop." + $loop_id),
    started_at_us: $now_us, expected_cadence_seconds: 1800, generation: 0,
    bound_cwd: "", last_heartbeat_us: $now_us}]}' \
  > "$HOME/.claude/loops/registry.json"
mkdir -p "$TEMP_DIR/state"
touch "$TEMP_DIR/CONTRACT.md"

DIAG=$(diagnose_loop "$LOOP_ID" 2>/dev/null)
MODES=$(echo "$DIAG" | jq -r '.failure_modes | map(. == "F1_missing_plist") | any')
assert_eq "true" "$MODES" "F1_missing_plist detected"

# ============================================================================
# Test group 3 — F4 false-positive guard (waker_path_stale only when actual file missing)
# ============================================================================
echo "Test 3: F4 NOT flagged when plist points at a different but existing waker"
# Create a fake "marketplace" runner+waker pair and a plist pointing at it.
ALT_WAKER="$TEMP_DIR/alt_waker.sh"
ALT_RUNNER="$TEMP_DIR/state/claude-loop-fake"
echo '#!/bin/bash' > "$ALT_WAKER" && chmod +x "$ALT_WAKER"
{
  echo '#!/bin/bash'
  echo "exec \"$ALT_WAKER\" \"\$1\""
} > "$ALT_RUNNER" && chmod +x "$ALT_RUNNER"

cat > "$HOME/Library/LaunchAgents/com.user.claude.loop.${LOOP_ID}.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.user.claude.loop.${LOOP_ID}</string>
	<key>ProgramArguments</key><array><string>${ALT_RUNNER}</string></array>
	<key>StartInterval</key><integer>900</integer>
</dict>
</plist>
EOF

DIAG=$(diagnose_loop "$LOOP_ID" 2>/dev/null)
F4=$(echo "$DIAG" | jq -r '.waker_path_stale')
assert_eq "false" "$F4" "F4 NOT flagged when runner + waker both exist on disk"

# ============================================================================
# Test group 4 — F4 detection when runner missing
# ============================================================================
echo "Test 4: F4 flagged when runner deleted"
rm -f "$ALT_RUNNER"
DIAG=$(diagnose_loop "$LOOP_ID" 2>/dev/null)
F4=$(echo "$DIAG" | jq -r '.waker_path_stale')
assert_eq "true" "$F4" "F4 flagged when runner missing on disk"

# ============================================================================
# Test group 5 — F2 detection (no autoloop hooks installed)
# ============================================================================
echo "Test 5: F2_missing_hooks detected when settings.json is empty"
echo '{}' > "$HOME/.claude/settings.json"
DIAG=$(diagnose_loop "$LOOP_ID" 2>/dev/null)
F2=$(echo "$DIAG" | jq -r '.failure_modes | map(. == "F2_missing_hooks") | any')
assert_eq "true" "$F2" "F2_missing_hooks detected on empty settings"

# ============================================================================
# Test group 6 — F3 detection (pending-bind beyond grace)
# ============================================================================
echo "Test 6: F3_pending_bind_stale when owner_session_id stuck > grace window"
LOOP_ID="cccccccccccc"
# Set started_at_us to 10 minutes ago so age > 5min default grace
TEN_MIN_AGO_US=$(python3 -c "import time; print(int((time.time() - 600) * 1_000_000))")
jq --arg id "$LOOP_ID" --arg started_us "$TEN_MIN_AGO_US" \
   --arg state_dir "$TEMP_DIR/state" --arg contract "$TEMP_DIR/CONTRACT.md" \
  '.loops += [{
    loop_id: $id, contract_path: $contract, state_dir: $state_dir,
    owner_session_id: "pending-bind", owner_pid: 0,
    owner_start_time_us: $started_us, launchd_label: ("com.user.claude.loop." + $id),
    started_at_us: $started_us, expected_cadence_seconds: 1800, generation: 0,
    bound_cwd: "", last_heartbeat_us: $started_us
  }]' "$HOME/.claude/loops/registry.json" > "$TEMP_DIR/r.json" && \
  mv "$TEMP_DIR/r.json" "$HOME/.claude/loops/registry.json"

DIAG=$(diagnose_loop "$LOOP_ID" 2>/dev/null)
F3=$(echo "$DIAG" | jq -r '.failure_modes | map(. == "F3_pending_bind_stale") | any')
assert_eq "true" "$F3" "F3_pending_bind_stale detected after grace window"

# ============================================================================
# Test group 7 — repair_pending_bind_owner_session refuses to overwrite real UUID
# ============================================================================
echo "Test 7: repair_pending_bind_owner_session refuses overwrite of bound UUID"
NEW_UUID="99999999-aaaa-bbbb-cccc-dddddddddddd"
OUT=$(repair_pending_bind_owner_session "bbbbbbbbbbbb" "$NEW_UUID" 2>&1)
CURRENT_AFTER=$(jq -r --arg id "bbbbbbbbbbbb" \
  '.loops[] | select(.loop_id == $id) | .owner_session_id' \
  "$HOME/.claude/loops/registry.json")
# Should be unchanged from the original bound UUID
assert_eq "$SESSION_UUID" "$CURRENT_AFTER" "bound UUID preserved (no overwrite)"
assert_contains "refusing to overwrite" "$OUT" "diagnostic message printed"

# ============================================================================
# Test group 8 — repair_pending_bind_owner_session DOES patch pending-bind
# ============================================================================
echo "Test 8: repair_pending_bind_owner_session patches pending-bind to UUID"
repair_pending_bind_owner_session "cccccccccccc" "$NEW_UUID" >/dev/null 2>&1
PATCHED=$(jq -r --arg id "cccccccccccc" \
  '.loops[] | select(.loop_id == $id) | .owner_session_id' \
  "$HOME/.claude/loops/registry.json")
assert_eq "$NEW_UUID" "$PATCHED" "pending-bind patched to new UUID"

# ============================================================================
# Summary
# ============================================================================
echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
