#!/bin/bash
# FILE-SIZE-OK
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

# probe_direct — antifragile invariant for outbound network probes.
#
# The statusline must be a faithful mirror of system state, not a victim of
# whatever proxy state the host imposes on it. Parent processes (notably
# ccmax-claude's bearer-pin wrapper) inject HTTPS_PROXY=http://127.0.0.1:<port>
# into every child's env to MITM api.anthropic.com — but that local proxy
# returns 502 Bad Gateway for every CONNECT target it isn't programmed to
# intercept, including api.github.com. Without this guard, every `gh api`
# call from the statusline would 502 → the (?) visibility badge would
# permanently replace (private)/(public), and `gh release view` would
# permanently surface `⌁ offline` even though the network is fine.
#
# Strip both UPPER and lower variants because curl/git/gh each honor a
# different subset. NO_PROXY is left intact (defensive whitelist, harmless).
#
# Invariant pinned by the "all outbound network calls use probe_direct"
# bats test in tests/test_statusline.bats — any new gh/curl(https://) call
# MUST be wrapped, or the lint test fails.
#
# CALL PATTERN — probe_direct goes FIRST, before timeout/gh/curl:
#     probe_direct timeout 2 gh api ...    ✓ correct
#     timeout 2 probe_direct gh api ...    ✗ wrong: `timeout` execs a real
#                                          binary and cannot see shell
#                                          functions, errors with
#                                          "No such file or directory".
# Inside the function body, `env -u ...` execs whatever was passed (timeout,
# gh, curl) as a real binary lookup against PATH, which is what we want.
probe_direct() {
    env -u HTTPS_PROXY -u HTTP_PROXY -u ALL_PROXY \
        -u https_proxy -u http_proxy -u all_proxy \
        "$@"
}

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

# Append raw statusline data to JSONL for analytics (ccmax-monitor analytics package)
# Format matches ccost's expected schema: {"ts":<unix_epoch>,"data":<stdin_json>}
echo "{\"ts\":$(date +%s),\"data\":$input}" >> "$HOME/.claude/statusline.jsonl" 2>/dev/null

# Extract fields.
#
# Perf (iter-30 statusline-input-payload-tsv-batch-decode): pre-iter-30 the
# statusline spawned FIVE jq processes for five top-level input fields
# (model, session_id, transcript_path, cost, git_branch) — each ~7-10ms
# cold-start on macOS, so ~35-50ms of overhead PER STATUSLINE REFRESH just
# to decode the input JSON. The statusline refreshes every few seconds so
# the cost compounds across every session.
#
# One TSV-batched jq + bash `read` decodes all five at once. The model
# field still gets post-processed with sed (Claude → display compactor)
# but the JSON-extraction step is now a single spawn. The trailing-tab
# fallback via printf keeps `read` happy if jq dies.
IFS=$'\t' read -r model_raw session_id transcript_file cost git_branch <<< "$(
    echo "$input" | jq -r '"\(.model.display_name // .model.id // .model // "Unknown")\t\(.session_id // "")\t\(.transcript_path // "")\t\(.cost.total_cost_usd // "")\t\(.git.branch // "")"' 2>/dev/null \
        || printf 'Unknown\t\t\t\t'
)"
model=$(echo "$model_raw" | sed 's/Claude //' | sed 's/ 4.5/4.5/')

# === Session Chain (Bun-based) ===
# Traces session ancestry, displays last 5 sessions with arrows
# All in gray for uniform, non-distracting reference display
session_chain=""
if [ -n "$session_id" ] && command -v bun >/dev/null 2>&1; then
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
# Instead, try to read from transcript file or show cost.
# (transcript_file already TSV-batched above in iter-30 input-payload decode.)
ctx_display=""

if [ -n "$transcript_file" ] && [ -f "$transcript_file" ]; then
    # Try to get token count from last line of transcript.
    # Perf (iter-30 transcript-last-line-tsv-batch): pre-iter-30 this block
    # spawned TWO jq processes (one per token field). Single TSV-batched
    # jq + bash `read` decodes both at once. Saves ~10ms per refresh when
    # a transcript exists. Fallback via printf '\t' keeps `read` happy if
    # jq dies (e.g. malformed last-line JSON) — both vars default to empty.
    last_line=$(tail -1 "$transcript_file" 2>/dev/null)
    if [ -n "$last_line" ]; then
        IFS=$'\t' read -r input_tok output_tok <<< "$(
            echo "$last_line" | jq -r '"\(.usage.input_tokens // "")\t\(.usage.output_tokens // "")"' 2>/dev/null \
                || printf '\t'
        )"

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

# Fallback: show cost if no token count available.
# (cost already TSV-batched above in iter-30 input-payload decode; empty-string
# defaults from the TSV become the "no cost available" branch here.)
if [ -z "$ctx_display" ]; then
    if [ -n "$cost" ]; then
        cost_formatted=$(printf "%.2f" "$cost" 2>/dev/null || echo "$cost")
        ctx_display="\$${cost_formatted}"
    else
        ctx_display="N/A"
    fi
fi

# Git info - try JSON first, fallback to direct git commands.
# (git_branch already TSV-batched above in iter-30 input-payload decode.)
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

# Extract owner/repo early — needed by both version lookup and visibility check
owner_repo=""
remote_url_raw=$(git remote get-url origin 2>/dev/null)
if [ -n "$remote_url_raw" ]; then
    owner_repo=$(echo "$remote_url_raw" | sed -E 's|\.wiki\.git$||; s|\.wiki$||' | sed -E 's|.*github\.com[^:]*:([^/]+/[^/.]+)(\.git)?$|\1|; s|https://github\.com/||; s|\.git$||')
fi

# Latest release from GitHub (semantic-release SSoT, not local tags which may
# include GSD milestone tags like v2.0/v2.1 that sort above semver releases).
# Tri-state: real release → version+age; API-says-no-release → ∅ rel; gh broken → ⌁ offline.
# `gh` returns exit 1 for both "release not found" AND auth/network failures, so we
# pattern-match stderr to tell them apart instead of trusting exit code alone.
if [ -n "$owner_repo" ]; then
    # Iter 19 (2026-05-19) — 5-minute disk cache. gh release view costs ~460ms
    # per call (network round-trip to api.github.com). Latest release rarely
    # changes within a 5-min window; semantic-release ships <1/hour typically.
    # Cache hits skip the network entirely. Auth/network errors are NOT cached
    # (they should retry). "release not found" IS cached (it's a stable state).
    release_cache_dir=$(git rev-parse --git-dir 2>/dev/null)
    release_cache_file="${release_cache_dir:-/tmp}/ccstatusline-gh-release-cache"
    release_cache_age=9999
    [ -f "$release_cache_file" ] && release_cache_age=$(($(date +%s) - $(stat -f %m "$release_cache_file" 2>/dev/null || echo 0)))
    if [ "$release_cache_age" -lt 300 ]; then
        release_out=$(cat "$release_cache_file")
        release_exit=0
    else
        release_out=$(probe_direct timeout 2 gh release view --repo "$owner_repo" --json tagName,publishedAt -q '.tagName + "|" + .publishedAt' 2>&1)
        release_exit=$?
        if { [ $release_exit -eq 0 ] && [ -n "$release_out" ]; } || [[ "$release_out" == *"release not found"* ]]; then
            echo "$release_out" > "$release_cache_file" 2>/dev/null
        fi
    fi
    if [ $release_exit -eq 0 ] && [ -n "$release_out" ]; then
        latest_tag="${release_out%%|*}"
        published_at="${release_out##*|}"
        # Convert ISO 8601 publishedAt (UTC) to epoch for reltime
        tag_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$published_at" "+%s" 2>/dev/null || echo "")
        tag_age=""
        if [ -n "$tag_epoch" ]; then
            tag_age=" ${BRIGHT_BLACK}$(reltime "$tag_epoch")${RESET}"
        fi
        git_changes="${git_changes} ${BRIGHT_BLACK}|${RESET} ${CYAN}${latest_tag}${RESET}${tag_age}"
    elif [[ "$release_out" == *"release not found"* ]]; then
        # gh succeeded talking to the API; the API just has no release for this repo
        git_changes="${git_changes} ${BRIGHT_BLACK}| ∅ rel${RESET}"
    else
        # Genuine failure: timeout (124), gh missing (127), HTTP 4xx/5xx, network unreachable
        git_changes="${git_changes} ${BRIGHT_BLACK}| ⌁ offline${RESET}"
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
# Handles standard repos and wiki repos (*.wiki.git → /wiki URL)
#
# Iter 18 (2026-05-19): take the remote URL as a positional arg instead of
# re-running `git remote get-url origin`. The caller already captured it as
# $remote_url_raw at the top of the script (line ~298). Each git-remote
# subprocess was ~450ms on this Mac; eliminating the second call shaves
# the same amount off every render.
get_github_url() {
    local remote_url="$1"

    if [[ -z "$remote_url" ]]; then
        echo ""
        return
    fi

    # Detect wiki repos before stripping .git suffix
    local is_wiki=false
    if [[ "$remote_url" == *.wiki.git || "$remote_url" == *.wiki ]]; then
        is_wiki=true
    fi

    # Convert SSH format to HTTPS
    # git@github.com-terrylica:terrylica/repo.git -> https://github.com/terrylica/repo
    # git@github.com:user/repo.git -> https://github.com/user/repo
    # Also handles wiki: Eon-Labs/kb.wiki.git -> https://github.com/Eon-Labs/kb/wiki
    local https_url
    https_url=$(echo "$remote_url" | sed -E 's|git@github\.com[^:]*:|https://github.com/|' | sed 's|\.wiki\.git$||; s|\.wiki$||; s|\.git$||')

    if $is_wiki; then
        echo "${https_url}/wiki"
    else
        # Add branch path if not on main/master
        local branch
        branch=$(git branch --show-current 2>/dev/null)
        if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
            echo "${https_url}/tree/${branch}"
        else
            echo "$https_url"
        fi
    fi
}

github_url=$(get_github_url "$remote_url_raw")

