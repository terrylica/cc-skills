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

# Pacing vocabulary regex (case-insensitive). Expanded in v16.8.0 to cover
# creative pacing disguises observed in 2026-04-29 audit (settle, buffer,
# give time, let it, pause for, breath, recover).
PACING_RE='(token[- ]?budget|cache[- ]?warm|self[- ]?pac|cooldown|warm-?up|\<rest\>|\<pause\>|\<settle\>|buffer[- ]?time|give[- ]?time|let it|breath(er|e)|recover|wait a bit|let.*settle|brief[- ]?wait)'

# Minimum reason length for non-trivial delays — forces specificity.
# v16.8.0: empty or 1-char reasons like "x" no longer slip through.
# Used by Rule 4 below; declared at top for visibility.
# shellcheck disable=SC2034
MIN_REASON_LEN_FOR_LONG_WAIT=40

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

# Rule 0 (v16.9.0): nonsense delay (≤ 0). Claude Code clamps delay to
# [60, 3600] but defense-in-depth: refuse anything ≤ 0 explicitly.
if [ "$DELAY" -le 0 ]; then
  emit_deny "ScheduleWakeup delay=${DELAY}s is non-positive — meaningless. If no real blocker exists, drop to Tier 0 (in-turn continuation). If you want the minimum, use delay=60."
fi

# Rule 1: cache-miss zone (300-1199s)
if [ "$DELAY" -ge 300 ] && [ "$DELAY" -le 1199 ]; then
  emit_deny "ScheduleWakeup delay=${DELAY}s sits in the prompt-cache-miss zone (300-1199s) — worst of both: pay full cache miss without amortizing a long wait. Stay cache-warm with 60-270s OR commit to ≥1200s if the wait is genuinely long. See plugins/autonomous-loop/CLAUDE.md \"Waker Tier System\"."
fi

# Rule 2: ANY delay with pacing vocabulary in reason. Pacing is pacing
# regardless of duration; even a 60s "let it settle" is using the waker
# as pacing instead of Tier 0 in-turn continuation.
if echo "$REASON" | grep -qiE "$PACING_RE"; then
  emit_deny "ScheduleWakeup reason contains pacing vocabulary (token-budget / cache-warm / self-pacing / cooldown / rest / pause / settle / buffer / give time / let it / breather / recover) — these are pacing concerns, not external blockers. Drop to Tier 0 (in-turn continuation) if work is ready, OR name a specific external signal you're waiting for. See plugins/autonomous-loop/CLAUDE.md \"Anti-Patterns: Never use ScheduleWakeup as pacing\"."
fi

# Rule 3 (v16.8.0): empty/missing reason for any non-trivial delay.
if [ "$DELAY" -gt 60 ] && [ -z "$REASON" ]; then
  emit_deny "ScheduleWakeup with delay=${DELAY}s has no reason. Every wake must name a specific external signal you are waiting for. Drop to Tier 0 (in-turn) if no real blocker exists."
fi

# Rule 4 (v16.8.0): minimum reason length for delays ≥270s. Reasons like "x"
# or "wait for things" are not specific enough to verify a real blocker.
# Boundary inclusive — 270s is already deep into Tier 2 territory.
if [ "$DELAY" -ge 270 ]; then
  REASON_LEN=${#REASON}
  if [ "$REASON_LEN" -lt "$MIN_REASON_LEN_FOR_LONG_WAIT" ]; then
    emit_deny "ScheduleWakeup delay=${DELAY}s has reason of only ${REASON_LEN} chars (\"${REASON}\"). Long waits require specific external blockers — name the process, file, time-of-day, or condition you are waiting on (≥${MIN_REASON_LEN_FOR_LONG_WAIT} chars). Drop to Tier 0 if no real blocker."
  fi
fi

# Rule 4b (v16.8.0): vacuous-reason detector. Long reasons that contain
# vague filler words ("nothing", "anything", "things", "stuff", "whatever",
# "something") on long waits are usually masking pacing.
VACUOUS_RE='\<(nothing|anything|something|things|stuff|whatever)\>'
if [ "$DELAY" -gt 270 ] && echo "$REASON" | grep -qiwE "$VACUOUS_RE"; then
  emit_deny "ScheduleWakeup delay=${DELAY}s reason contains vacuous filler (nothing/anything/something/things/stuff/whatever): \"${REASON:0:120}\". Real external blockers have specific names — process, file, condition, or ETA. Drop to Tier 0."
fi

# Rule 5 (v16.8.0): contract-aware veto. If cwd is under a registered loop's
# contract dir, parse the Implementation Queue and check for ready work.
# Suspicious if queue has unchecked items but reason doesn't reference any.
PAYLOAD_CWD=$(echo "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")
if [ -n "$PAYLOAD_CWD" ] && [ "$DELAY" -gt 270 ]; then
  REGISTRY="$HOME/.claude/loops/registry.json"
  if [ -f "$REGISTRY" ]; then
    # Find the matching loop entry (cwd starts_with dirname(contract_path))
    CONTRACT_PATH=$(jq -r --arg cwd "$PAYLOAD_CWD" '
      .loops[] |
      select(((.contract_path | split("/") | .[:-1] | join("/")) + "/") as $prefix |
             $cwd | startswith($prefix)) |
      .contract_path
    ' "$REGISTRY" 2>/dev/null | head -1)
    if [ -n "$CONTRACT_PATH" ] && [ -f "$CONTRACT_PATH" ]; then
      # Count unchecked items in Implementation Queue section
      QUEUE_OPEN=$(awk '
        /^## Implementation Queue/{in_section=1; next}
        /^## /{in_section=0}
        in_section && /^- \[ \]/{count++}
        END{print count+0}
      ' "$CONTRACT_PATH" 2>/dev/null)
      if [ "${QUEUE_OPEN:-0}" -gt 0 ]; then
        # Queue has work — does the reason reference any of those items?
        # Heuristic: extract first 6 words of each open item, check if any appear in reason
        QUEUE_HINT=$(awk '
          /^## Implementation Queue/{in_section=1; next}
          /^## /{in_section=0}
          in_section && /^- \[ \]/{print substr($0, 7, 80)}
        ' "$CONTRACT_PATH" 2>/dev/null | head -3)
        emit_deny "ScheduleWakeup delay=${DELAY}s but the loop contract at ${CONTRACT_PATH} has ${QUEUE_OPEN} unchecked Implementation Queue items. Drop to Tier 0 (in-turn continuation) and work the queue. First items: ${QUEUE_HINT//$'\n'/ | }"
      fi
    fi
  fi
fi

# Allowed — log telemetry
if command -v emit_provenance >/dev/null 2>&1; then
  emit_provenance "" "pacing_allowed" \
    session_id="$SESSION_ID" \
    reason="delay=${DELAY}s passed pacing-veto checks" \
    decision="proceeded" 2>/dev/null || true
fi

exit 0
