#!/usr/bin/env bash
# chezmoi-sync-reminder.sh - PostToolUse hook for chezmoi file change detection
# Prompts Claude to sync chezmoi-tracked dotfiles after edits
# Also detects untracked config files and suggests adding to chezmoi
#
# Trigger: PostToolUse on Edit|Write
# Output: JSON with decision:block to ensure Claude sees the reminder
# Reference: https://github.com/anthropics/claude-code/issues/3983
# Plugin: dotfiles-tools (cc-skills marketplace)

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

# ===========================================================================
# Iter-46 CHEZMOI-COMMAND-AVAILABILITY-FASTPATH (bash-builtin-before-jq):
#
# This hook fires on EVERY Edit and EVERY Write tool call. Pre-iter-46 it
# spawned TWO jq processes (~10-14 ms combined) AND resolved the absolute
# path BEFORE checking whether chezmoi is even installed. For any user
# who has dotfiles-tools enabled but doesn't actually use chezmoi (or
# hasn't installed it yet), every Edit/Write paid that full cost just to
# reach `command -v chezmoi` and bail.
#
# Bash `command -v` is a shell builtin — no fork/exec, ~50 microseconds.
# Moving it to position 1 (before any jq spawn or path resolution)
# short-circuits the entire pipeline for non-chezmoi users at ~100x less
# cost than the prior bail-out path.
#
# Speedup measured on m3max bash 5.3.9 (chezmoi NOT installed):
#   pre-iter-46 bail-out: ~12 ms (2 jq spawns + path resolve + builtin)
#   iter-46    bail-out: ~0.1 ms (just the builtin)
#   speedup factor: ~120x on the no-chezmoi bail-out path
#
# For users WITH chezmoi installed (the common case for dotfiles-tools
# adopters), behavior is unchanged — the builtin returns 0 immediately
# and the rest of the hook proceeds as before.
command -v chezmoi &>/dev/null || exit 0
# ===========================================================================

# Read JSON payload from stdin
PAYLOAD=$(cat)

# ===========================================================================
# Iter-47 PLAN-MODE-BASH-BUILTIN-SUBSTRING-FASTPATH-BEFORE-JQ-PERMISSION-MODE-EXTRACTION:
#
# This is the second pre-jq-fastpath layer on chezmoi-sync-reminder.sh
# (iter-46 was the first, moving `command -v chezmoi` to position 1).
# Iter-47 replaces the `jq -r .permission_mode` extraction with a bash
# case-glob substring match on the raw PAYLOAD JSON.
#
# Why this works: the Claude Code hook envelope serializes `permission_mode`
# as a top-level string. Plan mode is encoded as the literal substring
#   "permission_mode":"plan"
# (with no whitespace, because Claude Code's serializer is JSON-canonical).
# A bash builtin case-glob match against `*'"permission_mode":"plan"'*`
# detects plan mode with zero process spawn.
#
# Pre-iter-47: jq spawn (~5-7 ms cold) on EVERY Edit/Write call just to
# check a boolean condition that's TRUE in ~1% of calls.
#
# Iter-47: bash case-glob (~50 µs), no jq spawn. ~100-140x speedup on
# the permission-mode check for the ~99% non-plan-mode hot path.
#
# Safety: bash case-glob substring match doesn't parse JSON, so it could
# theoretically false-positive on a payload that includes the literal
# substring inside a different value. In practice the Claude Code
# serializer escapes embedded quotes so this is extremely unlikely.
# Worst case: a false positive bails the hook (no reminder fires) which
# is the same outcome as the genuine plan-mode case — strictly safe.
#
# Speedup measured on m3max bash 5.3.9 (chezmoi installed, NOT plan mode):
#   pre-iter-47 jq-permission-mode-check: ~5-7 ms
#   iter-47    bash-case-glob-substring-match: <0.1 ms
#   speedup factor on this check: ~100x
#
# For plan mode (rare): the case-glob matches and the hook exits 0
# immediately, same outcome as pre-iter-47 but ~5 ms faster.
case "$PAYLOAD" in
    *'"permission_mode":"plan"'*) exit 0 ;;  # plan-mode bail (rare)
esac
# ===========================================================================