# Repo visibility (public/private) — live query per render.
# Tri-state: known visibility → "public"/"private"; gh-broken → "?" (rendered red);
# repo-genuinely-missing-or-no-access (HTTP 404) → empty (badge hidden, same as no remote).
# Pre-fix: any gh failure silently disappeared the badge — no signal that auth/network broke.
repo_visibility=""
if [[ -n "$github_url" && -n "$owner_repo" ]]; then
    # Iter 19 (2026-05-19) — 60-minute disk cache. Visibility hardly ever
    # changes; an hour TTL keeps the badge fresh enough while removing ~430ms
    # of network round-trip per render. Auth errors NOT cached; "public" and
    # "private" ARE cached.
    vis_cache_dir=$(git rev-parse --git-dir 2>/dev/null)
    vis_cache_file="${vis_cache_dir:-/tmp}/ccstatusline-gh-visibility-cache"
    vis_cache_age=9999
    [ -f "$vis_cache_file" ] && vis_cache_age=$(($(date +%s) - $(stat -f %m "$vis_cache_file" 2>/dev/null || echo 0)))
    if [ "$vis_cache_age" -lt 3600 ]; then
        vis_out=$(cat "$vis_cache_file")
        vis_exit=0
    else
        vis_out=$(probe_direct timeout 2 gh api "repos/${owner_repo}" --jq 'if .private then "private" else "public" end' 2>&1)
        vis_exit=$?
        if [ $vis_exit -eq 0 ] && [[ "$vis_out" == "public" || "$vis_out" == "private" ]]; then
            echo "$vis_out" > "$vis_cache_file" 2>/dev/null
        fi
    fi
    if [ $vis_exit -eq 0 ] && [ -n "$vis_out" ]; then
        repo_visibility="$vis_out"
    elif [[ "$vis_out" == *"HTTP 404"* ]]; then
        repo_visibility=""  # repo doesn't exist or no read access — leave badge off
    else
        repo_visibility="?"  # auth, network, timeout, gh-missing — surface a marker
    fi
fi

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

# === ccmax-monitor: Active Account + 7d Reset + Pin Mode ===
# Fetches from ccmax-monitor Dashboard API, cached for 60s to avoid network spam.
# Endpoint: localhost:18095 (forwarded by ssh-tunnel-companion to bigblack:8095).
# ccmax-monitor binds 127.0.0.1 only — must be reached via SSH tunnel.
# Network: Tailscale primary (bigblack.tail0f299b.ts.net), CF Access fallback.
# Appended inline to datetime line: ... UTC | ... PDT | usalchemist 88% 1d 22h
#
# Pin-scope+mode badge (HEART-23 v2; requires ccmax-monitor with layered-pin
# support — graceful fallback to legacy device-only path if missing).
#
# The pin file format is layered: a single Mac can have pins at three
# scopes simultaneously, walked in this precedence:
#   1. session — ~/.config/ccmax/pin-by-session/<session-uuid>.toml  (highest)
#   2. repo    — ~/.config/ccmax/pin-by-repo/<md5-prefix-8>.toml
#   3. device  — ~/.config/ccmax/pin.toml                            (lowest)
# The first hit wins.
#
# We surface the WINNING scope in the badge so the user sees which layer is
# active, not just the mode:
#   default rotation → empty badge
#   session-soft     → [session:soft]    (yellow)
#   session-strict   → [session:strict]  (red)
#   repo-soft        → [repo:soft]       (yellow)
#   repo-strict      → [repo:strict]     (red)
#   device-soft      → [device:soft]     (yellow)  — replaces legacy [soft]
#   device-strict    → [device:strict]   (red)     — replaces legacy [strict]
#
# Resolution path (with graceful fallback for users without ccmax):
#   1. If ccmax-monitor's pin-helper.sh is installed at the marketplace path,
#      source it and call ccmax_resolve_layered_pin (~2 ms cost via awk).
#   2. Else if the legacy device-only ~/.config/ccmax/pin.toml exists, fall
#      back to a tiny inline awk parser (this is what every cc-skills user
#      gets if they don't have ccmax installed; the file legitimately won't
#      exist for them and the parser cleanly returns empty).
ccmax_pin_scope=""
ccmax_pin_mode=""
ccmax_pin_account=""
ccmax_pin_account_mode=""
CCMAX_PIN_HELPER_PATH="${HOME}/.claude/plugins/marketplaces/ccmax/hooks/pin-helper.sh"
CCMAX_PIN_DEVICE_FILE="${HOME}/.config/ccmax/pin.toml"

if [ -f "$CCMAX_PIN_HELPER_PATH" ]; then
    # Layered-pin path: source the helper and call the awk single-pass resolver.
    # We can't read the live session_id here (the statusline JSON does carry
    # it, but we want the badge to also be correct DURING the SessionStart
    # boundary when no JSONL exists yet). So we pass the session_id
    # extracted from the stdin JSON if available, else empty — the resolver
    # then considers only repo + device scopes, which is the desired
    # behavior at SessionStart.
    _ccmax_pin_layered_resolved=$(
        # shellcheck source=/dev/null
        source "$CCMAX_PIN_HELPER_PATH" 2>/dev/null \
            && if declare -F ccmax_resolve_layered_pin_with_account_mode >/dev/null 2>&1; then
                ccmax_resolve_layered_pin_with_account_mode "${session_id:-}" "$PWD" 2>/dev/null
            else
                ccmax_resolve_layered_pin "${session_id:-}" "$PWD" 2>/dev/null
            fi
    ) || _ccmax_pin_layered_resolved="|||none"
    # Formats:
    #   New helper: <account>|<mode>|<scope>|<account_mode>
    #   Old helper: <account>|<mode>|<scope>
    ccmax_pin_account="${_ccmax_pin_layered_resolved%%|*}"
    _ccmax_pin_layered_rest="${_ccmax_pin_layered_resolved#*|}"
    ccmax_pin_mode="${_ccmax_pin_layered_rest%%|*}"
    _ccmax_pin_layered_rest="${_ccmax_pin_layered_rest#*|}"
    ccmax_pin_scope="${_ccmax_pin_layered_rest%%|*}"
    ccmax_pin_account_mode="${_ccmax_pin_layered_rest#*|}"
    if [ "$ccmax_pin_account_mode" = "$ccmax_pin_scope" ]; then
        ccmax_pin_account_mode=""
    fi
    [ "$ccmax_pin_scope" = "none" ] && { ccmax_pin_scope=""; ccmax_pin_mode=""; ccmax_pin_account=""; ccmax_pin_account_mode=""; }
