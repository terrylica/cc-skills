#!/usr/bin/env bash
# chezmoi-sync-reminder.sh - PostToolUse hook for chezmoi file change detection
# Prompts Claude to sync chezmoi-tracked dotfiles after edits
#
# Trigger: PostToolUse on Edit|Write
# Output: JSON with decision:block to ensure Claude sees the reminder
# Reference: https://github.com/anthropics/claude-code/issues/3983
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

    # Output JSON with decision:block - REQUIRED for Claude to see the reason
    # See: https://github.com/anthropics/claude-code/issues/3983
    jq -n \
        --arg reason "[CHEZMOI] $REL_PATH is tracked by chezmoi. Sync with: chezmoi add $REL_PATH && chezmoi git -- push. Or use Skill(dotfiles-tools:chezmoi-workflows)." \
        '{decision: "block", reason: $reason}'
fi

exit 0
