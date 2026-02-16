#!/usr/bin/env bash
# Archive plan files BEFORE overwrite (PreToolUse hook)
# This preserves "genius memory" - the investigation history, dead ends, and decisions
#
# CRITICAL: This runs on PreToolUse (before the file is modified)
# so we can capture the original content before it's overwritten.
set -euo pipefail

# ===== RALPH-UNIVERSAL: NO PROJECT TYPE RESTRICTION =====
# Unlike original Ralph, this works on ANY project type.
# The Alpha-Forge exclusivity guard has been removed.

# ===== JQ AVAILABILITY CHECK =====
# jq is required for parsing hook input JSON. Try to install if missing.
if ! command -v jq &> /dev/null; then
    # Try mise install first (preferred tool manager)
    if command -v mise &> /dev/null; then
        if ! mise install jq 2>&1; then
            :
        fi
    fi
    # Try brew install (macOS fallback)
    if ! command -v jq &> /dev/null && command -v brew &> /dev/null; then
        if ! brew install jq 2>&1; then
            :
        fi
    fi
    # If still unavailable, block and notify user
    # ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
    # PreToolUse uses permissionDecision (not deprecated decision:block)
    if ! command -v jq &> /dev/null; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "jq is required for archive-plan.sh but could not be installed. Please install manually: brew install jq OR mise install jq"}}'
        exit 0
    fi
fi

ARCHIVE_DIR="$HOME/.claude/automation/loop-orchestrator/state/archives"

# Read hook input from stdin (CORRECT pattern per official docs)
if [[ -t 0 ]]; then
    exit 0  # No stdin (interactive terminal), skip
fi
HOOK_INPUT="$(cat)"

# Extract file_path from tool_input
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // ""')
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')

# Only archive writes to plan files
if [[ ! "$FILE_PATH" =~ \.claude/plans/.*\.md$ ]]; then
    exit 0
fi

# Archive the EXISTING file before it gets overwritten
if [[ -f "$FILE_PATH" && -n "$SESSION_ID" ]]; then
    if ! mkdir -p "$ARCHIVE_DIR" 2>&1; then
        :
    else
        TIMESTAMP=$(date +%s)
        BASENAME=$(basename "$FILE_PATH")
        if ! cp "$FILE_PATH" "$ARCHIVE_DIR/${SESSION_ID}-${TIMESTAMP}-${BASENAME}" 2>&1; then
            :
        else
            # Log the archival
            echo "[$(date -Iseconds)] Archived: $FILE_PATH -> $ARCHIVE_DIR/${SESSION_ID}-${TIMESTAMP}-${BASENAME}" \
                >> "$HOME/.claude/automation/loop-orchestrator/state/archive.log" 2>&1 || \
                :
        fi
    fi
fi

# Allow the write to proceed (exit 0 = success)
exit 0
