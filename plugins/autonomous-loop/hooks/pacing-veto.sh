#!/usr/bin/env bash
# pacing-veto.sh — PreToolUse hook that denies pacing-disguised ScheduleWakeup
# calls. References plugins/autonomous-loop/CLAUDE.md anti-pattern: "Wakers
# are not pacing". Documentation alone wasn't enforcing it; this hook is.
#
# Stdin payload (Claude Code PreToolUse hook):
#   {
#     "session_id": "<uuid>",
#     "tool_name": "ScheduleWakeup",
#     "tool_input": { "delaySeconds": <int>, "prompt": "...", "reason": "..." },
#     "hook_event_name": "PreToolUse"
#   }
#
# Decisions:
#   - tool_name != ScheduleWakeup → allow (default; no output, exit 0)
#   - delay ∈ [300, 1199]         → DENY (prompt-cache-miss zone; worst of both)
#   - delay > 270 AND reason matches pacing vocabulary → DENY
#   - otherwise                    → allow + log pacing_allowed provenance event
#
# All paths exit 0; deny is communicated via `permissionDecision` JSON output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source provenance for telemetry (best-effort; absent = no logging)
PROV_LIB="$SCRIPT_DIR/../scripts/provenance-lib.sh"
if [ -f "$PROV_LIB" ]; then
  # shellcheck source=/dev/null
  source "$PROV_LIB" 2>/dev/null || true
fi
export _PROV_AGENT="pacing-veto.sh"

# Read stdin payload
PAYLOAD=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat 2>/dev/null || echo "")
fi
[ -z "$PAYLOAD" ] && exit 0

TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ "$TOOL_NAME" != "ScheduleWakeup" ]; then
  exit 0
fi

DELAY=$(echo "$PAYLOAD" | jq -r '.tool_input.delaySeconds // 0' 2>/dev/null || echo 0)
REASON=$(echo "$PAYLOAD" | jq -r '.tool_input.reason // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || echo "")

# Sanitize delay to integer
case "$DELAY" in
  '' | *[!0-9]*) DELAY=0 ;;
esac

# Pacing vocabulary regex (case-insensitive)
PACING_RE='(token[- ]?budget|cache[- ]?warm|self[- ]?pac|cooldown|warm-?up|\<rest\>|\<pause\>)'

emit_deny() {
  local why="$1"
  if command -v emit_provenance >/dev/null 2>&1; then
    emit_provenance "" "pacing_vetoed" \
      session_id="$SESSION_ID" \
      reason="delay=${DELAY}s; rule=$why; original_reason=${REASON:0:160}" \
      decision="refused" 2>/dev/null || true
  fi
  jq -nc --arg msg "$why" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $msg
    }
  }' 2>/dev/null
  exit 0
}

# Rule 1: cache-miss zone (300-1199s)
if [ "$DELAY" -ge 300 ] && [ "$DELAY" -le 1199 ]; then
  emit_deny "ScheduleWakeup delay=${DELAY}s sits in the prompt-cache-miss zone (300-1199s) — worst of both: pay full cache miss without amortizing a long wait. Stay cache-warm with 60-270s OR commit to ≥1200s if the wait is genuinely long. See plugins/autonomous-loop/CLAUDE.md \"Waker Tier System\"."
fi

# Rule 2: long delay with pacing-vocab in reason
if [ "$DELAY" -gt 270 ] && echo "$REASON" | grep -qiE "$PACING_RE"; then
  emit_deny "ScheduleWakeup reason contains pacing vocabulary (token-budget / cache-warm / self-pacing / cooldown / rest / pause) — these are pacing concerns, not external blockers. Drop to Tier 0 (in-turn continuation) if work is ready, OR name a specific external signal you're waiting for. See plugins/autonomous-loop/CLAUDE.md \"Anti-Patterns: Never use ScheduleWakeup as pacing\"."
fi

# Allowed — log telemetry
if command -v emit_provenance >/dev/null 2>&1; then
  emit_provenance "" "pacing_allowed" \
    session_id="$SESSION_ID" \
    reason="delay=${DELAY}s passed pacing-veto checks" \
    decision="proceeded" 2>/dev/null || true
fi

exit 0