elif [ -f "$CCMAX_PIN_DEVICE_FILE" ]; then
    # Legacy fallback for older ccmax-monitor installs OR cc-skills users
    # without ccmax-monitor at all (in which case the file simply won't
    # exist and both vars stay empty, producing no badge).
    _ccmax_pin_legacy_combined=$(awk '
        {
            sub(/^[[:space:]]+/, ""); sub(/^#.*$/, "")
            eq = index($0, "="); if (eq == 0) next
            key = substr($0, 1, eq - 1); val = substr($0, eq + 1)
            sub(/[[:space:]]+$/, "", key)
            sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]*#.*$/, "", val); sub(/[[:space:]]+$/, "", val)
            gsub(/^["'\'']|["'\'']$/, "", val)
            if (key == "account") account_value = val
            else if (key == "mode") mode_value = val
            else if (key == "account_mode") account_mode_value = val
        }
        END {
            if (mode_value == "") mode_value = "soft"
            printf "%s|%s|%s\n", account_value, mode_value, account_mode_value
        }
    ' "$CCMAX_PIN_DEVICE_FILE" 2>/dev/null) || _ccmax_pin_legacy_combined="||"
    if [ -n "${_ccmax_pin_legacy_combined%%|*}" ]; then
        ccmax_pin_account="${_ccmax_pin_legacy_combined%%|*}"
        _ccmax_pin_legacy_rest="${_ccmax_pin_legacy_combined#*|}"
        ccmax_pin_scope="device"
        ccmax_pin_mode="${_ccmax_pin_legacy_rest%%|*}"
        ccmax_pin_account_mode="${_ccmax_pin_legacy_rest#*|}"
    fi
fi
unset _ccmax_pin_layered_resolved _ccmax_pin_layered_rest _ccmax_pin_legacy_combined _ccmax_pin_legacy_rest

ccmax_bearer_account=""
if [ "$ccmax_pin_account_mode" = "bearer_key_anthropic_compatible_api_mode" ] && [ -n "$ccmax_pin_account" ]; then
    ccmax_bearer_account="$ccmax_pin_account"
elif [ -n "${CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION:-}" ]; then
    ccmax_bearer_account="$CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION"
elif [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    case "$ANTHROPIC_BASE_URL" in
        *bigblack.tail0f299b.ts.net:8450*|*127.0.0.1:8450*|*localhost:8450*)
            ccmax_bearer_account="el02-doorward-bearer-api-1"
            ;;
    esac
fi

# === Doorward Gateway Health (replaces legacy OAuth-account/quota block) ===
#
# WHY THE REWRITE: Fleet migrated to bearer-mode routing where ccmax-claude PTY
# wrapper sets ANTHROPIC_BASE_URL=https://bigblack.tail0f299b.ts.net:8450 and
# doorward picks from a rotation pool of OAuth accounts dynamically per-request.
# The local keychain's OAuth account no longer tells you what's serving you, so
# the prior "account email + 5h%/7d% quota windows" rendering became misleading
# (it described a credential that isn't even being used). We replaced it with
# four signals that actually reflect the live pipeline:
#
#   1. Gate health badge   — composite of doorward reachability + canary state
#   2. Pool size           — pool.schedulable_active_accounts / pool.total_accounts
#   3. Canary state        — canary_self_test.consecutive_failures count
#   4. Wrapper version     — local ccmax-claude version vs doorward's floor
#
# Only two doorward routes are wrapper-version-gate-exempt and therefore safe
# for the statusline to hit anonymously on every render:
#   GET /v1/health         → liveness + canary + fleet transition counters
#   GET /v1/router-status  → adds the pool breakdown (per-account schedulable)
# We use the latter because it's a superset (canary + pool in one fetch).
# Confirmed bypass paths: spike-11/src/main.rs:1492,1505 (health) and 1515,1556
# (router-status). Both responses include x-doorward-decision and
# x-doorward-router-version headers for forensics.
#
# Cache: /tmp/ccmax-doorward-cache.json, 60s TTL. doorward already enforces a
# 30s server-side TTL on /v1/router-status (spike-11 cache_ttl_seconds), so 60s
# client-side covers two server windows with headroom. Stale-on-failure: if a
# fresh fetch fails but a cache exists, we render with stale cache rather than
# blanking — the operator still sees something instead of a false "unreachable".
#
# Failure semantics (drives $doorward_status string — used downstream to pick
# the render branch and per-token color, no longer a leading visual glyph):
#   reachable + status=ok + canary healthy + errors=0  → "healthy"    (all gray/✓)
#   reachable but canary degraded OR errors>0          → "degraded"   (red ✗N or red ratio)
#   unreachable / no cache                             → "unreachable" (literal red word replaces numerics)
#   /v1/router-status JSON parse failure               → "parse-error" (red word replaces numerics)
#
# Public cc-skills users (no doorward, no tailnet membership) get curl timeout
# → "unreachable" state → if they also have no bearer-mode env signal AND no
# pin, the entire ccmax line is suppressed (see renderer below). Graceful
# degradation.

DOORWARD_BASE="https://bigblack.tail0f299b.ts.net:8450"
DOORWARD_CACHE="/tmp/ccmax-doorward-cache.json"
DOORWARD_CACHE_TTL=60

# Doorward's minimum wrapper version floor — AUTO-DISCOVERED (L1a, 2026-05-13).
#
# Earlier versions hardcoded "1.2.0" here and required a manual bump whenever
# doorward raised its gate. Now we discover the live floor by probing any
# wrapper-gated route (e.g. /v1/users/me) WITHOUT the wrapper version header;
# doorward returns HTTP 403 with `minimum_wrapper_version_required` in the
# JSON body, which IS the current floor. Cached at /tmp/ccmax-doorward-floor
# with a 3600s TTL so we only probe doorward once per hour for this value.
#
# Probe failure modes (any → fall back to compiled-in default):
#   - Doorward unreachable: probe times out, no response
#   - Doorward returns 200 (gate disabled / env var unset): no floor to read
#   - Response body doesn't have the expected error.minimum_wrapper_version_required shape
# The fallback ensures the renderer always has SOMETHING to compare against,
# even when doorward is down. The fallback is updated whenever a fresh probe
# succeeds, so cold-start with a stale fallback only matters for the very
# first render after a new install.
DOORWARD_MIN_WRAPPER_VERSION_FALLBACK="1.2.0"
DOORWARD_FLOOR_CACHE="/tmp/ccmax-doorward-floor"
DOORWARD_FLOOR_TTL=3600  # 1 hour

# Cache-aware floor lookup. The cache file holds a single line containing the
# discovered floor semver (or empty if discovery failed). On cache miss or
# expiry, probe doorward; on probe failure, fall back to compiled-in default.
DOORWARD_MIN_WRAPPER_VERSION=""
if [ -f "$DOORWARD_FLOOR_CACHE" ]; then
    floor_cache_mtime=$(stat -f %m "$DOORWARD_FLOOR_CACHE" 2>/dev/null || echo 0)
    floor_cache_age=$(( $(date +%s) - floor_cache_mtime ))
    if [ "$floor_cache_age" -lt "$DOORWARD_FLOOR_TTL" ]; then
        DOORWARD_MIN_WRAPPER_VERSION=$(cat "$DOORWARD_FLOOR_CACHE" 2>/dev/null)
    fi
fi
if [ -z "$DOORWARD_MIN_WRAPPER_VERSION" ]; then
    # Probe a wrapper-gated route anonymously. The gate runs BEFORE auth, so
    # even without a Bearer header we elicit a 403 with the JSON body that
    # carries `minimum_wrapper_version_required`. Implementation note: the
    # `probe_direct curl` call below uses `-s` (NOT `-sf`) because `-f`
    # suppresses the response body on 4xx — and the body is exactly what we
    # need to parse.
    discovered_floor=$(probe_direct curl -s --connect-timeout 1 --max-time 2 \
        "${DOORWARD_BASE}/v1/users/me" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    err = d.get('error', {}) or {}
    floor = err.get('minimum_wrapper_version_required', '') or ''
    print(floor)
except Exception:
    pass
" 2>/dev/null) || discovered_floor=""
    if [ -n "$discovered_floor" ]; then
        printf '%s' "$discovered_floor" > "$DOORWARD_FLOOR_CACHE"
        DOORWARD_MIN_WRAPPER_VERSION="$discovered_floor"
    else
        DOORWARD_MIN_WRAPPER_VERSION="$DOORWARD_MIN_WRAPPER_VERSION_FALLBACK"
    fi
fi

# Fetch /v1/router-status (cache-aware).
doorward_raw=""
doorward_needs_fetch=1
if [ -f "$DOORWARD_CACHE" ]; then
    doorward_cache_mtime=$(stat -f %m "$DOORWARD_CACHE" 2>/dev/null || echo 0)
    doorward_cache_age=$(( $(date +%s) - doorward_cache_mtime ))
    [ "$doorward_cache_age" -lt "$DOORWARD_CACHE_TTL" ] && doorward_needs_fetch=0
fi
if [ "$doorward_needs_fetch" -eq 1 ]; then
    doorward_fresh=$(probe_direct curl -sf --connect-timeout 1 --max-time 2 \
        "${DOORWARD_BASE}/v1/router-status" 2>/dev/null) || doorward_fresh=""
    if [ -n "$doorward_fresh" ]; then
        echo "$doorward_fresh" > "$DOORWARD_CACHE"
        doorward_raw="$doorward_fresh"
    elif [ -f "$DOORWARD_CACHE" ]; then
        # Fetch failed but cache exists → render stale data rather than going
        # dark. The cache mtime already telegraphs staleness to anyone reading
        # the file directly.
        doorward_raw=$(cat "$DOORWARD_CACHE" 2>/dev/null) || doorward_raw=""
    fi
else
    doorward_raw=$(cat "$DOORWARD_CACHE" 2>/dev/null) || doorward_raw=""
fi

# Local ccmax-claude wrapper version (cached by binary mtime). The subprocess
# only re-runs when the binary file itself changes — rare — so the render-time
# cost amortizes to a file stat per render. Empty when the wrapper isn't
# installed (public cc-skills users), which the renderer treats as "skip the
# wrapper segment entirely".
WRAPPER_BIN="${HOME}/.local/bin/ccmax-claude"
WRAPPER_VERSION_CACHE="/tmp/ccmax-wrapper-version"
wrapper_version=""
if [ -x "$WRAPPER_BIN" ]; then
    wrapper_bin_mtime=$(stat -f %m "$WRAPPER_BIN" 2>/dev/null || echo 0)
    wrapper_cache_mtime=$(stat -f %m "$WRAPPER_VERSION_CACHE" 2>/dev/null || echo 0)
    if [ -f "$WRAPPER_VERSION_CACHE" ] && [ "$wrapper_cache_mtime" -ge "$wrapper_bin_mtime" ]; then
        wrapper_version=$(cat "$WRAPPER_VERSION_CACHE" 2>/dev/null)
    else
        wrapper_version=$("$WRAPPER_BIN" --version 2>/dev/null | head -1 | tr -d ' \n')
        [ -n "$wrapper_version" ] && printf '%s' "$wrapper_version" > "$WRAPPER_VERSION_CACHE"
    fi
fi

# Semver less-than via sort -V. Returns 0 (true) when $1 < $2.
version_lt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

# Parse the doorward snapshot into primitives. One python invocation emits a
# fixed-shape pipe-delimited line; shell unpacks with `IFS='|' read`. Output:
#   <status>|<schedulable>|<rotation_size>|<errors>|<canary_failures>|<canary_class>
# status      ∈ {healthy, degraded, parse-error}; unreachable is signalled by
#               empty doorward_raw before we enter this block
# canary_class ∈ {healthy, since-start-failure, transient, recent-degradation,
#               unknown} — see classification rules below
#
# Pool denominator semantics — we deliberately EXCLUDE inactive accounts from
# the denominator. doorward's response distinguishes three account states:
#   - schedulable + status=active   → in the rotation, picking traffic
#   - error_accounts                → in the rotation, currently failing
#   - other_status_accounts         → administratively inactive (paused,
#                                     not part of the rotation by operator
#                                     intent — NOT a failure mode)
# Including inactive accounts in the denominator (the prior `pool 3/4` form)
# was misleading because it visually framed an operator-intended deactivation
# as a partial pool failure. We use `schedulable + errors` as the denominator,
# which is the actual rotation working-set size: "how many accounts are
# expected to be able to serve, and how many of those actually can right now".
#
# Canary classification (L1b, 2026-05-13) — replaces the prior binary
# "degraded vs healthy" flag with a four-state model that distinguishes
# operationally-meaningful failure modes:
#
#   healthy              consecutive_failures == 0
#                        → the canary just succeeded; nothing to see here.
#
#   since-start-failure  success_runs == 0 AND consecutive_failures == total_runs
#                        → the canary has NEVER succeeded since the router
#                          process started. This is the fingerprint of a
#                          config bug (e.g. canary's request missing a
#                          required header). It is NOT evidence of upstream
#                          trouble — if upstream were broken, the canary
#                          would have at least ONE prior success at boot.
#                          Renderer dims this in gray instead of red.
#
#   transient            0 < consecutive_failures < consecutive_failure_threshold
#                        → canary had successes before, currently has a small
#                          run of failures below the alarm threshold. Worth
#                          watching, not yet worth paging.
#
#   recent-degradation   consecutive_failures >= consecutive_failure_threshold
#                        AND success_runs > 0 (i.e. NOT since-start-failure)
#                        → canary worked at some point, now degraded past the
#                          alarm threshold. This is the "real outage" signal.
#
#   unknown              canary fields absent or unreadable
#                        → fail-safe to "degraded color" so we don't silently
#                          hide a real problem behind missing data.
# All ten primitives below feed the unified renderer further down.
doorward_status="unreachable"
pool_schedulable=0
pool_rotation_size=0
pool_errors=0
# canary_failures retained as a parsed primitive even though the L1d
# renderer prefers humanized duration over raw count; downstream task #7 (L2
# statistics surface) will append this to the per-render JSONL log.
# shellcheck disable=SC2034
canary_failures=0
canary_class="unknown"
canary_failure_type_code_AU_QT_CF_UP_IN=""
pool_resilience_state_machine_label=""
unified_state_name_for_render_label=""
canary_failure_duration_humanized_short_form=""
if [ -n "$doorward_raw" ]; then
    doorward_parsed=$(echo "$doorward_raw" | python3 -c "
import sys, json

# ===========================================================================
# L1d UNIFIED-RENDER PRIMITIVE EXTRACTOR (cc-skills statusline, 2026-05-13)
# ===========================================================================
# Reads doorward's /v1/router-status response and emits a single pipe-delimited
# line of 10 primitives that the shell side unpacks via IFS='|' read. The
# verbose field names below match the names exported to shell-side variables
# downstream so a future reader can grep across the python<->bash boundary.
# Design contract documented in:
#   ccmax-monitor/HANDOFF-CC-SKILLS-STATUSLINE-DOORWARD-TELEMETRY-REDESIGN-AND-PATH-A-REPO-MERGE-2026-05-13.md
# Output line shape:
#   <gate_status>|<pool_schedulable>|<pool_rotation_size>|<pool_errors>
#    |<canary_consecutive_failures>|<canary_classification_four_state>
#    |<canary_failure_type_code_AU_QT_CF_UP_IN>
#    |<pool_resilience_state_machine_label>
#    |<unified_state_name_for_render_label>
#    |<canary_failure_duration_humanized_short_form>

def derive_canary_failure_type_code_from_last_observed_http_status(
    last_observed_http_status_code_from_canary_self_test_block,
):
    # RFC 9110 status-class taxonomy collapsed onto the operationally-distinct
    # 5-code shape we render in the statusline. Citation taxonomy:
    # RFC 9457 (problem+json), Envoy cluster_stats upstream_rq_* metric groups,
    # AWS API Gateway 4XXError/5XXError separation, Cloudflare Tunnel error
    # categorization (auth/policy/upstream/network/internal). Single source
    # signal today is canary_self_test.last_observed_http_status_code; richer
    # per-account reasons require L3 server work (task #8).
    s = int(last_observed_http_status_code_from_canary_self_test_block or 0)
    if s == 0:
        # Canary couldn't complete the HTTP request at all — network or
        # timeout before status was observed. Treat as upstream-unavailable.
        return 'UP'
    if s in (401, 403):
        return 'AU'  # Auth / credential / version-gate rejection
    if s in (429, 509):
        return 'QT'  # Quota / rate-limit / throttle
    if s in (400, 422):
        return 'CF'  # Client / schema / policy-deny
    if s in (502, 503, 504):
        return 'UP'  # Upstream unavailable / pool exhausted / gateway timeout
    if 500 <= s <= 599:
        return 'IN'  # Internal / proxy bug / 500 from our own gateway
    return ''        # Status 2xx/3xx (shouldn't happen on a 'failure' branch)

def derive_pool_resilience_state_machine_label_from_schedulable_and_rotation_size(
    schedulable_active_accounts_count, rotation_working_set_size,
):
    # Envoy outlier-detection + Resilience4j circuit-breaker state machine
    # adapted to a finite N-account rotation pool. The PARTIAL_OUTAGE state
    # (schedulable == 1) is the canonical pre-warning gate: one more failure
    # = total outage. Operators read this as 'pool has no resilience left,
    # intervene before next failure'.
    if rotation_working_set_size == 0:
        return 'unknown'
    if schedulable_active_accounts_count == 0:
        return 'total-outage'
    if schedulable_active_accounts_count == 1 and rotation_working_set_size >= 2:
        return 'partial-outage'
    if schedulable_active_accounts_count < rotation_working_set_size:
        return 'degraded'
    return 'healthy'

def compose_unified_state_name_for_render_label_from_canary_class_and_pool_state(
    canary_classification_four_state, pool_resilience_state,
):
    # Single label combining the canary's failure classification with the
    # pool's resilience state, taking the worst-of via this severity-ranked
    # precedence (highest to lowest):
    #   outage (red)       ← pool total-outage OR canary recent-degradation
    #   partial-outage (yellow) ← pool partial-outage (last-account-standing)
    #   flapping (yellow)  ← pool degraded OR canary transient
    #   since-boot (gray)  ← canary never-succeeded-since-router-start config bug
    #   healthy (green)    ← both signals report no failure
    if pool_resilience_state == 'total-outage':
        return 'outage'
    if canary_classification_four_state == 'recent-degradation':
        return 'outage'
    if pool_resilience_state == 'partial-outage':
        return 'partial-outage'
    if pool_resilience_state == 'degraded':
        return 'flapping'
    if canary_classification_four_state == 'transient':
        return 'flapping'
    if canary_classification_four_state == 'since-start-failure':
        return 'since-boot'
    if canary_classification_four_state == 'healthy' and pool_resilience_state == 'healthy':
        return 'healthy'
    return 'unknown'

def format_seconds_as_humanized_short_duration_with_no_ago_suffix(total_seconds):
    # Same humanization grammar as the existing reltime() bash helper but
    # without the trailing ' ago'. Output examples: '8s', '47m', '18h', '3d',
    # '5w'. Output is intentionally fixed-precision (no fractional units) to
    # keep the rendered token width predictable.
    s = int(max(0, total_seconds))
    if s < 60:
        return f'{s}s'
    if s < 3600:
        return f'{s // 60}m'
    if s < 86400:
        return f'{s // 3600}h'
    if s < 604800:
        return f'{s // 86400}d'
    return f'{s // 604800}w'

try:
    d = json.loads(sys.stdin.read())
    pool = d.get('pool', {}) or {}
    schedulable_active_accounts_count = int(pool.get('schedulable_active_accounts', 0) or 0)
    pool_error_accounts_count = int(pool.get('error_accounts', 0) or 0)
    rotation_working_set_size = schedulable_active_accounts_count + pool_error_accounts_count

    canary = d.get('canary_self_test', {}) or {}
    canary_consecutive_failures_count = int(canary.get('consecutive_failures', 0) or 0)
    canary_lifetime_success_runs_count = int(canary.get('success_runs', 0) or 0)
    canary_lifetime_total_runs_count = int(canary.get('total_runs', 0) or 0)
    canary_consecutive_failure_alarm_threshold = int(
        canary.get('consecutive_failure_threshold', 3) or 3
    )
    canary_configured_interval_seconds = int(
        canary.get('configured_interval_secs', 300) or 300
    )
    canary_last_observed_http_status_code = canary.get('last_observed_http_status_code', 0)

    # L1b four-state classification (unchanged from prior edit).
    if canary_consecutive_failures_count == 0:
        canary_classification_four_state = 'healthy'
    elif (
        canary_lifetime_success_runs_count == 0
        and canary_consecutive_failures_count == canary_lifetime_total_runs_count
    ):
        canary_classification_four_state = 'since-start-failure'
    elif canary_consecutive_failures_count < canary_consecutive_failure_alarm_threshold:
        canary_classification_four_state = 'transient'
    else:
        canary_classification_four_state = 'recent-degradation'

    # Gate-status binary (legacy primitive retained for backward-compat with
    # the existing $doorward_status check that triggers render-or-suppress).
    if pool_error_accounts_count > 0 or canary_classification_four_state == 'recent-degradation':
        legacy_gate_status_binary = 'degraded'
    else:
        legacy_gate_status_binary = 'healthy'

    # L1d new primitives.
    canary_failure_type_code_AU_QT_CF_UP_IN = \
        derive_canary_failure_type_code_from_last_observed_http_status(
            canary_last_observed_http_status_code,
        )
    pool_resilience_state_machine_label = \
        derive_pool_resilience_state_machine_label_from_schedulable_and_rotation_size(
            schedulable_active_accounts_count, rotation_working_set_size,
        )
    unified_state_name_for_render_label = \
        compose_unified_state_name_for_render_label_from_canary_class_and_pool_state(
            canary_classification_four_state, pool_resilience_state_machine_label,
        )
    canary_failure_duration_seconds_lower_bound = (
        canary_consecutive_failures_count * canary_configured_interval_seconds
    )
    canary_failure_duration_humanized_short_form = (
        format_seconds_as_humanized_short_duration_with_no_ago_suffix(
            canary_failure_duration_seconds_lower_bound,
        )
        if canary_consecutive_failures_count > 0 else ''
    )

    print(
        f'{legacy_gate_status_binary}'
        f'|{schedulable_active_accounts_count}'
        f'|{rotation_working_set_size}'
        f'|{pool_error_accounts_count}'
        f'|{canary_consecutive_failures_count}'
        f'|{canary_classification_four_state}'
        f'|{canary_failure_type_code_AU_QT_CF_UP_IN}'
        f'|{pool_resilience_state_machine_label}'
        f'|{unified_state_name_for_render_label}'
        f'|{canary_failure_duration_humanized_short_form}'
    )
except Exception:
    # Fail-safe shape: same 10 fields, sentinel values that the renderer
    # interprets as 'parse-error' (red, replaces numerics with the literal
    # 'parse-error' word — same UX as 'unreachable').
    print('parse-error|0|0|0|0|unknown||unknown|unknown|')
" 2>/dev/null) || doorward_parsed=""
    if [ -n "$doorward_parsed" ]; then
        IFS='|' read -r doorward_status pool_schedulable pool_rotation_size pool_errors canary_failures canary_class canary_failure_type_code_AU_QT_CF_UP_IN pool_resilience_state_machine_label unified_state_name_for_render_label canary_failure_duration_humanized_short_form <<< "$doorward_parsed"
    fi
fi

# L1c (real-traffic cross-check, 2026-05-13) — second-opinion damper on the
# canary signal. The canary is one synthetic probe; if it's degraded, that
# may or may not reflect actual upstream health. Real traffic is the ground
# truth: when this Mac's Claude Code session is actively pumping requests
# through doorward AND those requests are completing, doorward IS serving,
# regardless of what the canary says.
#
# Detection signals:
#   (a) $ANTHROPIC_BASE_URL points at doorward (bearer-mode routing) AND
#   (b) The current session's transcript JSONL has been written to within
#       the last 60s (Claude Code only appends to the transcript when it
#       successfully receives upstream responses)
#
# Effect: when both hold, downgrade the canary class by one alarm level.
# This is a damper, not a silencer — recent-degradation → transient,
# transient → since-start-failure (i.e. "config bug, not outage"). Healthy
# stays healthy. since-start-failure stays since-start-failure (already
# minimum-alarm).
#
# Why we DON'T just suppress the canary signal entirely when real traffic
# flows: the canary's interval (1-5min) doesn't perfectly align with the
# user's prompt cadence. A 5min-stale transcript with an actively-failing
# canary IS a credible early-warning of impending failure on the next
# prompt. Damper-not-silencer preserves that signal at one severity level.
real_traffic_recent=0
if [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "$transcript_file" ] && [ -f "$transcript_file" ]; then
    case "$ANTHROPIC_BASE_URL" in
        *bigblack.tail0f299b.ts.net:8450*|*127.0.0.1:8450*|*localhost:8450*)
            transcript_mtime=$(stat -f %m "$transcript_file" 2>/dev/null || echo 0)
            transcript_age=$(( $(date +%s) - transcript_mtime ))
            [ "$transcript_age" -lt 60 ] && real_traffic_recent=1
            ;;
    esac
fi
if [ "$real_traffic_recent" -eq 1 ]; then
    case "$canary_class" in
        recent-degradation) canary_class="transient" ;;
        transient)          canary_class="since-start-failure" ;;
    esac
    # Also clear pool-error escalation: if traffic is flowing, error_accounts
    # might be a transient blip the rotation is already routing around.
    if [ "$doorward_status" = "degraded" ] && [ "$pool_errors" -gt 0 ] && [ "$canary_class" != "recent-degradation" ]; then
        doorward_status="healthy"
    fi
