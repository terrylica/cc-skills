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

# Wave 6.1: canonicalize TEMP_DIR before any test creating real on-disk
# state_dirs that need to match the encoding heal-self.sh applies.
TEMP_DIR=$(cd "$TEMP_DIR" && pwd -P)

# ===== Wave 6.1 helper: v2-layout pending-bind fixture with live JSONL =====
# auto-bind needs (1) a v2 contract on disk, (2) created_at_cwd in registry,
# (3) a JSONL file at ~/.claude/projects/<encoded-cwd>/<uuid>.jsonl with
# mtime within the 5-minute window heal-self uses for liveness detection.
put_v2_pending_bind() {
  local loop_id="$1" age_s="$2" recent_jsonl_age_min="${3:-1}"
  local proj_root="$TEMP_DIR/v2-$loop_id"
  local contract_dir="$proj_root/.autoloop/heal-test--abcdef"
  local state_dir="$contract_dir/state"
  mkdir -p "$state_dir/revision-log" "$contract_dir"
  echo "---" >"$contract_dir/CONTRACT.md"
  local now_us start_us
  now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))")
  start_us=$((now_us - age_s * 1000000))

  # Encode project_root for ~/.claude/projects/<encoded>/ — the same
  # "/" → "-" mapping heal-self.sh applies internally.
  local encoded="${proj_root//\//-}"
  local proj_jsonl_dir="$HOME/.claude/projects/$encoded"
  mkdir -p "$proj_jsonl_dir"
  local fake_session="11111111-2222-3333-4444-555555555555"
  echo '{"type":"user","content":"hi"}' >"$proj_jsonl_dir/$fake_session.jsonl"
  if [ "$recent_jsonl_age_min" -gt 0 ]; then
    touch -t "$(date -v-"${recent_jsonl_age_min}M" +%Y%m%d%H%M.%S 2>/dev/null \
                || date -d "-${recent_jsonl_age_min} minutes" +%Y%m%d%H%M.%S)" \
              "$proj_jsonl_dir/$fake_session.jsonl"
  fi

  local entry
  entry=$(jq -nc \
    --arg loop_id "$loop_id" \
    --arg contract_path "$contract_dir/CONTRACT.md" \
    --arg state_dir "$state_dir" \
    --arg created_at_cwd "$proj_root" \
    --arg owner_session_id "pending-bind" \
    --arg owner_start_time_us "$start_us" \
    --argjson generation 0 \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, created_at_cwd: $created_at_cwd, owner_session_id: $owner_session_id, owner_start_time_us: $owner_start_time_us, generation: $generation}')
  [ ! -f "$CLAUDE_LOOPS_REGISTRY" ] && echo '{"schema_version": 1, "loops": []}' >"$CLAUDE_LOOPS_REGISTRY"
  jq --argjson e "$entry" '.loops += [$e]' "$CLAUDE_LOOPS_REGISTRY" >"$CLAUDE_LOOPS_REGISTRY.tmp" && mv "$CLAUDE_LOOPS_REGISTRY.tmp" "$CLAUDE_LOOPS_REGISTRY"
  echo "$fake_session"
}

# ===== Test 4 (Wave 6.1): auto-bind via JSONL-mtime detection =====
echo ""
echo "Test 4 (Wave 6.1): pending-bind with live JSONL → auto-bound, NOT archived"
reset
EXPECTED_SID=$(put_v2_pending_bind "555555555555" 7200 1)  # 2h old + 1min-fresh JSONL
bash "$HEAL" 2>/dev/null
SID_AFTER=$(jq -r '.loops[] | select(.loop_id=="555555555555") | .owner_session_id' "$CLAUDE_LOOPS_REGISTRY" 2>/dev/null)
assert_eq "$SID_AFTER" "$EXPECTED_SID" "auto-bind patched owner_session_id to live session UUID"
REMAINING=$(jq -r '.loops | length' "$CLAUDE_LOOPS_REGISTRY")
assert_eq "$REMAINING" "1" "auto-bound entry NOT archived (rescued before archival)"
EVENT=$( { jq -sr '.[] | select(.event=="heal_auto_bound" and .loop_id=="555555555555") | .event' "$PROVENANCE_GLOBAL_FILE" 2>/dev/null || true; } | head -1 || true)
assert_eq "$EVENT" "heal_auto_bound" "heal_auto_bound provenance event emitted"

# ===== Test 5 (Wave 6.1): heartbeat.bound_cwd seeded after auto-bind =====
echo ""
echo "Test 5 (Wave 6.1): heartbeat.bound_cwd seeded so next waker firing can proceed"
reset
put_v2_pending_bind "777777777777" 7200 1 >/dev/null
bash "$HEAL" 2>/dev/null
STATE_DIR=$(jq -r '.loops[] | select(.loop_id=="777777777777") | .state_dir' "$CLAUDE_LOOPS_REGISTRY")
HB="$STATE_DIR/heartbeat.json"
if [ -f "$HB" ]; then
  BOUND=$(jq -r '.bound_cwd // ""' "$HB")
  EXPECTED_DIR=$(jq -r '.loops[] | select(.loop_id=="777777777777") | .contract_path' "$CLAUDE_LOOPS_REGISTRY" | xargs dirname)
  assert_eq "$BOUND" "$EXPECTED_DIR" "heartbeat.bound_cwd seeded to contract_dir"
else
  echo "  ✗ FAIL: heartbeat.json was not created at $HB"
  FAIL=$((FAIL + 1))
fi

# ===== Test 6 (Wave 6.1): pending-bind without JSONL still archives =====
echo ""
echo "Test 6 (Wave 6.1): pending-bind with no live JSONL falls through to archival"
reset
put_loop "666666666666" "pending-bind" 7200
bash "$HEAL" 2>/dev/null
ARCHIVED_LINES=$(wc -l <"$HOME/.claude/loops/registry.archive.jsonl" 2>/dev/null | tr -d ' ')
assert_eq "$ARCHIVED_LINES" "1" "no live JSONL → archival proceeds (fallback path intact)"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