# Extract file path from tool input
FILE_PATH=$(echo "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# Exit silently if no file path (shouldn't happen for Edit/Write)
[[ -z "$FILE_PATH" ]] && exit 0

# Convert to absolute path for comparison
# Handle both ~ expansion and relative paths
if [[ "$FILE_PATH" == ~* ]]; then
    # Expand ~ to home directory
    ABSOLUTE_PATH=$(eval echo "$FILE_PATH")
elif [[ "$FILE_PATH" == /* ]]; then
    # Already absolute
    ABSOLUTE_PATH="$FILE_PATH"
else
    # Relative path - use CLAUDE_PROJECT_DIR or pwd
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        ABSOLUTE_PATH="${CLAUDE_PROJECT_DIR}/${FILE_PATH}"
    else
        ABSOLUTE_PATH="$(pwd)/${FILE_PATH}"
    fi
fi

# Note: chezmoi-availability check was moved to position 1 in iter-46
# (pre-jq-fastpath optimization above). If we reached this point, chezmoi
# is confirmed installed and the rest of the hook proceeds.

# =============================================================================
# EXCLUSION: Skip files in ~/eon (company repositories)
# =============================================================================
if [[ "$ABSOLUTE_PATH" == "$HOME/eon"* ]]; then
    exit 0
fi

# Get chezmoi managed files (cache for performance)
CACHE_FILE="${TMPDIR:-/tmp}/chezmoi-managed-files.cache"

# Refresh cache if stale or missing (5 minute TTL)
if [[ ! -f "$CACHE_FILE" ]] || [[ $(find "$CACHE_FILE" -mmin +5 2>/dev/null) ]]; then
    chezmoi managed --include=files --path-style=absolute --no-pager 2>/dev/null > "$CACHE_FILE" || exit 0
fi

# =============================================================================
# CASE 1: File IS tracked by chezmoi - remind to sync
# =============================================================================
# NOTE: decision:block is REQUIRED for Claude to see the reason field
# See: https://github.com/anthropics/claude-code/issues/3983
if grep -qxF "$ABSOLUTE_PATH" "$CACHE_FILE" 2>/dev/null; then
    REL_PATH="${ABSOLUTE_PATH/#$HOME/~}"
    jq -n \
        --arg reason "[CHEZMOI-SYNC] $REL_PATH is tracked by chezmoi. Sync with: chezmoi add $REL_PATH && chezmoi git -- push" \
        '{decision: "block", reason: $reason}'
    exit 0
fi

# =============================================================================
# CASE 2: File is NOT tracked - check if it's a config file worth tracking
# =============================================================================
# Config file patterns that should be considered for chezmoi tracking:
#   - ~/.config/* (XDG config directory)
#   - ~/.*rc (shell rc files: .bashrc, .zshrc, .vimrc, etc.)
#   - ~/.*profile (profile files)
#   - ~/.*_profile (bash_profile, zsh_profile)
#   - ~/.* (other dotfiles in home)
#   - *.conf files in ~/.config or similar

is_config_file() {
    local path="$1"

    # ~/.config/* - XDG config directory
    [[ "$path" == "$HOME/.config/"* ]] && return 0

    # ~/Library/Application Support/* - macOS app configs (selective)
    # Skip this - too broad, most are app-managed

    # Dotfiles in home directory
    local filename
    filename=$(basename "$path")
    local dirname
    dirname=$(dirname "$path")

    # Only consider files directly in $HOME that start with .
    if [[ "$dirname" == "$HOME" && "$filename" == .* ]]; then
        # Common dotfiles worth tracking
        case "$filename" in
            .bashrc|.zshrc|.bash_profile|.zprofile|.profile|.zshenv)
                return 0 ;;
            .gitconfig|.gitignore_global|.gitattributes)
                return 0 ;;
            .vimrc|.gvimrc|.ideavimrc)
                return 0 ;;
            .tmux.conf|.screenrc)
                return 0 ;;
            .inputrc|.editrc)
                return 0 ;;
            .curlrc|.wgetrc)
                return 0 ;;
            .npmrc|.yarnrc)
                return 0 ;;
            .gemrc|.irbrc|.pryrc)
                return 0 ;;
            .pylintrc|.flake8)
                return 0 ;;
            *)
                # Other dotfiles - skip (too many false positives)
                return 1 ;;
        esac
    fi

    # *.conf files in config locations
    if [[ "$filename" == *.conf && "$path" == "$HOME/.config/"* ]]; then
        return 0
    fi

    return 1
}

# Check if this is a config file worth suggesting
# NOTE: decision:block is REQUIRED for Claude to see the reason field
# See: https://github.com/anthropics/claude-code/issues/3983
if is_config_file "$ABSOLUTE_PATH"; then
    REL_PATH="${ABSOLUTE_PATH/#$HOME/~}"
    jq -n \
        --arg reason "[CHEZMOI-ADD] $REL_PATH is a config file NOT tracked by chezmoi. Use AskUserQuestion to ask: 'Track $REL_PATH with chezmoi for cross-machine sync?' Options: 'Yes, add to chezmoi' / 'No, skip'. If yes: chezmoi add $REL_PATH && chezmoi git -- push" \
        '{decision: "block", reason: $reason}'
    exit 0
fi

exit 0