fi

# === Code Statistics (scc) ===
# Runs scc on every render — no cache (full freshness, user-selected).
# Single jq pass extracts totals + top-3 languages + COCOMO into a colored line.
# Bounded by 1s timeout: pathologically large repos drop the line silently rather
# than hang the statusline.
code_stats=""
if command -v scc >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if command -v gtimeout >/dev/null 2>&1; then
        scc_json=$(gtimeout 1 scc --format=json2 . 2>/dev/null)
    elif command -v timeout >/dev/null 2>&1; then
        scc_json=$(timeout 1 scc --format=json2 . 2>/dev/null)
    else
        scc_json=$(scc --format=json2 . 2>/dev/null)
    fi

    if [ -n "$scc_json" ]; then
        code_stats=$(echo "$scc_json" | jq -r --arg BB "$BRIGHT_BLACK" --arg CY "$CYAN" --arg YE "$YELLOW" --arg RS "$RESET" '
            def compact(n):
                if n >= 1000000 then
                    ((n / 1000000) as $v | (if $v < 10 then ($v * 10 | floor / 10 | tostring) else ($v | floor | tostring) end) + "M")
                elif n >= 1000 then
                    ((n / 1000) as $v | (if $v < 10 then ($v * 10 | floor / 10 | tostring) else ($v | floor | tostring) end) + "k")
                else (n | tostring) end;
            def money(n):
                if n >= 1000000 then
                    ("$" + ((n / 1000000) as $v | (if $v < 10 then ($v * 10 | floor / 10 | tostring) else ($v | floor | tostring) end)) + "M")
                elif n >= 1000 then ("$" + ((n / 1000) | floor | tostring) + "k")
                else ("$" + (n | tostring)) end;
            def abbr: {"Markdown":"MD","TypeScript":"TS","JavaScript":"JS","Python":"Py","Shell":"Sh","BASH":"Bash","Bash":"Bash","C Header":"Ch","Objective C":"ObjC","Plain Text":"Txt","Swift":"Sw","Rust":"Rs","Ruby":"Rb","Kotlin":"Kt","C++":"Cpp","License":"Lic","Dockerfile":"Dock","Makefile":"Make","JSONL":"JSONL"}[.] // .[0:4];
            (.languageSummary | map(.Code) | add) as $tc |
            (.languageSummary | map(.Count) | add) as $tf |
            (.languageSummary | map(.Complexity) | add) as $tx |
            (if $tc > 0 then
                (.languageSummary | sort_by(-.Code) | .[0:3] |
                    map((.Name | abbr) + " " + ((.Code * 100 / $tc) | floor | tostring) + "%")
                    | join(" "))
             else "" end) as $top |
            (if $tx >= 1000 then $YE else $BB end) as $cxc |
            if ($tc // 0) > 0 then
                $BB + "Σ" + $RS + " " +
                $CY + compact($tc) + " LOC" + $RS + " " +
                $BB + "· " + compact($tf) + " files · " + $RS +
                $cxc + "cx " + compact($tx) + $RS + " " +
                $BB + "· " + $top + " · ~" + money(.estimatedCost // 0) + " COCOMO" + $RS
            else empty end
        ' 2>/dev/null)
    fi
fi

# Status line layout:
#   Line 1: git stats
#   Line 2: code stats (scc — LOC, files, complexity, top languages, COCOMO)
#   Line 3: UTC time | local time | ccmax (inline)
#   Line 4: ~/path | github-url
#   Line 5: session UUID (if available)
#   Line 6: ~/asciinemalogs cast UUID
line1="${git_changes}"

# Line 3: path | GitHub URL (visibility)
vis_label=""
case "$repo_visibility" in
    private) vis_label=" ${YELLOW}(private)${RESET}" ;;
    public)  vis_label=" ${BRIGHT_BLACK}(public)${RESET}" ;;
    "?")     vis_label=" ${RED}(?)${RESET}" ;;  # gh failed — auth/network/timeout
