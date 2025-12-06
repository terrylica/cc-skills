#!/usr/bin/env bash
#
# Unified PreToolUse guard for cc-skills plugin.
# Pure bash + jq implementation for minimal startup overhead (~5ms vs ~100ms Python)
#
# Blocks:
# 1. Direct graph-easy CLI usage (require skill invocation)
# 2. Manual ASCII art in markdown (require graph-easy source block)
#

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract fields using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# Early exit for non-matching tools
if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
    exit 0
fi

#--- Bash tool: Check for graph-easy CLI ---
if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

    # Check if command contains graph-easy
    if [[ "$COMMAND" =~ graph-easy ]]; then
        # Check transcript for recent skill invocation
        SKILL_INVOKED=false
        if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
            if tail -100 "$TRANSCRIPT_PATH" 2>/dev/null | grep -qi -E 'adr-graph-easy-architect|itp:graph-easy|graph-easy skill'; then
                SKILL_INVOKED=true
            fi
        fi

        if [[ "$SKILL_INVOKED" == "false" ]]; then
            cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Direct graph-easy CLI usage is not allowed. Use the adr-graph-easy-architect skill for ADR diagrams, or the graph-easy skill for other markdown files. The skill provides proper boxart mode, \\n escaping, and validation."}}
EOF
            exit 0
        fi
    fi
    exit 0
fi

#--- Write/Edit tool: Check for manual ASCII art ---
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

    # Only check markdown files
    if [[ ! "$FILE_PATH" =~ \.(md|mdx)$ ]]; then
        exit 0
    fi

    # Get content to check
    if [[ "$TOOL_NAME" == "Edit" ]]; then
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')
    else
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')
    fi

    # Check for box-drawing characters (Unicode block)
    # Using grep with Unicode character class
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

        cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Manual ASCII diagrams detected in markdown. Use the adr-graph-easy-architect skill for ADR diagrams, or the graph-easy skill for other markdown files. These skills generate proper boxart with reproducible source. Every diagram must include a <details><summary>graph-easy source</summary> block."}}
EOF
        exit 0
    fi
fi

exit 0
