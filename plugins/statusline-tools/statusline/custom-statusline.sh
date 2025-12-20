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

# ANSI Color codes
RESET='\033[0m'
CYAN='\033[36m'
BRIGHT_BLACK='\033[90m'
MAGENTA='\033[35m'
YELLOW='\033[33m'
RED='\033[91m'
BLUE='\033[94m'
GREEN='\033[92m'

# Get git repo-relative path display
# Shows: repo-name/relative/path (e.g., cc-skills/plugins/itp-hooks)
get_repo_path() {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [[ -n "$repo_root" ]]; then
        local repo_name
        repo_name=$(basename "$repo_root")
        local current_dir
        current_dir=$(pwd)

        if [[ "$current_dir" == "$repo_root" ]]; then
            # At repo root - just show repo name
            echo "$repo_name"
        else
            # Inside repo - show repo_name/relative/path
            local relative_path
            relative_path="${current_dir#$repo_root/}"
            echo "$repo_name/$relative_path"
        fi
    else
        # Not in a git repo - fallback to ~ substituted path
        pwd | sed "s|$HOME|~|"
    fi
}

repo_path=$(get_repo_path)

# Read JSON from stdin
input=$(cat)

# Extract fields
model=$(echo "$input" | jq -r '.model.name // .model.id // "Unknown"' | sed 's/Claude //' | sed 's/ 4.5/4.5/')
session_id=$(echo "$input" | jq -r '.session_id // ""')

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
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
        cache_file="${repo_root}/.git/ccstatusline-remote-cache"
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

# Determine branch color based on branch name
if [[ "$git_branch" == "main" || "$git_branch" == "master" ]]; then
    branch_color="${BRIGHT_BLACK}"
else
    branch_color="${MAGENTA}"
fi

# Single line status: repo-path | branch | git stats | github-url
status_line="${GREEN}${repo_path}${RESET} | ${branch_color}↯ ${git_branch}${RESET} | ${YELLOW}${git_changes}${RESET}"

# Append GitHub URL or warning (color matches branch state)
if [[ -n "$github_url" ]]; then
    if [[ "$git_branch" == "main" || "$git_branch" == "master" ]]; then
        # Main/master: whitish gray
        status_line="${status_line} | ${BRIGHT_BLACK}${github_url}${RESET}"
    else
        # Feature branch: magenta (matches branch indicator)
        status_line="${status_line} | ${MAGENTA}${github_url}${RESET}"
    fi
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # In a git repo but no remote configured
    status_line="${status_line} | ${RED}⚠ no remote${RESET}"
else
    # Not in a git repo at all
    status_line="${status_line} | ${RED}⚠ no git${RESET}"
fi

echo -e "$status_line"