esac
if [[ -n "$github_url" ]]; then
    if [[ "$git_branch" == "main" || "$git_branch" == "master" ]]; then
        line_repo="${GREEN}${repo_path}${RESET} | ${BRIGHT_BLACK}${github_url}${RESET}${vis_label}"
    else
        line_repo="${GREEN}${repo_path}${RESET} | ${MAGENTA}${github_url}${RESET}${vis_label}"
    fi
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    line_repo="${GREEN}${repo_path}${RESET} | ${RED}⚠ no remote${RESET}"
else
    line_repo="${GREEN}${repo_path}${RESET} | ${RED}⚠ no git${RESET}"
fi

# Extract iTerm2 session UUID from environment (format: w0t1p1:UUID)
iterm_session_uuid=""
if [ -n "$ITERM_SESSION_ID" ]; then
    iterm_session_uuid=$(echo "$ITERM_SESSION_ID" | cut -d':' -f2)
fi

# Output: git stats, code stats, timestamps, repo, session, cast, then cron jobs (bottom)
echo -e "$line1"

# Code statistics (scc): LOC, files, complexity, top 3 languages, COCOMO
# Empty when scc unavailable, repo not git, or computation timed out (>1s)
[ -n "$code_stats" ] && echo -e "$code_stats"

# =============================================================================
# Doorward gateway summary — render LEGEND + SOURCE-OF-TRUTH map
# =============================================================================
#
# Final output shapes (L1d unified multi-dimensional render, 2026-05-13):
#
#   ... UTC | ... PDT | doorward 3/3 ✓ 1.93.0                                ← all healthy
#   ... UTC | ... PDT | doorward 3/3 ✗AU 3d since-boot 1.93.0                ← today (config bug, gray)
#   ... UTC | ... PDT | doorward 2/3 ⚠UP 3m flapping 1.93.0                   ← one backend transient
#   ... UTC | ... PDT | doorward 1/3 ⚠UP 12m partial-outage 1.93.0            ← last healthy account, pre-warn
#   ... UTC | ... PDT | doorward 0/3 ✗UP 47m outage 1.93.0                    ← total outage, alarm
#   ... UTC | ... PDT | doorward 3/3 ✓ 1.2.0=1.2.0                             ← wrapper exactly at floor, pre-warn
#   ... UTC | ... PDT | doorward unreachable 1.93.0                          ← gateway down
#
# The render grammar is:
#   doorward <pool-ratio> <severity-glyph><type-code> [<duration>] [<state-name>] <wrapper-version>
#
# State is conveyed entirely by per-token coloring + the named state label:
#   "all healthy"    → ✓ in GREEN, rest in BRIGHT_BLACK, no state label
#   "since-boot"     → ✗AU and "since-boot" in BRIGHT_BLACK (calm, config bug)
#   "flapping"       → ⚠<type> and "flapping" in YELLOW (watch, transient)
#   "partial-outage" → ⚠<type> and "partial-outage" in YELLOW, pool ratio also YELLOW (pre-warn — last account standing)
#   "outage"         → ✗<type> and "outage" in RED, pool ratio in RED if 0/N (alarm)
#   "wrapper skewed" → wrapper version in YELLOW with "<floor" suffix
#   "wrapper at floor" → wrapper version in YELLOW with "=floor" suffix (pre-warn)
#   "gateway down"   → literal RED word "unreachable" replaces numerics
#
# Three label-stripping rounds preceded this design (all 2026-05-13):
#   - dropped the "pool", "canary", "wrapper" field labels (redundant within
#     a segment already anchored by "doorward")
#   - dropped the leading 🟢/🟡/🔴 gate-state emoji (redundant with per-token
#     coloring + state name)
#   - retired the "[5th-fleet]" bearer-mode badge (terminology no longer used)
#
# Every visible token, including the labels we stripped, is mapped here so the
# next maintainer can re-derive what each rendered glyph means without
# re-grepping doorward's source or CLAUDE.md. Tokens are listed left-to-right
# in render order.
#
# ── Gate emoji (RETIRED 2026-05-13) ──────────────────────────────────────────
#   Earlier versions led the segment with a 🟢/🟡/🔴 dot synthesised from
#   pool.error_accounts + canary_self_test.is_degraded_per_threshold +
#   reachability. Retired because:
#     - 🟢 "all healthy" was redundant with every trailing token being gray/✓
#     - 🟡 "degraded" was redundant with the RED ✗N glyph or RED pool ratio
#     - 🔴 "unreachable" was redundant with the literal RED word "unreachable"
#   The python parser still produces $doorward_status ∈ {healthy, degraded,
#   parse-error, unreachable} because that variable drives WHICH render
#   branch runs (numeric tokens vs. "unreachable" word), but the value is
#   no longer mapped to a leading visual glyph.
#
# ── "doorward" anchor word ───────────────────────────────────────────────────
#   The single retained label. Identifies which subsystem the segment is
#   reporting on. Without it the trailing numbers would float context-free
#   after the datetime. Rendered in BRIGHT_BLACK (gray) to de-emphasise.
#
# ── "3/3"  ←  pool numerator/denominator ─────────────────────────────────────
#   Render shape: <schedulable_active>/<rotation_working_set_size>
#   Numerator   = /v1/router-status .pool.schedulable_active_accounts
#                 (accounts whose status=="active" AND schedulable==true,
#                  i.e. currently picking traffic from doorward's rotation)
#   Denominator = .pool.schedulable_active_accounts + .pool.error_accounts
#                 (the rotation WORKING-SET: accounts expected to serve,
#                  whether currently healthy or transiently failing)
#   EXCLUDED from denominator:
#                .pool.other_status_accounts (status=="inactive" — admin-
#                paused by operator intent, NOT a failure mode; including them
#                would mis-frame an intentional deactivation as partial pool
#                degradation, e.g. the 4-registered-but-1-admin-inactive fleet
#                state would mislead as "3/4" instead of the correct "3/3").
#   Color: RED when .pool.error_accounts > 0; BRIGHT_BLACK (gray) otherwise.
#   "pool" label removed — the slash-fraction format is self-evidently a ratio
#   and the segment is already anchored by "doorward".
#   Live cross-reference: pool.per_account_summaries[] in the same response
#   carries each account's {name, status, schedulable} triple if you need to
#   know WHICH account is in which state.
#
# ── "✓" or "✗AU 3d" or "⚠UP 12m"  ←  severity-glyph + type-code + duration ──
#   The L1d unified render replaced the raw consecutive-failure-count display
#   with a three-token composite that's both more glanceable and more
#   actionable. Each token answers a distinct operator question:
#
#     severity-glyph   How urgent? — ✓ (none), ⚠ (warn), ✗ (alarm or calm)
#     type-code        What kind of failure? — AU / QT / CF / UP / IN
#     duration         How long has it been failing? — humanized short form
#
#   Source primitives = /v1/router-status .canary_self_test sub-object:
#     .canary_self_test.consecutive_failures (int)            → drives classification + duration
#     .canary_self_test.success_runs (int)                    → for classification
#     .canary_self_test.total_runs (int)                      → for classification
#     .canary_self_test.consecutive_failure_threshold (int)   → alarm cutoff
#     .canary_self_test.configured_interval_secs (int)        → × failures = duration
#     .canary_self_test.last_observed_http_status_code (int)  → maps to type-code
#
#   Type-code derivation (RFC 9457 / Envoy / AWS API Gateway taxonomy):
#     401, 403         → AU (auth / credential / version-gate)
#     429, 509         → QT (quota / rate-limit / throttle)
#     400, 422         → CF (client / schema / policy-deny)
#     502, 503, 504, 0 → UP (upstream unavailable / pool exhausted / timeout)
#     500, 501, 505..  → IN (internal / proxy bug from our own gateway)
#
#   The single source of type information today is the LAST observed canary
#   status code. Richer per-account failure reasons (one type-code per pool
#   account in the rotation) require L3 server work (task #8 — extending the
#   doorward response with .pool.per_account_failure_reason[]).
#
#   Duration formula:
#     duration_secs = consecutive_failures × configured_interval_secs
#     human-readable form: '8s', '47m', '18h', '3d', '5w' (no 'ago' suffix)
#   This is a lower bound — actual duration could be slightly larger because
#   the response only reports the CURRENT consecutive run, not the precise
#   first-failure timestamp. Exact timestamps require L3 server work (adding
#   .canary_self_test.first_failure_at_unix_secs).
#
#   L1c real-traffic damper: when $ANTHROPIC_BASE_URL points at doorward AND
#   the current transcript JSONL has mtime within last 60s (= real prompts
#   are completing through doorward right now), recent-degradation gets
#   downgraded to transient, and transient gets downgraded to since-start-
#   failure. Healthy stays healthy. since-start-failure stays. Damper not
#   silencer — real traffic confirms doorward is serving, so the canary alarm
#   cannot be at "real problem" severity, but residual flapping signal is
#   kept visible.
#
#   What the canary actually IS:
#     doorward runs a Tokio task on a .canary_self_test.configured_interval_secs
#     timer (default 300s, override via DOORWARD_CANARY_INTERVAL_SECS_OVERRIDE
#     — currently set to 60s in prod). Each fire posts a synthetic /v1/messages
#     request to .canary_self_test.target_loopback_url (currently
#     http://127.0.0.1:8089/v1/messages — i.e. doorward probes ITSELF) using
#     the DOORWARD_CANARY_BEARER_API_KEY env var as Authorization. If the
#     response isn't 200 the consecutive_failures counter increments; on any
#     success the counter resets to 0. Source: cc-router/spikes/spike-11-...
#     /src/main.rs:1227-1291.
#
# ── pool-resilience state machine label (color of N/M ratio) ─────────────────
#   Source primitives:
#     .pool.schedulable_active_accounts → schedulable_active_accounts_count
#     .pool.error_accounts              → pool_error_accounts_count
#     rotation_size = schedulable + errors (admin-inactive excluded)
#
#   Adapted from Envoy outlier-detection + Resilience4j circuit-breaker state
#   machines to a finite N-account rotation pool. Operators distinguish FIVE
#   states, not one binary health flag:
#
#     HEALTHY        schedulable == rotation_size                  (gray)
#     DEGRADED       schedulable < rotation_size && schedulable > 1 (yellow)
#     PARTIAL_OUTAGE schedulable == 1 && rotation_size >= 2        (yellow — pre-warn)
#     TOTAL_OUTAGE   schedulable == 0                              (red — alarm)
#     UNKNOWN        rotation_size == 0 (empty pool — config issue)
#
#   PARTIAL_OUTAGE is the canonical PRE-WARNING gate: one more failure means
#   the pool has no resilience left, and the next request 503's the user.
#
# ── unified state-name label (the operator-facing word) ──────────────────────
#   Combines canary classification + pool resilience state via worst-of
#   precedence (severity-ranked, highest to lowest):
#     pool total-outage          → "outage" (red, alarm)
#     canary recent-degradation  → "outage" (red, alarm)
#     pool partial-outage        → "partial-outage" (yellow, pre-warn)
#     pool degraded              → "flapping" (yellow, watch)
#     canary transient           → "flapping" (yellow, watch)
#     canary since-start-failure → "since-boot" (gray, calm — config bug)
#     all healthy                → "healthy" (no rendered label)
#
#   The state-name IS the playbook hint:
#     "since-boot" → file an issue against doorward; do NOT page
#     "flapping"   → watch for next minute; may self-recover
#     "partial-outage" → intervene now; pool has no redundancy
#     "outage"     → page someone immediately
#
# ── "1.93.0" or "1.93.0<1.2.0"  ←  local ccmax-claude wrapper version ────────
#   Render shape: bare semver, or "X<Y" when X is below floor Y.
#   Source X = $(ccmax-claude --version), cached by binary mtime in
#              /tmp/ccmax-wrapper-version. Empty when the binary isn't
#              installed (segment then omits the version entirely).
#   Source Y = DOORWARD_MIN_WRAPPER_VERSION — AUTO-DISCOVERED (L1a).
#              On a miss against /tmp/ccmax-doorward-floor (3600s TTL), we
#              anonymously probe doorward's /v1/users/me without the wrapper
#              version header and parse .error.minimum_wrapper_version_required
#              out of the 403 response body. Caches the discovered value, so
#              when doorward raises its floor, the next render within the
#              hour picks it up — no manual constant bump required. On probe
#              failure (doorward unreachable, gate disabled, parse error)
#              we fall back to compiled-in DOORWARD_MIN_WRAPPER_VERSION_FALLBACK
#              so the renderer always has SOMETHING to compare against.
#   Color: BRIGHT_BLACK (gray) when X >= Y; YELLOW with explicit "<Y" suffix
#          when below. Yellow surfaces version-skew BEFORE a real request
#          fails with 403 — instead of after.
#   "wrapper" label removed — a three-dotted semver token is visually distinct
#   from the slash-fractions and ✗N tokens that precede it.
#
# ── "unreachable" (replaces numeric tokens when fetch fails) ─────────────────
#   Rendered as a literal RED word in place of the pool/canary numerics.
#   Kept as a word (not redundant labeling) because it carries the WHY:
#   distinguishes "doorward is genuinely down" from "got a response but
#   couldn't parse it" (the latter would just show empty numerics if we
#   omitted this). With the gate emoji retired, this word IS the down-state
#   signal — the red color on the word itself replaces the prior red dot.
#
# ── pin scope+mode badge (RETIRED 2026-05-13) ───────────────────────────────
#   Earlier versions rendered a bracketed scope+mode marker like
#   "[device:soft]" or "[repo:strict]" synthesised from
#   ccmax_resolve_layered_pin_with_account_mode in ccmax-monitor's
#   pin-helper.sh, with YELLOW for ":soft" and RED for ":strict" coloring.
#   Retired per operator directive 2026-05-13 because under bearer-mode
#   routing doorward picks the upstream OAuth account dynamically per-
#   request, so knowing WHICH scope holds the pin no longer changes the
#   operator's mental model of "what is actually serving me". The pin
#   resolution itself still runs upstream — its output feeds bearer-mode
#   detection (see next section) — but the visible badge is dropped.
#
# ── Bearer-mode detection (NO visible badge) ─────────────────────────────────
#   $ccmax_bearer_account is set via pin file's account_mode field, the
#   CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION env var, or by
#   pattern-matching $ANTHROPIC_BASE_URL against the doorward hosts. It gates
#   whether to render the ccmax line at all (so that a red "unreachable"
#   warning still appears on a bearer-routed session even if no pin exists)
#   but no longer produces a visible label — the prior "[5th-fleet]" badge
#   was retired 2026-05-13 alongside the broader fleet-terminology cleanup.
#
# ── Line-suppression rule ────────────────────────────────────────────────────
#   The whole ccmax segment is suppressed (only datetime renders) when ALL of:
#     - doorward_status == "unreachable", AND
#     - ccmax_pin_badge is empty, AND
#     - ccmax_bearer_account is empty
#   This is the "no integration installed at all" case (most public cc-skills
#   users). They see the bare datetime line and nothing else.
# =============================================================================

