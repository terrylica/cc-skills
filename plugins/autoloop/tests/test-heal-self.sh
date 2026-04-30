#!/usr/bin/env bash
# test-heal-self.sh — Tests for heal-self.sh idempotent migration (DOC-03).
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HEAL="$PLUGIN_DIR/scripts/heal-self.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
export CLAUDE_LOOPS_REGISTRY="$HOME/.claude/loops/registry.json"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"
export HEAL_STALE_THRESHOLD_S=3600
trap 'rm -rf "$TEMP_DIR"' EXIT

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
  rm -rf "$HOME/.claude/loops"
  mkdir -p "$HOME/.claude/loops"
}

put_loop() {
  local loop_id="$1" owner_sid="$2" age_s="$3"
  local now_us start_us
  now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))")
  start_us=$((now_us - age_s * 1000000))
  local entry
  entry=$(jq -nc \
    --arg loop_id "$loop_id" \
    --arg contract_path "/tmp/$loop_id/LOOP_CONTRACT.md" \
    --arg state_dir "/tmp/$loop_id/.loop-state/$loop_id/" \
    --arg owner_session_id "$owner_sid" \
    --arg owner_start_time_us "$start_us" \
    --argjson generation 0 \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, owner_start_time_us: $owner_start_time_us, generation: $generation}')
  if [ ! -f "$CLAUDE_LOOPS_REGISTRY" ]; then
    echo '{"schema_version": 1, "loops": []}' >"$CLAUDE_LOOPS_REGISTRY"
  fi
  jq --argjson e "$entry" '.loops += [$e]' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
}

# ===== Test 1: stale pending-bind >1h archived =====
echo "Test 1: stale pending-bind >1h archived"
reset
put_loop "111111111111" "pending-bind" 7200
put_loop "222222222222" "uuid-real-session" 60  # not stale; should be preserved
bash "$HEAL" 2>/dev/null
ARCHIVED_LINES=$(wc -l <"$HOME/.claude/loops/registry.archive.jsonl" 2>/dev/null | tr -d ' ')
assert_eq "$ARCHIVED_LINES" "1" "1 entry archived to registry.archive.jsonl"
ARCHIVED_ID=$(jq -r '.loop_id' "$HOME/.claude/loops/registry.archive.jsonl")
assert_eq "$ARCHIVED_ID" "111111111111" "correct entry archived (the stale one)"
REMAINING=$(jq -r '.loops | length' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$REMAINING" "1" "registry has 1 remaining loop"
SURVIVOR=$(jq -r '.loops[0].loop_id' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$SURVIVOR" "222222222222" "live session preserved"

# ===== Test 2: recent pending-bind <1h preserved =====
echo ""
echo "Test 2: recent pending-bind <1h preserved"
reset
put_loop "333333333333" "pending-bind" 60  # 60s old
bash "$HEAL" 2>/dev/null
REMAINING=$(jq -r '.loops | length' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$REMAINING" "1" "recent pending-bind not archived"

# ===== Test 3: idempotent — second invocation no-op (gated by hash) =====
echo ""
echo "Test 3: idempotent — second invocation is no-op"
reset
put_loop "444444444444" "pending-bind" 7200
bash "$HEAL" 2>/dev/null
COUNT_AFTER_FIRST=$(wc -l <"$HOME/.claude/loops/registry.archive.jsonl" 2>/dev/null | tr -d ' ')
# Run again — registry hash should match → no-op
bash "$HEAL" 2>/dev/null
COUNT_AFTER_SECOND=$(wc -l <"$HOME/.claude/loops/registry.archive.jsonl" 2>/dev/null | tr -d ' ')
assert_eq "$COUNT_AFTER_SECOND" "$COUNT_AFTER_FIRST" "idempotent: archive count unchanged on 2nd call"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
