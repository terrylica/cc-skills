#!/usr/bin/env bash
# empty-firing-detector.sh — Stop hook (v16.8.0).
#
# Detects sessions that fire and immediately call ScheduleWakeup without
# doing real work — the cumulative version of the pacing anti-pattern.
# Counts non-ScheduleWakeup tool invocations from the session transcript.
# If the count is 0 AND a ScheduleWakeup was emitted, logs an
# `empty_firing_detected` provenance event for doctor surfacing.
#
# Stdin payload (Claude Code Stop hook):
#   {
#     "session_id": "<uuid>",
#     "transcript_path": "/path/to/transcript.jsonl",
#     "stop_hook_active": <bool>,
#     "hook_event_name": "Stop"
#   }
#
# Exits 0 on all paths (Stop hooks must not block session shutdown).
# Optional sub-agent audit (Layer 5) gated by _PACING_SUBAGENT_AUDIT_ENABLED=1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROV_LIB="$SCRIPT_DIR/../scripts/provenance-lib.sh"
if [ -f "$PROV_LIB" ]; then
  # shellcheck source=/dev/null
  source "$PROV_LIB" 2>/dev/null || true
fi
export _PROV_AGENT="empty-firing-detector.sh"

PAYLOAD=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat 2>/dev/null || echo "")
fi
[ -z "$PAYLOAD" ] && exit 0

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || echo "")
TRANSCRIPT=$(echo "$PAYLOAD" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# Count tool_use entries scoped to THIS session (defensive; transcript may
# contain entries from prior session resumes after cwd-drift incidents).
SCHEDULE_WAKEUP_COUNT=0
OTHER_TOOL_COUNT=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  TOOL_NAME=$(echo "$line" | jq -r '
    select(.message.content[0].type == "tool_use" and .sessionId == "'"$SESSION_ID"'") |
    .message.content[0].name // ""
  ' 2>/dev/null || echo "")
  case "$TOOL_NAME" in
    "")              ;;
    "ScheduleWakeup") SCHEDULE_WAKEUP_COUNT=$((SCHEDULE_WAKEUP_COUNT + 1)) ;;
    *)                OTHER_TOOL_COUNT=$((OTHER_TOOL_COUNT + 1)) ;;
  esac
done < <(tail -200 "$TRANSCRIPT" 2>/dev/null)

# Empty firing: ScheduleWakeup called but no real work
if [ "$SCHEDULE_WAKEUP_COUNT" -gt 0 ] && [ "$OTHER_TOOL_COUNT" -eq 0 ]; then
  if command -v emit_provenance >/dev/null 2>&1; then
    emit_provenance "" "empty_firing_detected" \
      session_id="$SESSION_ID" \
      reason="session ended with ${SCHEDULE_WAKEUP_COUNT} ScheduleWakeup call(s) and 0 other tool invocations — empty firing" \
      decision="refused" 2>/dev/null || true
  fi
fi

# Layer 5 (opt-in): sub-agent audit when ScheduleWakeup happened in a
# session with very few real tool calls but technically not zero.
# Gated behind explicit env var so it doesn't burn tokens by default.
if [ "${_PACING_SUBAGENT_AUDIT_ENABLED:-0}" = "1" ] \
   && [ "$SCHEDULE_WAKEUP_COUNT" -gt 0 ] \
   && [ "$OTHER_TOOL_COUNT" -le 2 ] \
   && command -v claude >/dev/null 2>&1; then
  # Spawn a Haiku sub-agent in the background to grade this firing.
  # Output goes to a per-session audit log; never blocks Stop.
  AUDIT_LOG="$HOME/.claude/loops/.pacing-audits.jsonl"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  PROMPT=$(printf 'Analyze this Claude Code session ending. ScheduleWakeup count=%s, other tool count=%s, session=%s. Is this stupid idle waiting? Reply with one word VERDICT: STUPID or LEGIT, then one sentence why.' \
    "$SCHEDULE_WAKEUP_COUNT" "$OTHER_TOOL_COUNT" "$SESSION_ID")
  (
    nohup claude -p "$PROMPT" --model haiku >>"$AUDIT_LOG" 2>&1 &
  ) >/dev/null 2>&1 || true
fi

exit 0
