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
#   Pth = Path violations (lint-relative-paths)
#
# Session line format:
#   ~/.claude/projects JSONL ID: <claude-code-uuid>
#   ~/asciinemalogs cast: <iterm2-uuid>
#   The Cast UUID maps to: ~/Downloads/*.<iterm2-uuid>.*.cast

# ANSI Color codes
RESET='\033[0m'
BRIGHT_BLACK='\033[90m'
MAGENTA='\033[35m'
YELLOW='\033[33m'
RED='\033[91m'
GREEN='\033[92m'
CYAN='\033[96m'

# Get path display with ~ substitution
# Shows: ~/eon/cc-skills or ~/eon/cc-skills/plugins/itp-hooks
get_repo_path() {
    pwd | sed "s|$HOME|~|"
}

repo_path=$(get_repo_path)

# Debug logging (temporary) - logs invocations to diagnose intermittent failures
DEBUG_LOG="/tmp/ccstatusline-invocation.log"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) PID=$$ PPID=$PPID PWD=$(pwd)" >> "$DEBUG_LOG" 2>/dev/null
# Read JSON from stdin
input=$(cat)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) INPUT_LEN=${#input} MODEL_RAW=$(echo "$input" | jq -r '.model // "null"' 2>/dev/null | head -c 80)" >> "$DEBUG_LOG" 2>/dev/null

# Extract fields
model=$(echo "$input" | jq -r '.model.display_name // .model.id // .model // "Unknown"' | sed 's/Claude //' | sed 's/ 4.5/4.5/')
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
# NOTE: Uses per-session-UUID lock (NOT per-PID $$) to avoid /tmp file proliferation.
if [ -n "$session_id" ]; then
    REGISTRY_LOCK="/tmp/ccstatusline-registered-${session_id}"
    if [ ! -f "$REGISTRY_LOCK" ]; then
        touch "$REGISTRY_LOCK"
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
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    # Get counts from local tracking ref (fast, may be stale after external push)
    ahead=$(git rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)
    behind=$(git rev-list 'HEAD..@{u}' --count 2>/dev/null || echo 0)

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
            remote_name=$(git config "branch.$(git branch --show-current).remote" 2>/dev/null || echo "origin")
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
git_changes="$(colorize_stat M "$modified") $(colorize_stat D "$deleted") $(colorize_stat S "$staged") $(colorize_stat U "$untracked")"

# Remote tracking (always show if tracking remote)
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    git_changes="${git_changes} $(colorize_stat ↑ "$ahead") $(colorize_stat ↓ "$behind")"
fi

# Stash count (always show)
git_changes="${git_changes} $(colorize_stat ≡ "$stash_count")"

# Conflict indicator (RED when non-zero)
git_changes="${git_changes} $(colorize_stat ⚠ "$conflicts" "$RED")"

# === Version Tag + Release Age ===
# Show latest git tag after git indicators, separated by |
# Includes compact relative time since tag was created (e.g., "3h", "2d")
# Semver tags (vN.N.N): shown in cyan
# Non-semver tags: shown in yellow
# No tags: show ∅ in gray

# Compact relative time: epoch → "3s", "5m", "2h", "3d", "2w", "4mo", "1y"
reltime() {
    local diff=$(( $(date +%s) - $1 ))
    if   (( diff < 60 ));       then printf '%ds ago'  "$diff"
    elif (( diff < 3600 ));     then printf '%dm ago'  "$(( diff / 60 ))"
    elif (( diff < 86400 ));    then printf '%dh ago'  "$(( diff / 3600 ))"
    elif (( diff < 604800 ));   then printf '%dd ago'  "$(( diff / 86400 ))"
    elif (( diff < 2592000 ));  then printf '%dw ago'  "$(( diff / 604800 ))"
    elif (( diff < 31536000 )); then printf '%dmo ago' "$(( diff / 2592000 ))"
    else                             printf '%dy ago'  "$(( diff / 31536000 ))"
    fi
}

latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$latest_tag" ]; then
    # Get tag creation epoch (works for both annotated and lightweight tags)
    tag_epoch=$(git log -1 --format='%ct' "$latest_tag" 2>/dev/null || echo "")
    tag_age=""
    if [ -n "$tag_epoch" ]; then
        tag_age=" ${BRIGHT_BLACK}$(reltime "$tag_epoch")${RESET}"
    fi

    if [[ "$latest_tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        git_changes="${git_changes} ${BRIGHT_BLACK}|${RESET} ${CYAN}${latest_tag}${RESET}${tag_age}"
    else
        git_changes="${git_changes} ${BRIGHT_BLACK}|${RESET} ${YELLOW}${latest_tag}${RESET}${tag_age}"
    fi
else
    git_changes="${git_changes} ${BRIGHT_BLACK}| ∅${RESET}"
fi

# === Active Cron Jobs ===
# Reads ~/.claude/state/active-crons.json written by cron-tracker.ts hook
# Each entry includes: id, schedule, session_id, project_path, prompt_file
# Displayed as dedicated bottom lines, one per scheduler.
# OSC 8 hyperlink emitted directly (never accumulated in a variable — avoids
# printf '%b' double-processing the backslash sequences).
cron_state_file="$HOME/.claude/state/active-crons.json"
cron_count=0
[ -f "$cron_state_file" ] && cron_count=$(jq 'length' "$cron_state_file" 2>/dev/null || echo 0)

# cron-countdown.py PID (iTerm2 status bar component)
cron_countdown_pid=$(pgrep -f 'cron-countdown\.py' 2>/dev/null | head -1)


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

# UTC and local timestamps with conditional date display
# Same date:        Tue 04 Mar 2026 23:36 UTC | 15:36 PST
# Different day:    Sun 22 Mar 2026 02:08 UTC | Sat 21 19:08 PDT
# Different month:  Wed 01 Jan 2026 05:00 UTC | Tue 31 Dec 19:00 PST
# Different year:   Thu 01 Jan 2026 05:00 UTC | Wed 31 Dec 2025 19:00 PST
# Local date portion shown in yellow when it differs from UTC
utc_date=$(date -u +"%a %d %b %Y")
utc_hm=$(date -u +"%H:%M")
utc_month=$(date -u +"%b")
utc_year=$(date -u +"%Y")
local_date=$(date +"%a %d %b %Y")
local_hm=$(date +"%H:%M")
local_tz=$(date +"%Z")
local_month=$(date +"%b")
local_year=$(date +"%Y")

if [ "$utc_date" = "$local_date" ]; then
    # Same date: show date once with UTC, local time-only
    datetime_display="${BRIGHT_BLACK}${utc_date} ${utc_hm} UTC | ${local_hm} ${local_tz}${RESET}"
else
    # Different date: build minimal local date showing only what differs
    # Always show day-of-week + day number; add month if different; add year if different
    local_short=$(date +"%a %d")
    if [ "$utc_year" != "$local_year" ]; then
        local_short="$(date +"%a %d %b %Y")"
    elif [ "$utc_month" != "$local_month" ]; then
        local_short="$(date +"%a %d %b")"
    fi
    datetime_display="${BRIGHT_BLACK}${utc_date} ${utc_hm} UTC | ${YELLOW}${local_short}${BRIGHT_BLACK} ${local_hm} ${local_tz}${RESET}"
fi

# Status line layout:
#   Line 1: git stats
#   Line 2:  ~/asciinemalogs cast UUID
#   Line 3:    ~/path | github-url
#   Line 4:    session UUID (if available)
#   Line 5:    UTC time | local time
line1="${git_changes}"

# Line 3: path | GitHub URL (indented, no timestamps)
if [[ -n "$github_url" ]]; then
    if [[ "$git_branch" == "main" || "$git_branch" == "master" ]]; then
        line_repo="    ${GREEN}${repo_path}${RESET} | ${BRIGHT_BLACK}${github_url}${RESET}"
    else
        line_repo="    ${GREEN}${repo_path}${RESET} | ${MAGENTA}${github_url}${RESET}"
    fi
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    line_repo="    ${GREEN}${repo_path}${RESET} | ${RED}⚠ no remote${RESET}"
else
    line_repo="    ${GREEN}${repo_path}${RESET} | ${RED}⚠ no git${RESET}"
fi

# Extract iTerm2 session UUID from environment (format: w0t1p1:UUID)
iterm_session_uuid=""
if [ -n "$ITERM_SESSION_ID" ]; then
    iterm_session_uuid=$(echo "$ITERM_SESSION_ID" | cut -d':' -f2)
fi

# Output: git stats, cast, repo, session, timestamps, then cron jobs (bottom)
echo -e "$line1"

if [ -n "$iterm_session_uuid" ]; then
    echo -e " ${BRIGHT_BLACK}~/asciinemalogs cast: ${iterm_session_uuid}${RESET}"
fi

echo -e "$line_repo"

if [ -n "$session_chain" ]; then
    echo -e "    ${BRIGHT_BLACK}~/.claude/projects JSONL ID:${RESET} ${session_chain}"
elif [ -n "$session_id" ]; then
    echo -e "    ${BRIGHT_BLACK}~/.claude/projects JSONL ID: ${session_id}${RESET}"
fi

echo -e "    ${datetime_display}"

# Cron jobs: one line per scheduler, after datetime (bottom of statusline)
# OSC 8 parts emitted with printf directly — never stored in variables to
# avoid printf '%b' re-interpreting already-built escape sequences.
#
# Defense-in-depth: render-time liveness GC (Layer 1 of 3)
# Two-signal liveness check: crontab (durable crons) OR session JSONL
# freshness (session-only crons). Claude Code's CronCreate with
# durable=false creates in-process crons that never appear in crontab,
# so crontab alone causes 100% false-positive pruning.
# See also: Layer 2 (stop-cron-gc.ts), Layer 3 (TTL in cron-tracker.ts).
if [ "$cron_count" -gt 0 ]; then
    crontab_snapshot=$(crontab -l 2>/dev/null || true)
    now_epoch=$(date +%s)
    session_stale_threshold=7200  # 2 hours in seconds
    stale_ids=""
    while IFS= read -r entry; do
        gc_id=$(echo "$entry" | jq -r '.id')
        [ -z "$gc_id" ] && continue
        # Signal 1: durable cron in system crontab → live
        if echo "$crontab_snapshot" | grep -qF "$gc_id"; then
            continue
        fi
        # Signal 2: session JSONL mtime freshness → live if recent
        gc_session=$(echo "$entry" | jq -r '.session_id // ""')
        gc_project=$(echo "$entry" | jq -r '.project_path // ""')
        is_stale=1
        if [ -n "$gc_session" ] && [ -n "$gc_project" ]; then
            full_path="${gc_project/#\~/$HOME}"
            encoded_dir="${full_path//\//-}"
            jsonl_file="$HOME/.claude/projects/${encoded_dir}/${gc_session}.jsonl"
            if [ -f "$jsonl_file" ]; then
                jsonl_mtime=$(stat -f %m "$jsonl_file" 2>/dev/null || echo 0)
                age=$((now_epoch - jsonl_mtime))
                if [ "$age" -lt "$session_stale_threshold" ]; then
                    is_stale=0  # session is alive
                fi
            fi
        fi
        if [ "$is_stale" -eq 1 ]; then
            stale_ids="${stale_ids:+$stale_ids|}$gc_id"
        fi
    done < <(jq -c '.[]' "$cron_state_file" 2>/dev/null)

    if [ -n "$stale_ids" ]; then
        # Atomic prune: remove stale entries, write via temp file + rename
        jq --arg ids "$stale_ids" '
            [ .[] | select(.id | test($ids) | not) ]
        ' "$cron_state_file" > "${cron_state_file}.tmp" 2>/dev/null \
            && mv "${cron_state_file}.tmp" "$cron_state_file" 2>/dev/null
        cron_count=$(jq 'length' "$cron_state_file" 2>/dev/null || echo 0)
        # Log GC event for observability
        gc_log="$HOME/.claude/logs/cron-tracker.jsonl"
        [ -d "$HOME/.claude/logs" ] && printf '{"ts":"%s","level":"info","component":"statusline-gc","event":"render_time_gc","pruned_ids":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stale_ids" >> "$gc_log" 2>/dev/null
    fi
fi

if [ "$cron_count" -gt 0 ]; then
    while IFS= read -r entry; do
        job_id=$(echo "$entry"     | jq -r '.id')
        job_sched=$(echo "$entry"  | jq -r '.schedule')
        job_sess=$(echo "$entry"   | jq -r '.session_id // ""' | cut -c1-8)
        job_proj=$(echo "$entry"   | jq -r '.project_path // ""')
        job_prompt=$(echo "$entry" | jq -r '.prompt_file // ""')
        # id(schedule) — clickable hyperlink to prompt file if available, cyan text
        if [ -n "$job_prompt" ] && [ -f "$job_prompt" ]; then
            printf '\033]8;;file://%s\033\\' "$job_prompt"
            printf '\033[96m%s(%s)\033[0m' "$job_id" "$job_sched"
            printf '\033]8;;\033\\'
        else
            printf '\033[96m%s(%s)\033[0m' "$job_id" "$job_sched"
        fi
        # Session short ID in gray
        [ -n "$job_sess" ] && printf ' \033[90m[%s]\033[0m' "$job_sess"
        # Project path in gray
        [ -n "$job_proj" ] && printf ' \033[90m%s\033[0m' "$job_proj"
        # cron-countdown.py PID (for easy kill if stale)
        [ -n "$cron_countdown_pid" ] && printf ' \033[90mpid:%s\033[0m' "$cron_countdown_pid"
        # Last 5 versioned history links — numbered 1=newest
        history_dir="$HOME/.claude/state/cron-history/${job_id}"
        if [ -d "$history_dir" ]; then
            version_num=1
            while IFS= read -r vfile; do
                [ -f "$vfile" ] || continue
                printf ' \033[90m'
                printf '\033]8;;file://%s\033\\' "$vfile"
                printf 'v%s' "$version_num"
                printf '\033]8;;\033\\'
                printf '\033[0m'
                version_num=$((version_num + 1))
                [ "$version_num" -gt 5 ] && break
            done < <(ls -t "$history_dir"/*.md 2>/dev/null)
        fi
        printf '\n'
    done < <(jq -c '.[]' "$cron_state_file" 2>/dev/null)
fi
