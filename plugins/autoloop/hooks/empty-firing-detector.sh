#!/usr/bin/env bash
# empty-firing-detector.sh — Stop hook (v16.8.0).
#
# Detects sessions that fire and immediately call ScheduleWakeup without
# doing real work — the cumulative version of the pacing anti-pattern.
# Counts non-ScheduleWakeup tool invocations from the session transcript.
# If the count is 0 AND a ScheduleWakeup was emitted, logs an
# `empty_firing_detected` provenance event for tinker surfacing.
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

# Iter-34 bash-5.2-patsub-replacement-defense (see heartbeat-tick.sh for
# full rationale): disable bash 5.2+ `&`-as-backreference in pattern
# substitution. `|| true` makes it a graceful no-op on bash <5.2.
shopt -u patsub_replacement 2>/dev/null || true

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

# Perf (iter-29 payload-decode-tsv-batch-empty-firing-detector): same TSV-
# batched-jq pattern as iter-25/26/28 — one jq spawn instead of two. Saves
# ~10ms cold-start per Stop hook firing.
IFS=$'\t' read -r SESSION_ID TRANSCRIPT <<< "$(
  echo "$PAYLOAD" | jq -r '"\(.session_id // "")\t\(.transcript_path // "")"' 2>/dev/null \
    || printf '\t'
)"

[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# Count tool_use entries scoped to THIS session (defensive; transcript may
# contain entries from prior session resumes after cwd-drift incidents).
#
# Perf (iter-29 transcript-tool-name-extraction-single-jq-streaming-pass):
# Pre-iter-29 this loop spawned ONE jq process per transcript line — up to
# 200 lines × ~7-10ms cold-start = ~1500-2000ms of pure jq overhead per
# Stop hook firing (user-facing session-end latency).
#
# The replacement uses jq's native JSONL streaming: jq reads stdin line by
# line by default (no `-s`), applies the filter to each, and emits one line
# of output per matching entry. The bash loop then counts via the same
# case statement, but with ZERO subprocess spawns inside the loop. Saves
# ~199 jq cold-starts on a typical 200-line transcript.
#
# Also corrected: pre-iter-29 the filter embedded $SESSION_ID directly into
# the jq string (`.sessionId == "'"$SESSION_ID"'"`). This relied on shell
# quoting for safety — anyone who manages to inject `"` into SESSION_ID
# (very unlikely given UUID validation upstream, but still) could escape
# the filter. The `--arg sid` form is safer and clearer.
SCHEDULE_WAKEUP_COUNT=0
OTHER_TOOL_COUNT=0
TOOL_NAMES=$(tail -200 "$TRANSCRIPT" 2>/dev/null | jq -r --arg sid "$SESSION_ID" '
  select(.message.content[0].type == "tool_use" and .sessionId == $sid) |
  .message.content[0].name // ""
' 2>/dev/null || echo "")
while IFS= read -r tool_name; do
  case "$tool_name" in
    "")              ;;
    "ScheduleWakeup") SCHEDULE_WAKEUP_COUNT=$((SCHEDULE_WAKEUP_COUNT + 1)) ;;
    *)                OTHER_TOOL_COUNT=$((OTHER_TOOL_COUNT + 1)) ;;
  esac
done <<< "$TOOL_NAMES"

# Empty firing: ScheduleWakeup called but no real work.
# Wave 6.4: decision="flagged" — a Stop hook never blocks Claude Code (it
# can't refuse anything; Stop fires after the session is already winding
# down). The historical "refused" value mis-categorized this event in
# provenance forever-after — every post-mortem that filtered for actual
# refusals (spawn_refused_*, bind_skipped_*) had to special-case
# empty_firing_detected. "flagged" is the right verb: this is a passive
# audit note for an operator's attention, not a blocked operation.
if [ "$SCHEDULE_WAKEUP_COUNT" -gt 0 ] && [ "$OTHER_TOOL_COUNT" -eq 0 ]; then
  if command -v emit_provenance >/dev/null 2>&1; then
    emit_provenance "" "empty_firing_detected" \
      session_id="$SESSION_ID" \
      reason="session ended with ${SCHEDULE_WAKEUP_COUNT} ScheduleWakeup call(s) and 0 other tool invocations — empty firing" \
      decision="flagged" 2>/dev/null || true
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
