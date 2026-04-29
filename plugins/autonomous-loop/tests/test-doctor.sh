#!/usr/bin/env bash
# test-doctor.sh — Tests for doctor-lib.sh (DOC-01, DOC-02).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops" "$HOME/Library/LaunchAgents"
export CLAUDE_LOOPS_REGISTRY="$HOME/.claude/loops/registry.json"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"
export DOCTOR_PENDING_BIND_THRESHOLD_S=3600

# launchctl shim
STUB_BIN="$TEMP_DIR/stub-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/launchctl" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  list)
    [ -f "$HOME/.claude/loops/.fake-launchctl-list" ] && cat "$HOME/.claude/loops/.fake-launchctl-list"
    ;;
  bootout) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$STUB_BIN/launchctl"
export PATH="$STUB_BIN:$PATH"

trap 'rm -rf "$TEMP_DIR"' EXIT

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/doctor-lib.sh"

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
  rm -rf "$HOME/.claude/loops" "$HOME/Library/LaunchAgents"
  mkdir -p "$HOME/.claude/loops" "$HOME/Library/LaunchAgents"
}

put_loop() {
  local loop_id="$1" owner_sid="$2" age_s="${3:-0}" contract_exists="${4:-yes}"
  local contract_dir="$TEMP_DIR/proj-$loop_id"
  mkdir -p "$contract_dir/.loop-state/$loop_id"
  local contract="$contract_dir/LOOP_CONTRACT.md"
  if [ "$contract_exists" = "yes" ]; then
    echo "---" >"$contract"
  fi
  local now_us start_us
  now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))")
  start_us=$((now_us - age_s * 1000000))
  local entry
  entry=$(jq -nc \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract" \
    --arg state_dir "$contract_dir/.loop-state/$loop_id/" \
    --arg owner_session_id "$owner_sid" \
    --arg owner_pid "$$" \
    --arg owner_start_time_us "$start_us" \
    --argjson generation 0 \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, generation: $generation}')
  if [ ! -f "$CLAUDE_LOOPS_REGISTRY" ]; then
    echo '{"schema_version": 1, "loops": []}' >"$CLAUDE_LOOPS_REGISTRY"
  fi
  jq --argjson e "$entry" '.loops += [$e]' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
  echo "$contract_dir"
}

# ===== Test 1: clean state → all GREEN =====
echo "Test 1: clean state → GREEN"
reset
SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
put_loop "111111111111" "$SID" 60 "yes" >/dev/null
JSON=$(loop_doctor_report --json 2>/dev/null)
VERDICT=$(echo "$JSON" | jq -r '.loops[0].verdict // "MISSING"')
assert_eq "$VERDICT" "GREEN" "verdict GREEN for fresh loop"

# ===== Test 2: zombie launchctl entry → RED =====
echo ""
echo "Test 2: zombie launchctl → RED"
reset
put_loop "222222222222" "$SID" 60 "yes" >/dev/null
echo "1234	0	com.user.claude.loop.zzzzzzzzzzzz" >"$HOME/.claude/loops/.fake-launchctl-list"
JSON=$(loop_doctor_report --json 2>/dev/null)
ZOMBIE=$(echo "$JSON" | jq -r '.loops[] | select(.kind == "zombie_launchctl") | .verdict')
assert_eq "$ZOMBIE" "RED" "zombie_launchctl entry detected as RED"
LABEL_HINT=$(echo "$JSON" | jq -r '.loops[] | select(.kind == "zombie_launchctl") | .issues[0]' 2>/dev/null)
case "$LABEL_HINT" in
  *bootout*) assert_eq "ok" "ok" "remediation hint mentions bootout" ;;
  *) assert_eq "$LABEL_HINT" "*bootout*" "bootout in hint" ;;
esac

# ===== Test 3: pending-bind >1h → YELLOW =====
echo ""
echo "Test 3: stale pending-bind → YELLOW"
reset
echo "" >"$HOME/.claude/loops/.fake-launchctl-list"  # no zombies
put_loop "333333333333" "pending-bind" 7200 "yes" >/dev/null
JSON=$(loop_doctor_report --json 2>/dev/null)
VERDICT=$(echo "$JSON" | jq -r '.loops[0].verdict')
assert_eq "$VERDICT" "YELLOW" "stale pending-bind = YELLOW"

# ===== Test 4: --json output is valid JSON with loops array =====
echo ""
echo "Test 4: --json output structure"
reset
put_loop "444444444444" "$SID" 60 "yes" >/dev/null
put_loop "555555555555" "pending-bind" 7200 "yes" >/dev/null
JSON=$(loop_doctor_report --json 2>/dev/null)
HAS_LOOPS=$(echo "$JSON" | jq -r 'has("loops")')
assert_eq "$HAS_LOOPS" "true" "JSON has loops field"
LOOP_COUNT=$(echo "$JSON" | jq -r '.loops | length')
assert_eq "$LOOP_COUNT" "2" "JSON contains 2 loop entries"
HAS_TS=$(echo "$JSON" | jq -r 'has("generated_at_iso")')
assert_eq "$HAS_TS" "true" "JSON has generated_at_iso timestamp"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
