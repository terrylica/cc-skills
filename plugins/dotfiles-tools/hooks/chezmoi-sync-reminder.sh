#!/usr/bin/env bash
# chezmoi-sync-reminder.sh - PostToolUse hook for chezmoi file change detection
# Emits reminder when editing chezmoi-tracked dotfiles
#
# Trigger: PostToolUse on Edit|Write
# Output: Non-blocking JSON reminder to stdout
# Plugin: dotfiles-tools (cc-skills marketplace)

set -euo pipefail

# Read JSON payload from stdin
PAYLOAD=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$PAYLOAD" | jq -r '.tool_input.file_path // empty')

# Exit silently if no file path (shouldn't happen for Edit/Write)
[[ -z "$FILE_PATH" ]] && exit 0

# Expand ~ to absolute path for comparison
ABSOLUTE_PATH=$(eval echo "$FILE_PATH")

# Check if chezmoi is available
command -v chezmoi &>/dev/null || exit 0

# Get chezmoi managed files (cache for performance)
CACHE_FILE="${TMPDIR:-/tmp}/chezmoi-managed-files.cache"

# Refresh cache if stale or missing (5 minute TTL)
if [[ ! -f "$CACHE_FILE" ]] || [[ $(find "$CACHE_FILE" -mmin +5 2>/dev/null) ]]; then
    chezmoi managed --include=files --path-style=absolute --no-pager 2>/dev/null > "$CACHE_FILE" || exit 0
fi

# Check if modified file is in managed list
if grep -qxF "$ABSOLUTE_PATH" "$CACHE_FILE" 2>/dev/null; then
    # Get relative path for display
    REL_PATH="${ABSOLUTE_PATH/#$HOME/~}"

    # Build reminder message
    REMINDER="[CHEZMOI] $REL_PATH was modified.\\nSync with: Skill(dotfiles-tools:chezmoi-workflows)\\nQuick: chezmoi add $REL_PATH && chezmoi git -- push"

    # Output to stdout (JSON escaped)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"${REMINDER}\"}}"
fi

exit 0
