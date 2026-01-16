#!/bin/bash
# Custom Claude Code Status Line
# Receives Claude Code status JSON via stdin, outputs formatted status line
#
# MIT License
# Copyright (c) 2025 Terry Li
#
# Original concept inspired by: https://github.com/sirmalloc/ccstatusline (MIT)
# This is a custom implementation with git status, link validation, and path linting.
#
# Indicators:
#   M = Modified (unstaged)    D = Deleted (unstaged)
#   S = Staged (for commit)    U = Untracked (new files)
#   ↑ = Commits ahead          ↓ = Commits behind
#   ≡ = Stash count            ⚠ = Merge conflicts
#   L = Broken links (lychee)  P = Path violations (lint-relative-paths)
#
# Session line format:
#   Session UUID: <claude-code-uuid> | Cast: <iterm2-uuid>
#   The Cast UUID maps to: ~/Downloads/*.<iterm2-uuid>.*.cast

# ANSI Color codes
RESET='\033[0m'
CYAN='\033[36m'
BRIGHT_BLACK='\033[90m'
MAGENTA='\033[35m'
YELLOW='\033[33m'
RED='\033[91m'
BLUE='\033[94m'
GREEN='\033[92m'

# Get path display with ~ substitution
# Shows: ~/eon/cc-skills or ~/eon/cc-skills/plugins/itp-hooks
get_repo_path() {
    pwd | sed "s|$HOME|~|"
}

repo_path=$(get_repo_path)

# Read JSON from stdin
input=$(cat)

# Extract fields
model=$(echo "$input" | jq -r '.model.name // .model.id // "Unknown"' | sed 's/Claude //' | sed 's/ 4.5/4.5/')
session_id=$(echo "$input" | jq -r '.session_id // ""')

# === Session Chain (Bun-based) ===
# Traces session ancestry, displays last 5 sessions with arrows
# All in gray for uniform, non-distracting reference display
session_chain=""
if [ -n "$session_id" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    chain_script="${SCRIPT_DIR}/../scripts/session-chain.ts"
    if [ -f "$chain_script" ]; then
        # Run with timeout to not block statusline (gtimeout on macOS via coreutils)
        if command -v gtimeout >/dev/null 2>&1; then
            session_chain=$(gtimeout 0.1 bun "$chain_script" "$session_id" 2>/dev/null || echo "")
        elif command -v timeout >/dev/null 2>&1; then
            session_chain=$(timeout 0.1 bun "$chain_script" "$session_id" 2>/dev/null || echo "")
        else
            # No timeout available, run directly (may block briefly)
            session_chain=$(bun "$chain_script" "$session_id" 2>/dev/null || echo "")
        fi
    fi
fi

# Context - Claude Code doesn't send token counts in status JSON
# Instead, try to read from transcript file or show cost
transcript_file=$(echo "$input" | jq -r '.transcript_path // empty')
ctx_display=""

if [ -n "$transcript_file" ] && [ -f "$transcript_file" ]; then
    # Try to get token count from last line of transcript
    last_line=$(tail -1 "$transcript_file" 2>/dev/null)
    if [ -n "$last_line" ]; then
        input_tok=$(echo "$last_line" | jq -r '.usage.input_tokens // empty' 2>/dev/null)
        output_tok=$(echo "$last_line" | jq -r '.usage.output_tokens // empty' 2>/dev/null)

        if [ -n "$input_tok" ] && [ -n "$output_tok" ]; then
            total_tok=$((input_tok + output_tok))
            if [ "$total_tok" -gt 1000 ]; then
                ctx_k=$((total_tok / 1000))
                ctx_display="${ctx_k}k"
            else
                ctx_display="${total_tok}"
            fi
        fi
    fi
fi

# Fallback: show cost if no token count available
if [ -z "$ctx_display" ]; then
    cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
    if [ -n "$cost" ]; then
        # Format cost to 2 decimal places
        cost_formatted=$(printf "%.2f" "$cost" 2>/dev/null || echo "$cost")
        ctx_display="\$${cost_formatted}"
    else
        ctx_display="N/A"
    fi
fi

# Git info - try JSON first, fallback to direct git commands
git_branch=$(echo "$input" | jq -r '.git.branch // empty')
if [ -z "$git_branch" ]; then
    # Fallback: read git directly
    git_branch=$(git branch --show-current 2>/dev/null || echo "no-branch")
fi

# === Session Registry Update (CONDITIONAL fire-and-forget) ===
# Only fires when session_id changes - not every render (performance optimization)
# Updates ~/.claude/projects/{encoded-path}/.session-chain-cache.json
if [ -n "$session_id" ]; then
    REGISTRY_CACHE="/tmp/ccstatusline-session-$$"
    cached_session=$(cat "$REGISTRY_CACHE" 2>/dev/null || echo "")

    if [[ "$session_id" != "$cached_session" ]]; then
        echo "$session_id" > "$REGISTRY_CACHE"
        registry_script="${SCRIPT_DIR}/../scripts/update-session-registry.ts"
        if [ -f "$registry_script" ]; then
            cwd_path=$(pwd)
            # Single-instance lock to prevent process accumulation
            LOCK_DIR="/tmp/session-registry.lock"
            if mkdir "$LOCK_DIR" 2>/dev/null; then
                (
                    trap 'rmdir /tmp/session-registry.lock 2>/dev/null' EXIT
                    bun "$registry_script" "$session_id" "$cwd_path" "$model" "${cost:-}" "$git_branch"
                ) >/dev/null 2>&1 &
            fi
        fi
    fi
fi

# Get file status counts (consistent with Telegram bot format)
# Using --diff-filter to separate change types accurately:
#   M = Modified (content changed, unstaged)
#   D = Deleted (removed from working tree, unstaged)
#   S = Staged (any change staged for commit)
#   U = Untracked (new files not in git)
git_status_output=$(git status --porcelain 2>/dev/null)
if [ -n "$git_status_output" ]; then
    modified=$(git diff --name-only --diff-filter=M 2>/dev/null | wc -l | tr -d ' ')
    deleted=$(git diff --name-only --diff-filter=D 2>/dev/null | wc -l | tr -d ' ')
    staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
else
    modified=0
    deleted=0
    staged=0
    untracked=0
fi

# Ahead/Behind remote tracking
# ↑n = commits ahead (need to push), ↓n = commits behind (need to pull)
ahead=0
behind=0
if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
    # Get counts from local tracking ref (fast, may be stale after external push)
    ahead=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo 0)
    behind=$(git rev-list HEAD..@{u} --count 2>/dev/null || echo 0)

    # Quick staleness check: if ahead > 0, verify with remote (cached for 30s)
    # This catches the case where external tools pushed but local refs are stale
    if [ "$ahead" -gt 0 ]; then
        # Use git rev-parse --git-dir for worktree compatibility (.git may be a file)
        git_dir=$(git rev-parse --git-dir 2>/dev/null)
        cache_file="${git_dir}/ccstatusline-remote-cache"
        cache_age=9999

        if [ -f "$cache_file" ]; then
            cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0)))
        fi

        # Only query remote every 30 seconds to avoid network overhead
        if [ "$cache_age" -gt 30 ]; then
            local_head=$(git rev-parse HEAD 2>/dev/null)
            remote_name=$(git config branch.$(git branch --show-current).remote 2>/dev/null || echo "origin")
            remote_head=$(git ls-remote --heads "$remote_name" "$(git branch --show-current)" 2>/dev/null | cut -f1)
            echo "${local_head}:${remote_head}" > "$cache_file" 2>/dev/null
        else
            # Read from cache
            IFS=':' read -r local_head remote_head < "$cache_file" 2>/dev/null
            local_head=${local_head:-$(git rev-parse HEAD 2>/dev/null)}
        fi

        # If local HEAD matches remote HEAD, we're in sync
        if [ "$local_head" = "$remote_head" ]; then
            ahead=0
        fi
    fi
