#!/usr/bin/env bash
# test-plist-collision.sh — Tests for generate_plist label collision detection (WAKE-03).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/loops"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"

# Stub launchctl by prepending a directory to PATH containing a fake launchctl.
# The fake's behavior is controlled by a state file.
STUB_BIN="$TEMP_DIR/stub-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/launchctl" <<'STUB'
#!/usr/bin/env bash
# Fake launchctl. Reads ~/.claude/loops/.fake-launchctl-list to decide what
# `launchctl list` reports. `bootout` is a no-op.
case "${1:-}" in
  list)
    if [ -f "$HOME/.claude/loops/.fake-launchctl-list" ]; then
      cat "$HOME/.claude/loops/.fake-launchctl-list"
    fi
    ;;
  bootout)
    # Simulate a successful bootout
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$STUB_BIN/launchctl"
export PATH="$STUB_BIN:$PATH"

trap 'rm -rf "$TEMP_DIR"' EXIT

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/launchd-lib.sh"

PASS=0
FAIL=0
assert_eq() {
  if [ "$1" = "$2" ]; then
    echo "  ✓ PASS: $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $3 (expected=$2 actual=$1)"
    FAIL=$((FAIL + 1))
  fi
}

reset() {
  rm -rf "$HOME/Library/LaunchAgents" "$HOME/.claude/loops"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/loops"
  rm -rf "$TEMP_DIR"/state-*
}

# Use a fake waker_script path (file existence not strictly required for plist write)
WAKER_PATH="$PLUGIN_DIR/scripts/waker.sh"

# ===== Test 1: no existing plist → clean write =====
echo "Test 1: no existing plist → clean write"
reset
LOOP_ID="aaa111aaa111"
STATE_DIR="$TEMP_DIR/state-$LOOP_ID"
generate_plist "$LOOP_ID" "$STATE_DIR" "$WAKER_PATH" "300" 2>/dev/null
if [ -f "$STATE_DIR/waker.plist" ]; then
  assert_eq "exists" "exists" "waker.plist generated"
else
  assert_eq "missing" "exists" "waker.plist"
fi
if [ -d "$STATE_DIR/orphans" ]; then
  ORPHAN_COUNT=$(find "$STATE_DIR/orphans" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
else
  ORPHAN_COUNT=0
fi
assert_eq "$ORPHAN_COUNT" "0" "no orphans dir created"

# ===== Test 2: stale plist file (no launchctl entry) → archived =====
echo ""
echo "Test 2: stale plist → archived"
reset
LOOP_ID="bbb222bbb222"
STATE_DIR="$TEMP_DIR/state-$LOOP_ID"
LABEL="com.user.claude.loop.$LOOP_ID"
mkdir -p "$STATE_DIR"
echo "<plist>old</plist>" >"$HOME/Library/LaunchAgents/$LABEL.plist"
generate_plist "$LOOP_ID" "$STATE_DIR" "$WAKER_PATH" "300" 2>/dev/null
ARCHIVED=$(find "$STATE_DIR/orphans" -name "$LABEL.plist" 2>/dev/null | head -1)
if [ -n "$ARCHIVED" ]; then
  assert_eq "archived" "archived" "stale plist archived to orphans"
else
  assert_eq "missing" "archived" "stale plist"
fi
EVT=$(jq -sr '.[] | select(.event=="label_collision_resolved" and .loop_id=="bbb222bbb222") | .event' "$PROVENANCE_GLOBAL_FILE" 2>/dev/null | head -1)
assert_eq "$EVT" "label_collision_resolved" "label_collision_resolved provenance event"

# ===== Test 3: launchctl shows label → bootout + archive =====
echo ""
echo "Test 3: launchctl shows label → bootout + archive"
reset
LOOP_ID="ccc333ccc333"
STATE_DIR="$TEMP_DIR/state-$LOOP_ID"
LABEL="com.user.claude.loop.$LOOP_ID"
# Fake launchctl list output: PID STATUS LABEL (3 columns)
echo "1234	0	$LABEL" >"$HOME/.claude/loops/.fake-launchctl-list"
echo "<plist>loaded</plist>" >"$HOME/Library/LaunchAgents/$LABEL.plist"
generate_plist "$LOOP_ID" "$STATE_DIR" "$WAKER_PATH" "300" 2>/dev/null
ARCHIVED=$(find "$STATE_DIR/orphans" -name "$LABEL.plist" 2>/dev/null | head -1)
if [ -n "$ARCHIVED" ]; then
  assert_eq "archived" "archived" "loaded-plist archived to orphans"
else
  assert_eq "missing" "archived" "loaded-plist"
fi
EVT3=$(jq -sr '.[] | select(.event=="label_collision_resolved" and .loop_id=="ccc333ccc333") | .event' "$PROVENANCE_GLOBAL_FILE" 2>/dev/null | head -1)
assert_eq "$EVT3" "label_collision_resolved" "label_collision_resolved emitted (loaded case)"
# New plist exists
if [ -f "$STATE_DIR/waker.plist" ]; then
  assert_eq "exists" "exists" "fresh waker.plist regenerated"
else
  assert_eq "missing" "exists" "fresh waker.plist"
fi

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
