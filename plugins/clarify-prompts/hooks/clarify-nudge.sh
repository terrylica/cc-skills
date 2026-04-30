#!/usr/bin/env bash
# Stop hook: nudge the main agent to invoke AskUserQuestion when ambiguity
# remains, UNLESS the most recent assistant turn already used AskUserQuestion
# OR this session is part of an autonomous-loop campaign.
#
# Behavior:
#   1. Loop guard         — honor stop_hook_active (Claude Code re-fire flag).
#   2. Subagent guard     — skip /agents/ transcripts (subagent stops).
#   3. Autonomous-loop    — skip if our session_id matches a registered loop
#                           owner, OR if cwd is a known loop contract dir.
#                           Reason: AskUserQuestion in a loop session would
#                           block the agent overnight — disastrous.
#   4. Already-asked      — if last assistant turn already invoked
#                           AskUserQuestion, don't double-nudge.
#   5. Otherwise          — emit "block" decision with a clarification reason.
#
# Failure mode: any unexpected error (missing transcript/registry/jq) fails
# open — exit 0 → normal stop. We never want this hook to wedge the agent.
set -uo pipefail

input=$(cat 2>/dev/null || true)
[[ -z "$input" ]] && exit 0

# 1. Loop guard.
if jq -e '.stop_hook_active // false' <<<"$input" >/dev/null 2>&1; then
    exit 0
fi

# 2. Subagent guard.
transcript_path=$(jq -r '.transcript_path // ""' <<<"$input" 2>/dev/null || echo "")
if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
    exit 0
fi
case "$transcript_path" in
    */agents/*) exit 0 ;;
esac

# 3. Autonomous-loop guard.
session_id=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null || echo "")
cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null || echo "")
registry_path="${LOOP_REGISTRY_PATH:-$HOME/.claude/loops/registry.json}"

if [[ -f "$registry_path" ]]; then
    # Match by session_id (precise — identifies a loop-owned session).
    if [[ -n "$session_id" ]]; then
        if jq -e --arg sid "$session_id" '
            .loops // [] | map(select(.owner_session_id == $sid)) | length > 0
        ' "$registry_path" >/dev/null 2>&1; then
            exit 0
        fi
    fi
    # Match by cwd (paranoid — in case session_id rotated mid-campaign).
    # contract_path is <cwd>/LOOP_CONTRACT.md, so dirname == cwd.
    if [[ -n "$cwd" ]]; then
        if jq -e --arg cwd "$cwd" '
            .loops // []
            | map(select((.contract_path | sub("/LOOP_CONTRACT\\.md$"; "")) == $cwd))
            | length > 0
        ' "$registry_path" >/dev/null 2>&1; then
            exit 0
        fi
    fi
fi

# 4. Already-asked guard.
last_assistant=$(jq -sc 'map(select(.type == "assistant")) | last // empty' \
    "$transcript_path" 2>/dev/null || echo "")

if [[ -n "$last_assistant" ]]; then
    if jq -e '
        .message.content // []
        | map(select(.type == "tool_use" and .name == "AskUserQuestion"))
        | length > 0
    ' <<<"$last_assistant" >/dev/null 2>&1; then
        exit 0
    fi
fi

# 5. Nudge. Keep the reason terse — Claude Code surfaces it back as a
#    "Stop hook error" line in the user-visible hook list. A long reason
#    crowds the already-long Stop hook output. ~15 words max.
jq -nc '{
    decision: "block",
    reason: "If user'"'"'s request had ambiguity, invoke AskUserQuestion (plain language, ≤12-char headers, 2-4 options); else stop next pass."
}'