fi

# Stash count - easy to forget stashed changes!
stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

# Merge conflicts (unmerged files) - critical during rebase/merge
conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')

# Build git status display with conditional coloring
# Format: M:n D:n S:n U:n | ↑:n ↓:n | ≡:n | ⚠:n
# All counters always shown for consistency and to indicate tracking
#
# Color rules:
#   Zero values: whitish gray (BRIGHT_BLACK)
#   Non-zero values: yellow (YELLOW)
#   Conflicts non-zero: red (RED)

# Helper function: colorize stat based on value
colorize_stat() {
    local label="$1"
    local value="$2"
    local highlight_color="${3:-$YELLOW}"

    if [ "$value" -eq 0 ]; then
        echo "${BRIGHT_BLACK}${label}:${value}${RESET}"
    else
        echo "${highlight_color}${label}:${value}${RESET}"
    fi
}

# File changes group (each stat colored independently)
git_changes="$(colorize_stat M $modified) $(colorize_stat D $deleted) $(colorize_stat S $staged) $(colorize_stat U $untracked)"

# Remote tracking (always show if tracking remote)
if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
    git_changes="${git_changes} $(colorize_stat ↑ $ahead) $(colorize_stat ↓ $behind)"
fi

# Stash count (always show)
git_changes="${git_changes} $(colorize_stat ≡ $stash_count)"

# Conflict indicator (RED when non-zero)
git_changes="${git_changes} $(colorize_stat ⚠ $conflicts $RED)"

# =============================================================================
# Lychee Link Checker + lint-relative-paths (reads from cached results)
# =============================================================================
# The stop hook runs lychee AND lint-relative-paths in background and caches
# results. Shown as separate indicators:
#   L = Lychee (broken links)
#   P = Path violations (relative path format issues)
#
# Priority (mirrors stop hook config resolution):
#   1. Local first: $git_root/.lychee-results.json
#   2. Fallback to global: ~/.claude/.lychee-results.json

link_errors=0
path_violations=0
lychee_cache=""
git_root=$(git rev-parse --show-toplevel 2>/dev/null)