# Pin scope+mode badge RETIRED 2026-05-13 (operator directive: "[repo:soft]
# no longer needed"). The upstream pin-resolution cascade still runs because
# ccmax_pin_account_mode + ccmax_pin_account feed into ccmax_bearer_account
# detection, which gates the render-decision below. The visible badge itself
# is dropped — the operator has no remaining need to see WHICH scope holds
# the pin since under bearer-mode routing doorward picks the upstream
# account dynamically per-request anyway. ccmax_pin_badge stays as an empty
# placeholder so downstream render-decision and echo statements don't need
# structural changes.
ccmax_pin_badge=""

# NOTE: gate-state emoji (🟢/🟡/🔴) was REMOVED 2026-05-13. Rationale: every
# state the emoji could signal is already expressed by a colored token after
# the "doorward" anchor — the RED ✗N glyph carries "canary degraded", the
# RED pool ratio carries "errors in rotation", and the literal RED word
# "unreachable" carries "gateway down". The emoji was therefore pure
# duplication. The state is now read entirely from the per-token coloring of
# the trailing numbers/words.

# =============================================================================
# L1d MULTI-DIMENSIONAL UNIFIED RENDERER (2026-05-13)
# =============================================================================
# Render shape (all tokens after the BRIGHT_BLACK "doorward" anchor):
#
#   doorward <N/M> <severity><type>[<duration>] [<state-name>] <wrapper>
#
#   N/M         pool ratio, colored by pool resilience state machine
#               (BRIGHT_BLACK healthy, YELLOW degraded/partial-outage, RED total-outage)
#   severity    ✓ healthy (GREEN) | ✗ degraded/outage (RED/gray) | ⚠ pre-warn (YELLOW)
#   type        AU/QT/CF/UP/IN — only when severity != ✓ (derived from canary
#               last_observed_http_status_code per RFC 9457 taxonomy)
#   duration    humanized canary failure duration (e.g. 18h, 3m, 2d) — only
#               when severity != ✓
#   state-name  since-boot | flapping | partial-outage | outage — operator-
#               facing label that names the actionable failure category
#   wrapper     local ccmax-claude version, with <floor suffix (YELLOW) when
#               below DOORWARD_MIN_WRAPPER_VERSION, or =floor suffix (YELLOW)
#               when exactly at floor (pre-warn for next floor bump)
#
# Scenario examples (against today's live state and hypotheticals):
#   doorward 3/3 ✓ 1.93.0                              all healthy
#   doorward 3/3 ✗AU 18h since-boot 1.93.0             today (config bug, gray)
#   doorward 2/3 ⚠UP 3m flapping 1.93.0                one backend transient
#   doorward 1/3 ⚠UP 12m partial-outage 1.93.0         last healthy, pre-warn
#   doorward 0/3 ✗UP 47m outage 1.93.0                 total outage, alarm
#   doorward 3/3 ✓ 1.2.0=1.2.0                          wrapper exactly at floor
#
# Full source-of-truth legend for each token lives in the in-script LEGEND
# block earlier in the file (search "Doorward gateway summary — render LEGEND").

