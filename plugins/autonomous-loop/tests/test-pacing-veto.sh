#!/usr/bin/env bash
# test-pacing-veto.sh — Tests for hooks/pacing-veto.sh anti-pacing enforcement.
# shellcheck disable=SC2329

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/pacing-veto.sh"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"
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

# Build a PreToolUse payload for ScheduleWakeup
mk_payload() {
  local delay="$1" reason="$2" tool="${3:-ScheduleWakeup}"
  jq -nc --arg t "$tool" --argjson d "$delay" --arg r "$reason" '{
    session_id: "test-session",
    tool_name: $t,
    tool_input: { delaySeconds: $d, reason: $r, prompt: "noop" },
    hook_event_name: "PreToolUse"
  }'
}

# Run the hook with a payload, capture stdout
run_hook() {
  local payload="$1"
  echo "$payload" | bash "$HOOK" 2>/dev/null || true
}

# Extract permissionDecision (or empty string if no JSON output)
extract_decision() {
  local out="$1"
  if [ -z "$out" ]; then echo ""; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo ""
}

# ===== Test 1: tool_name != ScheduleWakeup → allow (no output) =====
echo "Test 1: non-ScheduleWakeup tool → allow (no output)"
OUT=$(run_hook "$(mk_payload 300 'whatever' 'Bash')")
assert_eq "$OUT" "" "no JSON output for non-ScheduleWakeup tool"

# ===== Test 2: short delay (Tier 2) with valid reason → allow =====
echo ""
echo "Test 2: 120s delay with non-pacing reason → allow"
OUT=$(run_hook "$(mk_payload 120 'wait for the deploy to finish')")
DECISION=$(extract_decision "$OUT")
assert_eq "$DECISION" "" "no deny for 120s short delay"

# ===== Test 3: cache-miss zone (300-1199s) → deny =====
echo ""
echo "Test 3: 600s delay → deny (cache-miss zone)"
OUT=$(run_hook "$(mk_payload 600 'safety net for agents')")
DECISION=$(extract_decision "$OUT")
assert_eq "$DECISION" "deny" "deny for 600s cache-miss zone"
REASON=$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
case "$REASON" in
  *"cache-miss zone"*) assert_eq "ok" "ok" "denial reason mentions cache-miss zone" ;;
  *) assert_eq "$REASON" "*cache-miss zone*" "cache-miss in reason" ;;
esac

# ===== Test 4: Tier 3 (≥1200s) WITH pacing vocabulary → deny =====
echo ""
echo "Test 4: 1200s with token-budget reason → deny (pacing vocab)"
OUT=$(run_hook "$(mk_payload 1200 'self-paced wake; 1200s gives token-budget recovery')")
DECISION=$(extract_decision "$OUT")
assert_eq "$DECISION" "deny" "deny for 1200s with pacing vocabulary"
REASON=$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
case "$REASON" in
  *"pacing vocabulary"*) assert_eq "ok" "ok" "denial reason cites pacing vocabulary" ;;
  *) assert_eq "$REASON" "*pacing vocabulary*" "pacing vocab in reason" ;;
esac

# ===== Test 5: Tier 3 WITHOUT pacing vocabulary → allow (real blocker) =====
echo ""
echo "Test 5: 1800s with real external blocker → allow"
OUT=$(run_hook "$(mk_payload 1800 'wait for nightly cron job to deploy and run smoke tests on staging')")
DECISION=$(extract_decision "$OUT")
assert_eq "$DECISION" "" "allow 1800s when reason names real external blocker"

# ===== Test 6: Tier 0 (60s, the minimum) → allow =====
echo ""
echo "Test 6: 60s minimum delay → allow"
OUT=$(run_hook "$(mk_payload 60 'rate limit reset known to be 60s away')")
DECISION=$(extract_decision "$OUT")
assert_eq "$DECISION" "" "allow 60s minimum delay"

# ===== Test 7: provenance events emitted for both veto and allow =====
echo ""
echo "Test 7: provenance telemetry emitted"
VETOED=$(jq -sr '[.[] | select(.event == "pacing_vetoed")] | length' "$PROVENANCE_GLOBAL_FILE" 2>/dev/null || echo 0)
ALLOWED=$(jq -sr '[.[] | select(.event == "pacing_allowed")] | length' "$PROVENANCE_GLOBAL_FILE" 2>/dev/null || echo 0)
if [ "$VETOED" -ge 2 ]; then
  assert_eq "ok" "ok" "≥2 pacing_vetoed events ($VETOED)"
else
  assert_eq "$VETOED" ">=2" "veto telemetry"
fi
if [ "$ALLOWED" -ge 2 ]; then
  assert_eq "ok" "ok" "≥2 pacing_allowed events ($ALLOWED)"
else
  assert_eq "$ALLOWED" ">=2" "allow telemetry"
fi

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed."
exit 0