# Priority 1: Local repo results (preferred)
if [[ -n "$git_root" && -f "$git_root/.lychee-results.json" ]]; then
    lychee_cache="$git_root/.lychee-results.json"
# Priority 2: Global results (fallback)
elif [[ -f "$HOME/.claude/.lychee-results.json" ]]; then
    lychee_cache="$HOME/.claude/.lychee-results.json"
fi

# Extract lychee error count from cached results
if [[ -n "$lychee_cache" ]]; then
    link_errors=$(jq -r '.errors // 0' "$lychee_cache" 2>/dev/null || echo 0)
fi

# Extract lint-relative-paths violations (same location as lychee cache)
if [[ -n "$git_root" && -f "$git_root/.lint-relative-paths-results.txt" ]]; then
    # Parse "Found N violation(s)" from results file
    path_violations=$(grep -oE 'Found [0-9]+ violation' "$git_root/.lint-relative-paths-results.txt" 2>/dev/null | grep -oE '[0-9]+' || echo 0)
fi

# Add separator and link checker indicators (L=Links, P=Paths)
# These are separate from git status, so use | delimiter
link_status="$(colorize_stat L $link_errors $RED) $(colorize_stat P $path_violations $RED)"
git_changes="${git_changes} | ${link_status}"

# Get GitHub remote URL (convert SSH to HTTPS for browser link)
get_github_url() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null)

    if [[ -z "$remote_url" ]]; then
        echo ""
        return
    fi

    # Convert SSH format to HTTPS
    # git@github.com-terrylica:terrylica/repo.git -> https://github.com/terrylica/repo
    # git@github.com:user/repo.git -> https://github.com/user/repo
    local https_url
    https_url=$(echo "$remote_url" | sed -E 's|git@github\.com[^:]*:|https://github.com/|' | sed 's|\.git$||')

    # Add branch path if not on main/master
    local branch
    branch=$(git branch --show-current 2>/dev/null)
    if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
        echo "${https_url}/tree/${branch}"
    else
        echo "$https_url"
    fi
}

github_url=$(get_github_url)

# UTC and local timestamps with dates (updated every time statusline triggers)
# Compact format: 24Dec21 14:32Z (2-digit year + month + day + time + Z/L suffix)
# Both dates shown since UTC and local may be different days
utc_time=$(date -u +"%y%b%d %H:%MZ")
local_time=$(date +"%y%b%d %H:%ML")

# Three-line status:
#   Line 1: git stats | local time
#   Line 2: ~/path | github-url | UTC time
#   Line 3: session UUID (if available)
line1="${git_changes} | ${BRIGHT_BLACK}${local_time}${RESET}"

# Line 2: path | GitHub URL + UTC time
if [[ -n "$github_url" ]]; then
    if [[ "$git_branch" == "main" || "$git_branch" == "master" ]]; then
        line2="${GREEN}${repo_path}${RESET} | ${BRIGHT_BLACK}${github_url} | ${utc_time}${RESET}"
    else
        line2="${GREEN}${repo_path}${RESET} | ${MAGENTA}${github_url} | ${utc_time}${RESET}"
    fi
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    line2="${GREEN}${repo_path}${RESET} | ${RED}⚠ no remote${RESET} | ${BRIGHT_BLACK}${utc_time}${RESET}"
else
    line2="${GREEN}${repo_path}${RESET} | ${RED}⚠ no git${RESET} | ${BRIGHT_BLACK}${utc_time}${RESET}"
fi

echo -e "$line1"
echo -e "$line2"

# Line 3: Session UUID + Cast file reference (for asciinema playback)
# Format: Session UUID: <claude-code-uuid> | Cast: <iterm2-uuid>
# The Cast UUID directly maps to asciinema recording filename in ~/Downloads/

# Extract iTerm2 session UUID from environment (format: w0t1p1:UUID)
iterm_session_uuid=""
if [ -n "$ITERM_SESSION_ID" ]; then
    # Extract just the UUID part after the colon
    iterm_session_uuid=$(echo "$ITERM_SESSION_ID" | cut -d':' -f2)
fi

if [ -n "$session_chain" ]; then
    # Claude Code UUID already includes ANSI colors from Bun script
    if [ -n "$iterm_session_uuid" ]; then
        echo -e "${BRIGHT_BLACK}Session UUID:${RESET} ${session_chain} ${BRIGHT_BLACK}| Cast: ${iterm_session_uuid}${RESET}"
    else
        echo -e "${BRIGHT_BLACK}Session UUID:${RESET} ${session_chain}"
    fi
elif [ -n "$session_id" ]; then
    # Fallback if Bun script unavailable
    if [ -n "$iterm_session_uuid" ]; then
        echo -e "${BRIGHT_BLACK}Session UUID: ${session_id} | Cast: ${iterm_session_uuid}${RESET}"
    else
        echo -e "${BRIGHT_BLACK}Session UUID: ${session_id}${RESET}"
    fi
fi
