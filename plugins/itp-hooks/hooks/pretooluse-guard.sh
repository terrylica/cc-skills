#!/usr/bin/env bash
#
# PreToolUse guard for itp-hooks plugin.
# Pure bash + jq implementation for minimal startup overhead (~5ms vs ~100ms Python)
#
# Hard blocks (exit 2 - cannot be bypassed):
# 1. Manual ASCII art in markdown without graph-easy source block
#
# Note: graph-easy CLI usage is handled by PostToolUse reminder instead of
# PreToolUse blocking, since blocking can be bypassed with permissions and
# transcript-based skill detection has false positives.
#

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract fields using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only process Write/Edit for ASCII art check
if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
    exit 0
fi

#--- Write/Edit tool: Check for manual ASCII art ---
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Only check markdown files
if [[ ! "$FILE_PATH" =~ \.(md|mdx)$ ]]; then
    exit 0
fi

# Exempt plan files from ASCII art blocking (configurable via mise)
# Plan files are AI-generated during Claude's planning phase and may contain
# diagrams that don't have graph-easy source blocks yet
#
# SSoT: ~/.config/mise/config.toml [env] section
# Set ITP_HOOKS_EXEMPT_PLANS="true" to exempt, "false" to enforce blocking
if [[ "$FILE_PATH" =~ /\.claude/plans/.*\.md$ ]]; then
    # Check if variable is explicitly set (mise SSoT)
    if [[ -z "${ITP_HOOKS_EXEMPT_PLANS+x}" ]]; then
        # Variable not set - warn but default to exempt for backwards compatibility
        echo "[itp-hooks] WARN: ITP_HOOKS_EXEMPT_PLANS not set. Defaulting to exempt plan files." >&2
        echo "[itp-hooks] Configure in ~/.config/mise/config.toml: ITP_HOOKS_EXEMPT_PLANS = \"true\"" >&2
        exit 0
    elif [[ "$ITP_HOOKS_EXEMPT_PLANS" == "true" ]]; then
        # Explicitly enabled via mise
        exit 0
    fi
    # If set to "false" or other value, continue to check for ASCII art
fi

# Check if graph-easy was recently used in this session
# ADR: 2025-12-09-itp-hooks-workflow-aware-graph-easy
STATE_DIR="$HOME/.claude/hooks/state"
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

if [[ -n "$SESSION_ID" && -f "$STATE_DIR/${SESSION_ID}.graph-easy-used" ]]; then
    FLAG_TIMESTAMP=$(cat "$STATE_DIR/${SESSION_ID}.graph-easy-used")
    CURRENT_TIME=$(date +%s)
    FLAG_AGE=$((CURRENT_TIME - FLAG_TIMESTAMP))

    if [[ $FLAG_AGE -lt 30 ]]; then
        # graph-easy was used within 30 seconds, allow this write
        # Consume the flag (one-shot) to prevent abuse
        rm "$STATE_DIR/${SESSION_ID}.graph-easy-used"
        exit 0
    fi

    # Flag expired, clean up
    rm "$STATE_DIR/${SESSION_ID}.graph-easy-used"
fi

# Get content to check
if [[ "$TOOL_NAME" == "Edit" ]]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')
else
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')
fi

# Check for box-drawing characters (Unicode block)
BOX_CHARS='[┌─│┐└┘├┤┬┴┼╌╎║═╔╗╚╝╠╣╦╩╬┏┓┗┛┃━╭╮╯╰]'

if echo "$CONTENT" | grep -q "$BOX_CHARS"; then
    # Allow if graph-easy source block present
    if echo "$CONTENT" | grep -q '<summary>graph-easy source</summary>'; then
        exit 0
    fi

    # Count box characters - allow small edits (< 10 chars)
    BOX_COUNT=$(echo "$CONTENT" | grep -o "$BOX_CHARS" | wc -l | tr -d ' ')
    if [[ "$BOX_COUNT" -lt 10 ]]; then
        exit 0
    fi

    # EXIT CODE 2 = Hard block (cannot be bypassed by any permission mode)
    echo "BLOCKED: Manual ASCII diagrams detected in markdown without source block." >&2
    echo "" >&2
    echo "Required: Use the graph-easy skill (or adr-graph-easy-architect for ADRs)." >&2
    echo "These skills generate proper boxart with reproducible source." >&2
    echo "" >&2
    echo "Every diagram MUST include:" >&2
    echo "  <details><summary>graph-easy source</summary>...</details>" >&2
    exit 2
fi

exit 0