# =============================================================================
# L2 STATISTICS SURFACE — JSONL append per render (2026-05-13, task #7)
# =============================================================================
# Persists every parsed doorward state to ~/.claude/doorward-state.jsonl, one
# line per render. Consumed by the sibling analytics CLI:
#   plugins/statusline-tools/scripts/doorward-telemetry-analytics-from-statusline-jsonl-log.py
# which emits time-windowed uptime %, type-code distribution, state-machine
# transition counts, and pre-warning event timelines.
#
# Schema (v1) — 20 fields, verbose snake_case names:
#   schema_version                                          (int, monotonic)
#   wall_clock_unix_seconds                                 (int, epoch seconds)
#   doorward_gateway_legacy_binary_gate_status              ∈ {healthy, degraded, parse-error, unreachable}
#   doorward_pool_schedulable_active_accounts_count         (int)
#   doorward_pool_rotation_working_set_size                 (int, denom = schedulable + errors)
#   doorward_pool_error_accounts_count                      (int)
#   doorward_pool_resilience_state_machine_label            ∈ {healthy, degraded, partial-outage, total-outage, unknown}
#   doorward_canary_consecutive_failures                    (int)
#   doorward_canary_classification_four_state               ∈ {healthy, since-start-failure, transient, recent-degradation, unknown}
#   doorward_canary_failure_type_code                       ∈ {AU, QT, CF, UP, IN, ""}  (RFC 9457 taxonomy)
#   doorward_canary_failure_duration_humanized              (str, e.g. "3d", "47m", "")
#   doorward_canary_real_traffic_damper_engaged             (bool)
#   doorward_unified_state_name_for_render                  ∈ {healthy, since-boot, flapping, partial-outage, outage, unknown}
#   doorward_local_ccmax_claude_wrapper_version             (semver str, e.g. "1.93.0")
#   doorward_minimum_supported_wrapper_version_floor        (semver str, e.g. "1.2.0")
#   doorward_wrapper_skew_present                           (bool, wrapper < floor)
#   doorward_wrapper_at_floor_pre_warn                      (bool, wrapper == floor)
#   doorward_pin_scope_active                               ∈ {"", session, repo, device}
#   doorward_pin_mode_active                                ∈ {"", soft, strict}
#   doorward_bearer_mode_routing_active                     (bool)
#
# Safety: all string fields are constrained to ASCII-safe enums (parser output)
# or semver shapes; none can contain quote/backslash characters, so direct
# string interpolation into the JSON is safe and avoids a jq dependency. Match
# the existing terse-echo pattern used at line ~83 for statusline.jsonl.
#
# Failure mode: every write redirects errors to /dev/null. If the log file
# can't be written (disk full, perms), we silently continue — never block the
# statusline render on telemetry persistence.

doorward_state_jsonl_log_absolute_path="${HOME}/.claude/doorward-state.jsonl"

doorward_wrapper_skew_present_boolean_serialized="false"
doorward_wrapper_at_floor_pre_warn_boolean_serialized="false"
if [ -n "$wrapper_version" ]; then
    if version_lt "$wrapper_version" "$DOORWARD_MIN_WRAPPER_VERSION"; then
        doorward_wrapper_skew_present_boolean_serialized="true"
    elif [ "$wrapper_version" = "$DOORWARD_MIN_WRAPPER_VERSION" ]; then
        doorward_wrapper_at_floor_pre_warn_boolean_serialized="true"
    fi
fi
doorward_bearer_mode_routing_active_boolean_serialized="false"
[ -n "$ccmax_bearer_account" ] && doorward_bearer_mode_routing_active_boolean_serialized="true"
doorward_real_traffic_damper_engaged_boolean_serialized="false"
[ "$real_traffic_recent" -eq 1 ] && doorward_real_traffic_damper_engaged_boolean_serialized="true"

doorward_state_jsonl_log_record_for_this_render="{\
\"schema_version\":1,\
\"wall_clock_unix_seconds\":$(date +%s),\
\"doorward_gateway_legacy_binary_gate_status\":\"${doorward_status}\",\
\"doorward_pool_schedulable_active_accounts_count\":${pool_schedulable},\
\"doorward_pool_rotation_working_set_size\":${pool_rotation_size},\
\"doorward_pool_error_accounts_count\":${pool_errors},\
\"doorward_pool_resilience_state_machine_label\":\"${pool_resilience_state_machine_label}\",\
\"doorward_canary_consecutive_failures\":${canary_failures},\
\"doorward_canary_classification_four_state\":\"${canary_class}\",\
\"doorward_canary_failure_type_code\":\"${canary_failure_type_code_AU_QT_CF_UP_IN}\",\
\"doorward_canary_failure_duration_humanized\":\"${canary_failure_duration_humanized_short_form}\",\
\"doorward_canary_real_traffic_damper_engaged\":${doorward_real_traffic_damper_engaged_boolean_serialized},\
\"doorward_unified_state_name_for_render\":\"${unified_state_name_for_render_label}\",\
\"doorward_local_ccmax_claude_wrapper_version\":\"${wrapper_version}\",\
\"doorward_minimum_supported_wrapper_version_floor\":\"${DOORWARD_MIN_WRAPPER_VERSION}\",\
\"doorward_wrapper_skew_present\":${doorward_wrapper_skew_present_boolean_serialized},\
\"doorward_wrapper_at_floor_pre_warn\":${doorward_wrapper_at_floor_pre_warn_boolean_serialized},\
\"doorward_pin_scope_active\":\"${ccmax_pin_scope}\",\
\"doorward_pin_mode_active\":\"${ccmax_pin_mode}\",\
\"doorward_bearer_mode_routing_active\":${doorward_bearer_mode_routing_active_boolean_serialized}\
}"
echo "${doorward_state_jsonl_log_record_for_this_render}" >> "${doorward_state_jsonl_log_absolute_path}" 2>/dev/null

doorward_inline=""
if [ "$doorward_status" = "healthy" ] || [ "$doorward_status" = "degraded" ]; then
    # Pool ratio colored by pool_resilience_state_machine_label (orthogonal to
    # canary state — pool can be healthy while canary is broken via L1c
    # damper, or vice versa).
    case "$pool_resilience_state_machine_label" in
        healthy)
            pool_part="${BRIGHT_BLACK}${pool_schedulable}/${pool_rotation_size}${RESET}"
            ;;
        degraded)
            pool_part="${YELLOW}${pool_schedulable}/${pool_rotation_size}${RESET}"
            ;;
        partial-outage)
            # "Last healthy account" pre-warn — yellow (escalates if pool
            # falls to 0 next; precedent for using yellow on the pre-warn
            # state is from Envoy outlier-detection ejection-threshold UX).
            pool_part="${YELLOW}${pool_schedulable}/${pool_rotation_size}${RESET}"
            ;;
        total-outage)
            pool_part="${RED}${pool_schedulable}/${pool_rotation_size}${RESET}"
            ;;
        *)
            pool_part="${BRIGHT_BLACK}${pool_schedulable}/${pool_rotation_size}${RESET}"
            ;;
    esac

    # Severity glyph + type-code + duration, composed from the unified state
    # name. The four operator-facing state names map onto three visual
    # severity tiers (GREEN healthy / BRIGHT_BLACK calm-since-boot / YELLOW
    # warn-flapping-or-partial / RED alarm-outage):
    case "$unified_state_name_for_render_label" in
        healthy)
            severity_glyph_with_optional_type_code_and_duration="${GREEN}✓${RESET}"
            unified_state_name_visible_label_token=""
            ;;
        since-boot)
            severity_glyph_with_optional_type_code_and_duration="${BRIGHT_BLACK}✗${canary_failure_type_code_AU_QT_CF_UP_IN} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${BRIGHT_BLACK}since-boot${RESET}"
            ;;
        flapping)
            severity_glyph_with_optional_type_code_and_duration="${YELLOW}⚠${canary_failure_type_code_AU_QT_CF_UP_IN} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${YELLOW}flapping${RESET}"
            ;;
        partial-outage)
            severity_glyph_with_optional_type_code_and_duration="${YELLOW}⚠${canary_failure_type_code_AU_QT_CF_UP_IN} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${YELLOW}partial-outage${RESET}"
            ;;
        outage)
            severity_glyph_with_optional_type_code_and_duration="${RED}✗${canary_failure_type_code_AU_QT_CF_UP_IN} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${RED}outage${RESET}"
            ;;
        *)
            # unknown / parse-error / sentinel — fail-safe to red alarm so we
            # don't hide a real problem behind missing data.
            severity_glyph_with_optional_type_code_and_duration="${RED}?${RESET}"
            unified_state_name_visible_label_token=" ${RED}${unified_state_name_for_render_label:-unknown}${RESET}"
            ;;
    esac

    doorward_inline=" ${BRIGHT_BLACK}doorward${RESET} ${pool_part} ${severity_glyph_with_optional_type_code_and_duration}${unified_state_name_visible_label_token}"
elif [ -n "$doorward_status" ] && [ "$doorward_status" != "unreachable" ]; then
    # Non-empty $doorward_status but not the expected healthy/degraded values —
    # surface the raw state token in red so the operator sees the literal
    # parse-error word (or any future sentinel we introduce).
    doorward_inline=" ${BRIGHT_BLACK}doorward${RESET} ${RED}${doorward_status}${RESET}"
else
    doorward_inline=" ${BRIGHT_BLACK}doorward${RESET} ${RED}unreachable${RESET}"
fi

# Wrapper version: bare semver normally; YELLOW with "<floor" suffix when
# below floor (skew, will be 403'd); YELLOW with "=floor" suffix when exactly
# at floor (pre-warn — next doorward floor-bump will reject us). The "=floor"
# pre-warning is the canonical "at-threshold" SRE pattern (one perturbation
# away from breach). Label "wrapper" deliberately dropped — three-dot semver
# is visually unique against the other tokens.
wrapper_part=""
if [ -n "$wrapper_version" ]; then
    if version_lt "$wrapper_version" "$DOORWARD_MIN_WRAPPER_VERSION"; then
        wrapper_part=" ${YELLOW}${wrapper_version}<${DOORWARD_MIN_WRAPPER_VERSION}${RESET}"
    elif [ "$wrapper_version" = "$DOORWARD_MIN_WRAPPER_VERSION" ]; then
        wrapper_part=" ${YELLOW}${wrapper_version}=${DOORWARD_MIN_WRAPPER_VERSION}${RESET}"
    else
        wrapper_part=" ${BRIGHT_BLACK}${wrapper_version}${RESET}"
    fi
