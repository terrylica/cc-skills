#!/usr/bin/env bash
# Archive plan files BEFORE overwrite (PreToolUse hook)
# This preserves "genius memory" - the investigation history, dead ends, and decisions
#
# CRITICAL: This runs on PreToolUse (before the file is modified)
# so we can capture the original content before it's overwritten.
set -euo pipefail

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
    mkdir -p "$ARCHIVE_DIR"
    TIMESTAMP=$(date +%s)
    BASENAME=$(basename "$FILE_PATH")
    cp "$FILE_PATH" "$ARCHIVE_DIR/${SESSION_ID}-${TIMESTAMP}-${BASENAME}"

    # Log the archival
    echo "[$(date -Iseconds)] Archived: $FILE_PATH -> $ARCHIVE_DIR/${SESSION_ID}-${TIMESTAMP}-${BASENAME}" \
        >> "$HOME/.claude/automation/loop-orchestrator/state/archive.log"
fi

# Allow the write to proceed (exit 0 = success)
exit 0
