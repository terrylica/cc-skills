#!/usr/bin/env bash
# Archive plan files BEFORE overwrite (PreToolUse hook)
# This preserves "genius memory" - the investigation history, dead ends, and decisions
#
# CRITICAL: This runs on PreToolUse (before the file is modified)
# so we can capture the original content before it's overwritten.
set -euo pipefail

# ===== ALPHA-FORGE ONLY GUARD =====
# Ralph is dedicated to alpha-forge ML research workflows only.
# Skip all processing for non-alpha-forge projects (zero overhead).
_is_alpha_forge() {
    local dir="$1"
    # Check characteristic markers
    [[ -d "$dir/packages/alpha-forge-core" ]] && return 0
    [[ -d "$dir/outputs/runs" ]] && return 0
    grep -q -E "alpha[-_]forge" "$dir/pyproject.toml" 2>/dev/null && return 0
    return 1
}

if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    is_af=false
    # Direct detection
    if _is_alpha_forge "$CLAUDE_PROJECT_DIR"; then
        is_af=true
    # Git worktree detection: .git is a file containing "gitdir: ..."
    elif [[ -f "$CLAUDE_PROJECT_DIR/.git" ]]; then
        gitdir=$(grep "^gitdir:" "$CLAUDE_PROJECT_DIR/.git" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        if [[ -n "$gitdir" && "$gitdir" == *"/worktrees/"* ]]; then
            # Navigate: .git/worktrees/<name> → .git → repo root
            main_repo=$(dirname "$(dirname "$gitdir")")
            main_repo=$(dirname "$main_repo")
            if [[ -d "$main_repo" ]] && _is_alpha_forge "$main_repo"; then
                is_af=true
            fi
        fi
    fi
    if [[ "$is_af" == "false" ]]; then
        exit 0  # Not alpha-forge, skip archival
    fi
fi

# ===== JQ AVAILABILITY CHECK (RSSI Enhancement) =====
# jq is required for parsing hook input JSON. Try to install if missing.
if ! command -v jq &> /dev/null; then
    # Try mise install first (preferred tool manager)
    if command -v mise &> /dev/null; then
        echo "[ralph] jq not found, attempting mise install..." >&2
        if ! mise install jq 2>&1; then
            echo "[ralph] mise install jq failed" >&2
        fi
    fi
    # Try brew install (macOS fallback)
    if ! command -v jq &> /dev/null && command -v brew &> /dev/null; then
        echo "[ralph] Attempting brew install jq..." >&2
        if ! brew install jq 2>&1; then
            echo "[ralph] brew install jq failed" >&2
        fi
    fi
    # If still unavailable, block and notify user
    if ! command -v jq &> /dev/null; then
        echo "[ralph] ERROR: jq required but could not be installed" >&2
        echo '{"decision": "block", "reason": "jq is required for archive-plan.sh but could not be installed. Please install manually: brew install jq OR mise install jq"}'
        exit 0  # Exit 0 with blocking JSON (hook protocol)
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
        echo "[ralph] Failed to create archive directory: $ARCHIVE_DIR" >&2
    else
        TIMESTAMP=$(date +%s)
        BASENAME=$(basename "$FILE_PATH")
        if ! cp "$FILE_PATH" "$ARCHIVE_DIR/${SESSION_ID}-${TIMESTAMP}-${BASENAME}" 2>&1; then
            echo "[ralph] Failed to archive: $FILE_PATH" >&2
        else
            # Log the archival
            echo "[$(date -Iseconds)] Archived: $FILE_PATH -> $ARCHIVE_DIR/${SESSION_ID}-${TIMESTAMP}-${BASENAME}" \
                >> "$HOME/.claude/automation/loop-orchestrator/state/archive.log" 2>&1 || \
                echo "[ralph] Failed to write archive log" >&2
        fi
    fi
fi

# Allow the write to proceed (exit 0 = success)
exit 0