fi

# Decide whether to render the ccmax segment at all. Three independent
# triggers, any one is sufficient:
#   - doorward responded (cached or fresh) → status != "unreachable"
#   - a pin file resolved a scope+mode → ccmax_pin_badge non-empty
#   - bearer-mode detection found a bearer account → ccmax_bearer_account set
# Otherwise (no integration installed), print the bare datetime line.
# ccmax_bearer_account itself produces no visible badge — only the render
# decision uses it; presence of the doorward block already implies bearer-
# mode routing for the operator.
if [ "$doorward_status" != "unreachable" ] || [ -n "$ccmax_pin_badge" ] || [ -n "$ccmax_bearer_account" ]; then
    # $doorward_inline starts with its own leading space (the "doorward"
    # anchor), so concatenating directly after the BRIGHT_BLACK "|" separator
    # produces exactly one space of padding between them.
    echo -e "${datetime_display} ${BRIGHT_BLACK}|${RESET}${doorward_inline}${wrapper_part}${ccmax_pin_badge}"
else
    echo -e "${datetime_display}"
fi

# Autonomous-loop awareness (v16.9.2): if the current cwd is under any
# registered loop's contract dir, print one compact line with the loop's
# identity + health. Sits between datetime and the path line so the
# operator sees "what loop owns this terminal" alongside the project info.
loop_registry="$HOME/.claude/loops/registry.json"
if [ -f "$loop_registry" ]; then
    # Find the loop whose contract dir is a prefix of the current cwd OR
    # whose contract dir IS the current cwd. Same matcher as session-bind.sh.
    loop_match=$(jq -c --arg cwd "$PWD" '
        .loops[]? |
        select(
            ((.contract_path | split("/") | .[:-1] | join("/")) as $contract_dir |
              ($contract_dir + "/") as $contract_prefix |
              ($cwd | startswith($contract_prefix)) or ($cwd == $contract_dir)
            )
        ) |
        {
            loop_id, contract_path, state_dir,
            owner_session_id: (.owner_session_id // "")
        }
    ' "$loop_registry" 2>/dev/null | head -1)
    if [ -n "$loop_match" ] && [ "$loop_match" != "null" ]; then
        # Perf (iter-30 statusline-loop-match-tsv-batch-decode): pre-iter-30
        # the statusline spawned FOUR jq processes here — one per field
        # extracted from $loop_match. Each spawn pays ~7-10ms cold-start on
        # macOS, so a 4-field decode cost ~30-40ms PER STATUSLINE REFRESH.
        # The statusline refreshes every few seconds; with autoloop active
        # this cost compounds across the whole session.
        #
        # TSV-batched decode + bash `read` mirrors the iter-25/26 pattern
        # established in heartbeat-tick.sh's MATCHING_LOOP decode. The
        # trailing-tab fallback via printf keeps `read` happy if jq dies so
        # all four vars default to empty strings.
        IFS=$'\t' read -r loop_id contract_path state_dir_raw owner_sid <<< "$(
            echo "$loop_match" | jq -r '"\(.loop_id // "")\t\(.contract_path // "")\t\(.state_dir // "")\t\(.owner_session_id // "")"' 2>/dev/null \
                || printf '\t\t\t'
        )"
        state_dir="${state_dir_raw%/}"  # strip trailing slash (was `sed 's:/*$::'`)

        # Read contract frontmatter for name + status + iteration
        loop_name=""; loop_status=""; loop_iter=""
        if [ -f "$contract_path" ]; then
            # Single awk pass — name / status / iteration from YAML frontmatter
            eval "$(awk '
                /^---$/{n++; next}
                n==1 && /^name:[[:space:]]*/      {sub(/^name:[[:space:]]*/, "");      gsub(/'\''/, ""); printf "loop_name=%s\n", "\"" $0 "\""; next}
                n==1 && /^status:[[:space:]]*/    {sub(/^status:[[:space:]]*/, "");    gsub(/'\''/, ""); printf "loop_status=%s\n", "\"" $0 "\""; next}
                n==1 && /^iteration:[[:space:]]*/ {sub(/^iteration:[[:space:]]*/, ""); printf "loop_iter=%s\n", "\"" $0 "\""; next}
                n==1 && NR > 30 {exit}
            ' "$contract_path" 2>/dev/null)" 2>/dev/null
        fi
        loop_name="${loop_name:-$loop_id}"
        loop_status="${loop_status:-?}"
        loop_iter="${loop_iter:-?}"

        # Heartbeat freshness — last_wake_us age in seconds; cwd-drift flag.
        #
        # Perf (iter-30 statusline-heartbeat-tsv-batch + python3-now-us-replacement):
        # Pre-iter-30 this block did THREE expensive things:
        #   1. jq for last_wake_us (~7-10ms)
        #   2. python3 -c "import time; ..." for now_us (~30-50ms cold start
        #      on macOS — Python startup is much slower than gdate)
        #   3. jq for cwd_drift_detected (~7-10ms)
        # Cumulative: ~45-70ms PER STATUSLINE REFRESH when autoloop is active.
        #
        # Iter-30 replaces all three with:
        #   - 1 TSV-batched jq reading both heartbeat fields at once
        #   - gdate +%s%6N for now_us (~3ms cold start vs python3's ~30-50ms)
        # Cumulative: ~10-15ms — a 3-7× speedup on this block.
        #
        # Matches the iter-25/26 pattern and the iter-28
        # python3-now-us-replacement applied to session-bind.sh.
        hb_age="?"
        drift_flag=""
        if [ -n "$state_dir" ] && [ -f "$state_dir/heartbeat.json" ]; then
            IFS=$'\t' read -r last_us drift <<< "$(
                jq -r '"\(.last_wake_us // 0)\t\(.cwd_drift_detected // false)"' "$state_dir/heartbeat.json" 2>/dev/null \
                    || printf '0\tfalse'
            )"
            now_us=$(gdate +%s%6N 2>/dev/null || python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0)
            if [ "${last_us:-0}" -gt 0 ] && [ "${now_us:-0}" -gt 0 ]; then
                hb_age=$(( (now_us - last_us) / 1000000 ))
            fi
            [ "$drift" = "true" ] && drift_flag=" ${RED}⚠ cwd-drift${RESET}"
        fi

        # Binding state — color-code owner_session_id
        case "$owner_sid" in
            ""|"unknown"|"unknown-session"|"pending-bind")
                bind_label="${YELLOW}${owner_sid:-unbound}${RESET}"
                ;;
            *)
                # Truncate UUID to first 8 chars for compactness
                bind_label="${GREEN}${owner_sid:0:8}${RESET}"
                ;;
        esac

        # Status color: ACTIVE → green; DONE/* → bright_black; PAUSED → yellow; else cyan
        case "$loop_status" in
            ACTIVE*|active*)            status_label="${GREEN}${loop_status:0:30}${RESET}" ;;
            DONE*|done*|COMPLETE*|FINISHED*|SUPERSEDED*|STOPPED*|ABORTED*)
                                        status_label="${BRIGHT_BLACK}${loop_status:0:30}${RESET}" ;;
            PAUSED*|paused*)            status_label="${YELLOW}${loop_status:0:30}${RESET}" ;;
            *)                          status_label="${CYAN}${loop_status:0:30}${RESET}" ;;
        esac

        # Heartbeat age color: <60s green; <600s cyan; <3600s yellow; else red/?
        case "$hb_age" in
            "?")           hb_label="${BRIGHT_BLACK}♡ never${RESET}" ;;
            *)
                if   [ "$hb_age" -lt 60 ];   then hb_label="${GREEN}♡ ${hb_age}s${RESET}"
                elif [ "$hb_age" -lt 600 ];  then hb_label="${CYAN}♡ ${hb_age}s${RESET}"
                elif [ "$hb_age" -lt 3600 ]; then hb_label="${YELLOW}♡ ${hb_age}s${RESET}"
                else                              hb_label="${RED}♡ ${hb_age}s${RESET}"
                fi
                ;;
        esac

        # Compose: ⏿ <name> [<id>] iter N · <status> · bound: <sid> · ♡ <age>
        echo -e "${BRIGHT_BLACK}⏿${RESET} ${MAGENTA}${loop_name:0:40}${RESET} ${BRIGHT_BLACK}[${loop_id}]${RESET} iter ${loop_iter} ${BRIGHT_BLACK}·${RESET} ${status_label} ${BRIGHT_BLACK}·${RESET} bound:${bind_label} ${BRIGHT_BLACK}·${RESET} ${hb_label}${drift_flag}"
    fi
fi

echo -e "$line_repo"

if [ -n "$session_chain" ]; then
    echo -e "${BRIGHT_BLACK}~/.claude/projects JSONL ID:${RESET} ${session_chain}"
elif [ -n "$session_id" ]; then
    echo -e "${BRIGHT_BLACK}~/.claude/projects JSONL ID: ${session_id}${RESET}"
fi

if [ -n "$iterm_session_uuid" ]; then
    echo -e "${BRIGHT_BLACK}~/asciinemalogs cast: ${iterm_session_uuid}${RESET}"
fi

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
        # id(schedule) — clickable hyperlink to prompt file if available, cyan text.
        # The '\033\\' sequences are OSC 8 hyperlink open/close terminators
        # (ESC byte + literal backslash = the OSC String Terminator). SC1003
        # is a known false-positive for OSC 8 because shellcheck reads the
        # trailing `\\` as an attempt to escape a single quote, when it's
        # actually a printf format-string escape producing a single backslash.
        if [ -n "$job_prompt" ] && [ -f "$job_prompt" ]; then
            # shellcheck disable=SC1003
            printf '\033]8;;file://%s\033\\' "$job_prompt"
            printf '\033[96m%s(%s)\033[0m' "$job_id" "$job_sched"
            # shellcheck disable=SC1003
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
                # OSC 8 hyperlink terminators — see comment in earlier block
                # explaining the SC1003 false-positive on `\033\\`.
                # shellcheck disable=SC1003
                printf '\033]8;;file://%s\033\\' "$vfile"
                printf 'v%s' "$version_num"
                # shellcheck disable=SC1003
                printf '\033]8;;\033\\'
                printf '\033[0m'
                version_num=$((version_num + 1))
                [ "$version_num" -gt 5 ] && break
            done < <(ls -t "$history_dir"/*.md 2>/dev/null)
        fi
        printf '\n'
    done < <(jq -c '.[]' "$cron_state_file" 2>/dev/null)
fi
