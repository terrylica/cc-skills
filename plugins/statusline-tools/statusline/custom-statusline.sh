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
#
# =============================================================================
# OPTIONAL INTEGRATION SEAM — everything here is OFF unless you opt in
# =============================================================================
# This script renders an optional "admission gateway health" segment. With no
# configuration it is completely inert: no network call, no cache file, no log
# file, no output, no error. You have to name a gateway to switch it on.
#
#   STATUSLINE_GATEWAY_BASE_URL     Gateway base URL. THE MASTER SWITCH — the
#                                   whole feature is skipped while it and the
#                                   env file below are both absent.
#   STATUSLINE_GATEWAY_ENV_FILE     Shell file exporting ANTHROPIC_BASE_URL,
#                                   used when the var above is unset.
#   STATUSLINE_GATEWAY_PORT_REWRITE "FROM:TO" — rewrite the URL's port when a
#                                   deployment splits inference and
#                                   introspection across two ports.
#   STATUSLINE_GATEWAY_LABEL        Word shown before the metrics. Default
#                                   "gateway".
#   STATUSLINE_GATEWAY_STATE_LOG    Telemetry JSONL path. Written ONLY when a
#                                   gateway is configured.
#   STATUSLINE_PIN_HELPER_PATH      Optional account-pin helper library.
#   STATUSLINE_PIN_DEVICE_FILE      Optional device-scope pin file.
#   STATUSLINE_PIN_RESOLVER_FN      Resolver function name in that helper.
#   STATUSLINE_PIN_RESOLVER_FN_LEGACY  Older resolver name, tried second.
#   STATUSLINE_CLIENT_WRAPPER_BIN   Client wrapper binary whose --version is
#                                   compared against the gateway's floor.
#
# The pin/wrapper entries keep backwards-compatible defaults naming the
# specific third-party tool this integration was first written against. Those
# defaults are the ONLY deployment-specific strings left in this file, and are
# inert paths or symbol names (a missing file is skipped), never endpoints or
# credentials. Set
# the variables above to point at your own tooling and nothing in this script
# refers to that tool at all.

# GIT_OPTIONAL_LOCKS=0 — the statusline must OBSERVE repo state, never CONTEND for it.
# Every render runs `git status`/`git diff`, which by default take .git/index.lock to refresh
# the index. Fired on each prompt render, that races a user's concurrent `git commit`/`git add`
# in the same checkout (and in worktrees, the per-worktree index.lock), intermittently failing
# their commit with "Unable to create '.../index.lock': File exists". Setting this env var (the
# same mechanism VS Code and other IDEs use) makes all git subprocesses this script spawns skip
# the OPTIONAL index lock — status/diff still report correctly, they just don't write index.lock.
# Comprehensive + future-proof: covers every git call here, including any added later.
export GIT_OPTIONAL_LOCKS=0

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
# a bearer-pin client wrapper) inject HTTPS_PROXY=http://127.0.0.1:<port>
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

# Read JSON from stdin
input=$(cat)

# Append raw statusline data to JSONL for analytics
# Format matches ccost's expected schema: {"ts":<unix_epoch>,"data":<stdin_json>}
# Consumed by: scripts/gateway-telemetry-analytics-from-statusline-jsonl-log.py
# (L2 telemetry surface) and an external analytics package —
# intentional cross-repo infrastructure, NOT dead code.
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
# One batched jq + bash `read` decodes all fields in a single spawn. The
# trailing-separator fallback via printf keeps `read` happy if jq dies
# (all fields default to empty → segment omitted).
# Delimiter note (2026-06-10 model-id-badges edit): switched TSV → \x1f (ASCII
# unit separator). Tab is IFS *whitespace*, so bash `read` COLLAPSES runs of
# consecutive tabs — any empty mid-field silently shifts every later field
# left (session_id would receive the transcript path). \x1f is non-whitespace,
# so empty fields survive.
#
# OFFICIAL-VALUES-ONLY decode (2026-06-11 operator directive): values pass
# through VERBATIM. No made-up fallbacks — the former "Unknown" model
# fallback and the `sed 's/Claude //'` display compactor are gone (a payload
# without a model renders no model segment; the session registry receives
# the official display_name untouched). Booleans distinguish ABSENT (empty
# string → token omitted from render) from present-false (official value
# "false" rendered). jq's `//` cannot make that distinction (it treats false
# as empty), so booleans use an explicit null check instead of `// false`.
IFS=$'\x1f' read -r model_raw model_id effort_level thinking_enabled fast_mode_flag session_id transcript_file cost git_branch cc_version <<< "$(
    echo "$input" | jq -r '[(.model.display_name // .model.id // ""), (.model.id // ""), (.effort.level // ""), (.thinking.enabled | if . == null then "" else tostring end), (.fast_mode | if . == null then "" else tostring end), (.session_id // ""), (.transcript_path // ""), (.cost.total_cost_usd // ""), (.git.branch // ""), (.version // "")] | map(tostring) | join("\u001f")' 2>/dev/null \
        || printf '\x1f\x1f\x1f\x1f\x1f\x1f\x1f\x1f\x1f'
)"

# === Context window fields (for bracketed-zone bar on model line) ===
# Separate jq spawn from the 10-field model-info TSV above — kept apart for
# readability and because context_window is absent at session start (all vars
# empty → bar suppressed downstream). Unit-separator pattern mirrors iter-30.
#
# cfmt: compact token notation — integers only, no decimals needed for this
# use case (97205 → "97k", 1000000 → "1M", 200000 → "200k").
IFS=$'\x1f' read -r ctx_used_tok ctx_window_size ctx_used_pct ctx_tok_compact ctx_win_compact <<< "$(
    echo "$input" | jq -r '
        def cfmt:
            if . >= 1000000 then (. / 1000000 | floor | tostring) + "M"
            elif . >= 1000  then (. / 1000    | floor | tostring) + "k"
            else tostring end;
        [
            (.context_window.total_input_tokens  // 0 | tostring),
            (.context_window.context_window_size // 0 | tostring),
            (.context_window.used_percentage     // 0 | tostring),
            (.context_window.total_input_tokens  // 0 | cfmt),
            (.context_window.context_window_size // 0 | cfmt)
        ] | join("")' 2>/dev/null \
            || printf '\x1f\x1f\x1f\x1f'
)"

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

# Context/cost block REMOVED 2026-06-11: ctx_display (token count from the
# transcript tail, cost fallback, invented "N/A" terminal fallback) was
# computed on every render but NEVER rendered — dead code since the layout
# settled, surfaced by the official-values audit. $cost itself is still
# decoded above and passed to the session registry.

# Git info - try JSON first, fallback to direct git commands.
# (git_branch already TSV-batched above in iter-30 input-payload decode.)
if [ -z "$git_branch" ]; then
    # Fallback: read git directly. OFFICIAL-VALUES-ONLY (2026-06-11): the
    # invented "no-branch" label is gone — on detached HEAD (show-current
    # empty) surface the official short SHA; outside a git repo stay empty.
    git_branch=$(git branch --show-current 2>/dev/null)
    if [ -z "$git_branch" ]; then
        git_branch=$(git rev-parse --short HEAD 2>/dev/null)
    fi
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
                    bun "$registry_script" "$session_id" "$cwd_path" "$model_raw" "${cost:-}" "$git_branch"
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

# Credential resolution (ADR 2026-06-21 doctrine): derive the gh account from the
# remote host-alias (git@github.com-<account>:…) — the single source of truth — and
# pin its isolated profile. ALWAYS strip ambient GH_TOKEN/GITHUB_TOKEN: gh ranks
# GH_TOKEN above GH_CONFIG_DIR, so a stale session token would 401 the status line
# after a rotation. `gh_cred` is the prefix for every API-hitting gh call below.
gh_account=$(printf '%s' "$remote_url_raw" | sed -nE 's#^git@github\.com-([A-Za-z0-9_-]+):.*#\1#p')
gh_cred=(env -u GH_TOKEN -u GITHUB_TOKEN)
# When the alias names an account but no ~/.config/gh-<account> profile exists,
# gh falls back to the multi-user default config, whose active-account
# resolution is fragile in this subprocess (it 401s as "gh exit 4"). Flag the
# real cause so a missing profile reads as an actionable hint, not a mystery.
# (Observed failure mode: repos under a secondary org failed because that
# org.s gh profile was never set up — every in-use host-alias needs its own
# isolated profile.)
gh_profile_missing=""
if [ -n "$gh_account" ]; then
    if [ -d "$HOME/.config/gh-$gh_account" ]; then
        gh_cred+=("GH_CONFIG_DIR=$HOME/.config/gh-$gh_account")
    else
        gh_profile_missing="$gh_account"
    fi
fi

# Latest release from GitHub (semantic-release SSoT, not local tags which may
# include non-semver milestone tags like v2.0/v2.1 that sort above semver releases).
# Tri-state, rendered with OFFICIAL text only (2026-06-11 directive — the
# invented "∅ rel"/"⌁ offline" markers are gone): real release → version+age;
# failure → the first line of gh's own stderr verbatim (e.g. "release not
# found"); silent failure (timeout kills gh before it prints) → the official
# exit code as "gh exit N". `gh` returns exit 1 for both "release not found"
# AND auth/network failures, so stderr text — not the exit code — is also
# what distinguishes cacheable no-release from transient network errors.
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
        release_out=$(probe_direct timeout 2 "${gh_cred[@]}" gh release view --repo "$owner_repo" --json tagName,publishedAt -q '.tagName + "|" + .publishedAt' 2>&1)
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
    else
        # Failure: render gh's OWN diagnostic verbatim (first stderr line,
        # severity prefix stripped — covers both "release not found" and
        # auth/network errors). When gh died without output (timeout 124,
        # binary missing 127), state the official exit code instead —
        # never an invented marker word.
        gh_rel_diag=$(printf '%s' "$release_out" | head -1 | sed -E 's/^(fatal|error): //')
        # Missing-profile failures are actionable — name the absent profile
        # instead of gh's generic auth diagnostic ("gh exit 4" / login prompt).
        if [ -n "$gh_profile_missing" ]; then
            gh_rel_diag="no gh-${gh_profile_missing} profile"
        fi
        git_changes="${git_changes} ${BRIGHT_BLACK}| ${gh_rel_diag:-gh exit ${release_exit}}${RESET}"
    fi
fi
# (No origin remote → the release segment is omitted entirely: absent data
# renders nothing, per the official-values policy — the invented "| ∅"
# placeholder was removed 2026-06-11.)

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
    # git@github.com-myalias:myorg/repo.git -> https://github.com/myorg/repo
    # git@github.com:user/repo.git -> https://github.com/user/repo
    # Also handles wiki: myorg/kb.wiki.git -> https://github.com/myorg/kb/wiki
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
    vis_err=""
    if [ "$vis_cache_age" -lt 3600 ]; then
        vis_out=$(cat "$vis_cache_file")
        vis_exit=0
    else
        # Capture stdout and stderr SEPARATELY. On a non-2xx response `gh api`
        # dumps the raw JSON response body to STDOUT (its first line is a bare
        # "{") and writes its own one-line diagnostic — `gh: <msg> (HTTP NNN)`
        # — as the LAST line of STDERR. The pre-2026-06-21 code merged the two
        # with `2>&1` and took `head -1`, so it surfaced the JSON body's "{"
        # and rendered the ({) badge on every auth failure. Keep the streams
        # apart so the success value (stdout) and the diagnostic (stderr)
        # never contaminate each other.
        vis_err_file=$(mktemp -t ccstatusline-gh-vis.XXXXXX)
        vis_out=$(probe_direct timeout 2 "${gh_cred[@]}" gh api "repos/${owner_repo}" --jq 'if .private then "private" else "public" end' 2>"$vis_err_file")
        vis_exit=$?
        vis_err=$(cat "$vis_err_file" 2>/dev/null)
        rm -f "$vis_err_file"
        if [ $vis_exit -eq 0 ] && [[ "$vis_out" == "public" || "$vis_out" == "private" ]]; then
            echo "$vis_out" > "$vis_cache_file" 2>/dev/null
        fi
    fi
    if [ $vis_exit -eq 0 ] && [[ "$vis_out" == "public" || "$vis_out" == "private" ]]; then
        repo_visibility="$vis_out"
    elif [[ "$vis_err" == *"HTTP 404"* ]]; then
        repo_visibility=""  # repo doesn't exist or no read access — leave badge off
    else
        # auth, network, timeout, gh-missing: surface gh's OWN diagnostic
        # verbatim instead of the invented "?" marker (removed 2026-06-11 per
        # official-values directive). Prefer gh's last `gh: ...` stderr line
        # (e.g. "Bad credentials (HTTP 401)"); fall back to the JSON body's
        # .message; finally state the official exit code when gh died silently
        # (timeout/missing binary leave both streams empty).
        gh_vis_diag=$(printf '%s\n' "$vis_err" | grep -E '^gh: ' | tail -1 | sed -E 's/^gh: //')
        if [ -z "$gh_vis_diag" ]; then
            gh_vis_diag=$(printf '%s' "$vis_out" | grep -oE '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')
        fi
        # A missing isolated profile is the actionable root cause — name it
        # instead of gh's generic auth diagnostic (see gh_profile_missing above).
        if [ -n "$gh_profile_missing" ]; then
            gh_vis_diag="no gh-${gh_profile_missing} profile"
        fi
        repo_visibility="${gh_vis_diag:-gh exit ${vis_exit}}"
    fi
fi

# UTC and local timestamps with conditional date display
# Same date:        Tue 04 Mar 2026 23:36 UTC | 15:36 PST
# Different day:    Sun 22 Mar 2026 02:08 UTC | Sat 21 19:08 PDT
# Different month:  Wed 01 Jan 2026 05:00 UTC | Tue 31 Dec 19:00 PST
# Different year:   Thu 01 Jan 2026 05:00 UTC | Wed 31 Dec 2025 19:00 PST
# Local date portion shown in yellow when it differs from UTC
#
# SYSTEM-TZ invariant (2026-07-04, sibling of probe_direct): "local" time
# MUST come from the HOST's real timezone (/etc/localtime symlink), never
# from the inherited $TZ. Some client wrappers force TZ=UTC on the
# child claude process (China-origin timezone/locale metadata-leak
# neutralization, 2026-07-02 stego finding), and the statusline inherits
# that env — a bare `date` would render UTC as "local" (observed live:
# "06:38 UTC | 06:38 UTC"). Resolving the symlink is display-only; the
# claude process's privacy posture (TZ=UTC on the wire) is unchanged.
# Fallback: inherited TZ when the symlink is unreadable (hardened boxes).
system_tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
[ -z "$system_tz" ] && system_tz="${TZ:-UTC}"

utc_date=$(date -u +"%a %d %b %Y")
utc_hm=$(date -u +"%H:%M")
utc_month=$(date -u +"%b")
utc_year=$(date -u +"%Y")
local_date=$(TZ="$system_tz" date +"%a %d %b %Y")
local_hm=$(TZ="$system_tz" date +"%H:%M")
local_tz=$(TZ="$system_tz" date +"%Z")
local_month=$(TZ="$system_tz" date +"%b")
local_year=$(TZ="$system_tz" date +"%Y")

if [ "$utc_date" = "$local_date" ]; then
    # Same date: show date once with UTC, local time-only
    datetime_display="${BRIGHT_BLACK}${utc_date} ${utc_hm} UTC | ${local_hm} ${local_tz}${RESET}"
else
    # Different date: build minimal local date showing only what differs
    # Always show day-of-week + day number; add month if different; add year if different
    local_short=$(TZ="$system_tz" date +"%a %d")
    if [ "$utc_year" != "$local_year" ]; then
        local_short="$(TZ="$system_tz" date +"%a %d %b %Y")"
    elif [ "$utc_month" != "$local_month" ]; then
        local_short="$(TZ="$system_tz" date +"%a %d %b")"
    fi
    datetime_display="${BRIGHT_BLACK}${utc_date} ${utc_hm} UTC | ${YELLOW}${local_short}${BRIGHT_BLACK} ${local_hm} ${local_tz}${RESET}"
fi

# === Optional account-pin integration: Active Account + Pin Mode ===
#
# THIS BLOCK READS LOCAL FILES ONLY — no HTTP call, no network, no cache.
#
# (Scope correction 2026-09-04: the note here used to assert "this script
# contains zero curl invocations", which was false — the gateway block further
# down does make two. The no-network claim is true of THIS block only, and is
# now stated that way. A claim whose scope is wider than its evidence reads as
# a guarantee about the whole file.)
#
# Do NOT reintroduce a fetch of a local quota API here. Where a rotating
# gateway serves inference from a per-request account pool, the LOCAL
# credential's quota describes spend the user is not making — an accurate
# number for the wrong question. What follows reads a pin file only.
#
# OPTIONAL account-pin integration. Entirely absent for a default install:
# neither path below exists, both branches are skipped, no badge is produced.
#
# An external account-manager may pin this machine to one upstream account at
# one of three scopes, walked highest-first, first hit wins:
#   1. session — <pin-dir>/pin-by-session/<session-uuid>.toml   (highest)
#   2. repo    — <pin-dir>/pin-by-repo/<md5-prefix-8>.toml
#   3. device  — <pin-dir>/pin.toml                             (lowest)
#
# Resolution path:
#   1. If a pin-helper shell library is present, source it and call its
#      resolver (~2 ms via awk).
#   2. Else if the device-scope pin file exists, fall back to the small inline
#      awk parser below.
#   3. Else produce nothing.
#
# Both locations are env-overridable so the integration's identity lives in
# the user's own configuration rather than in this public script. The legacy
# defaults are retained ONLY so existing installs keep working without an
# edit; a fresh install should set the env vars.
pin_scope=""
pin_mode=""
pin_account=""
pin_account_mode=""
STATUSLINE_PIN_HELPER_PATH="${STATUSLINE_PIN_HELPER_PATH:-${HOME}/.claude/plugins/marketplaces/ccmax/hooks/pin-helper.sh}"
STATUSLINE_PIN_DEVICE_FILE="${STATUSLINE_PIN_DEVICE_FILE:-${HOME}/.config/ccmax/pin.toml}"

if [ -f "$STATUSLINE_PIN_HELPER_PATH" ]; then
    # Layered-pin path: source the helper and call the awk single-pass resolver.
    # We can't read the live session_id here (the statusline JSON does carry
    # it, but we want the badge to also be correct DURING the SessionStart
    # boundary when no JSONL exists yet). So we pass the session_id
    # extracted from the stdin JSON if available, else empty — the resolver
    # then considers only repo + device scopes, which is the desired
    # behavior at SessionStart.
    # NOTE: the two function names below are the EXTERNAL helper's API, not
    # ours. They are a contract with whatever installed that helper, so they
    # are spelled exactly as that helper defines them and must NOT be renamed
    # for cosmetic reasons — doing so silently selects the `else` branch and
    # the pin never resolves. Overridable via STATUSLINE_PIN_RESOLVER_FN.
    _pin_fn_new="${STATUSLINE_PIN_RESOLVER_FN:-ccmax_resolve_layered_pin_with_account_mode}"
    _pin_fn_old="${STATUSLINE_PIN_RESOLVER_FN_LEGACY:-ccmax_resolve_layered_pin}"
    _pin_layered_resolved=$(
        # shellcheck source=/dev/null
        source "$STATUSLINE_PIN_HELPER_PATH" 2>/dev/null \
            && if declare -F "$_pin_fn_new" >/dev/null 2>&1; then
                "$_pin_fn_new" "${session_id:-}" "$PWD" 2>/dev/null
            elif declare -F "$_pin_fn_old" >/dev/null 2>&1; then
                "$_pin_fn_old" "${session_id:-}" "$PWD" 2>/dev/null
            fi
    ) || _pin_layered_resolved="|||none"
    unset _pin_fn_new _pin_fn_old
    # Formats:
    #   New helper: <account>|<mode>|<scope>|<account_mode>
    #   Old helper: <account>|<mode>|<scope>
    pin_account="${_pin_layered_resolved%%|*}"
    _pin_layered_rest="${_pin_layered_resolved#*|}"
    pin_mode="${_pin_layered_rest%%|*}"
    _pin_layered_rest="${_pin_layered_rest#*|}"
    pin_scope="${_pin_layered_rest%%|*}"
    pin_account_mode="${_pin_layered_rest#*|}"
    if [ "$pin_account_mode" = "$pin_scope" ]; then
        pin_account_mode=""
    fi
    [ "$pin_scope" = "none" ] && { pin_scope=""; pin_mode=""; pin_account=""; pin_account_mode=""; }
elif [ -f "$STATUSLINE_PIN_DEVICE_FILE" ]; then
    # Legacy fallback for older helper installs OR users
    # without the integration at all (in which case the file simply won't
    # exist and both vars stay empty, producing no badge).
    _pin_legacy_combined=$(awk '
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
            # Default "soft" is NOT invented here: it is the documented
            # official default from the SSoT of the external helper,
            # hooks/pin-helper.sh (pin_mode). This legacy inline
            # parser only runs when that helper is absent, so the default
            # is duplicated by necessity — keep it in sync with the SSoT.
            if (mode_value == "") mode_value = "soft"
            printf "%s|%s|%s\n", account_value, mode_value, account_mode_value
        }
    ' "$STATUSLINE_PIN_DEVICE_FILE" 2>/dev/null) || _pin_legacy_combined="||"
    if [ -n "${_pin_legacy_combined%%|*}" ]; then
        pin_account="${_pin_legacy_combined%%|*}"
        _pin_legacy_rest="${_pin_legacy_combined#*|}"
        pin_scope="device"
        pin_mode="${_pin_legacy_rest%%|*}"
        pin_account_mode="${_pin_legacy_rest#*|}"
    fi
fi
unset _pin_layered_resolved _pin_layered_rest _pin_legacy_combined _pin_legacy_rest

gateway_bearer_account=""
# "bearer_key_anthropic_compatible_api_mode" is the OFFICIAL enum value of the
# pin file's [account_mode] field — SSoT: the external pin-helper.
# This is a verbatim comparison against the official value, not a translation;
# keep the literal in sync with the SSoT if that helper ever renames it.
if [ "$pin_account_mode" = "bearer_key_anthropic_compatible_api_mode" ] && [ -n "$pin_account" ]; then
    gateway_bearer_account="$pin_account"
elif [ -n "${STATUSLINE_GATEWAY_BEARER_ACCOUNT:-}" ]; then
    gateway_bearer_account="$STATUSLINE_GATEWAY_BEARER_ACCOUNT"
elif [ -n "${CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION:-}" ]; then
    # Backwards-compatible alias for the variable name the original external
    # wrapper exports. Kept so an existing install does not silently lose its
    # render trigger; prefer STATUSLINE_GATEWAY_BEARER_ACCOUNT above.
    gateway_bearer_account="$CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION"
elif [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "${ANTHROPIC_API_KEY:-}" ] \
     && [ -n "${STATUSLINE_GATEWAY_BASE_URL:-}" ]; then
    # Bearer-mode heuristic, deployment-agnostic: if the session is pointed at
    # a custom inference base URL AND the operator has declared a gateway (see
    # STATUSLINE_GATEWAY_BASE_URL below), treat this as gateway-routed.
    #
    # This value is a BOOLEAN in practice — it is never rendered. It only feeds
    # the JSONL "bearer mode active" flag and the render-decision at the bottom
    # of this file. It therefore carries a generic sentinel rather than any
    # account name. (Before 2026-09-04 this branch pattern-matched one specific
    # private hostname and assigned one specific account name; both were
    # deployment identifiers with no business in a public marketplace, and
    # neither was ever displayed.)
    gateway_bearer_account="gateway-bearer"
fi

# === OPTIONAL: Admission-Gateway Health ===
#
# OFF BY DEFAULT. Requires an explicitly configured gateway (see
# STATUSLINE_GATEWAY_BASE_URL below). With no gateway configured this entire
# section is skipped: no network, no files, no output.
#
# WHAT IT IS FOR: some deployments put an admission gateway in front of the
# Anthropic API that serves inference from a rotating pool of upstream
# accounts. When that is how you are routed, the LOCAL credential no longer
# tells you what is actually serving you, so rendering its account email and
# quota windows is actively misleading. This block instead surfaces four
# signals that describe the live path:
#
#   1. Gate health   — composite of gateway reachability + canary state
#   2. Pool size     — pool.schedulable_active_accounts / pool.total_accounts
#   3. Canary state  — canary_self_test.consecutive_failures count
#   4. Client version — local client version vs the gateway's advertised floor
#
# EXPECTED GATEWAY CONTRACT — any gateway exposing these two anonymous,
# unauthenticated GET routes works; nothing here is vendor-specific:
#   GET /v1/health         → liveness + canary
#   GET /v1/router-status  → superset: adds the per-account pool breakdown
# We fetch the latter only, since it covers all four signals in one request.
#
# Cache: /tmp/statusline-gateway-cache-<hash>.json, 60s TTL, keyed by gateway URL.
# Stale-on-failure: if a fresh fetch fails but a cache exists we render the
# stale data rather than blanking, so a blip does not read as an outage.
#
# Failure semantics (drives $gateway_status string — used downstream to pick
# the render branch and per-token color, no longer a leading visual glyph):
#   reachable + status=ok + canary healthy + errors=0  → "healthy"    (all gray/✓)
#   reachable but canary degraded OR errors>0          → "degraded"   (red ✗N or red ratio)
#   unreachable / no cache                             → "unreachable" (literal red word replaces numerics)
#   /v1/router-status JSON parse failure               → "parse-error" (red word replaces numerics)
#
# Users with no gateway configured never reach any of these states: the block
# short-circuits before the first probe, so there is no timeout to wait on and
# no "unreachable" to suppress. (Until 2026-09-04 they DID pay for a timeout
# against a hardcoded third-party host on every cold cache — see below.)

# GATEWAY_BASE — the admission-gateway base URL. OPT-IN, never hardcoded.
#
# ── Public default: EMPTY. ────────────────────────────────────────────────
# When this resolves empty, the entire gateway block below is skipped: no
# curl, no DNS lookup, no cache file, no JSONL append, and no rendered
# segment. A cc-skills user who has not configured a gateway pays exactly
# nothing for this feature and sees nothing from it.
#
# Until 2026-09-04 this variable was initialised to one specific private
# hostname as a "historical fallback". That was a defect with three faces:
#   1. it published a private deployment's host identifier in a public repo;
#   2. every installer of this marketplace silently probed that third-party
#      host twice per cold cache on every render (/v1/users/me and
#      /v1/router-status), which is unannounced outbound traffic to somebody
#      else's infrastructure; and
#   3. the probe could only ever fail for them, so the cost bought nothing.
#
# ── Resolution order (first non-empty wins) ───────────────────────────────
#   1. $STATUSLINE_GATEWAY_BASE_URL      — explicit env override, any user
#   2. $STATUSLINE_GATEWAY_ENV_FILE      — a shell file exporting
#      (default ~/.config/ccmax/bearer-pin-env.sh)   ANTHROPIC_BASE_URL
#
# Both live OUTSIDE this repository, so the fleet-specific identity stays in
# the operator's private configuration while this script stays generic.
#
# Port note: some deployments expose inference and gateway introspection on
# different ports. $STATUSLINE_GATEWAY_PORT_REWRITE, when set as "FROM:TO",
# rewrites a trailing :FROM to :TO. Unset means the URL is used verbatim.
_pin_file="${STATUSLINE_GATEWAY_ENV_FILE:-${HOME}/.config/ccmax/bearer-pin-env.sh}"
GATEWAY_BASE="${STATUSLINE_GATEWAY_BASE_URL:-}"
if [ -z "$GATEWAY_BASE" ] && [ -r "$_pin_file" ]; then
    _pin_url=$(sed -n 's/^export ANTHROPIC_BASE_URL=//p' "$_pin_file" 2>/dev/null | tr -d "\"'" | head -1)
    if [ -n "$_pin_url" ]; then
        GATEWAY_BASE="$_pin_url"
        if [ -n "${STATUSLINE_GATEWAY_PORT_REWRITE:-}" ]; then
            _pr_from="${STATUSLINE_GATEWAY_PORT_REWRITE%%:*}"
            _pr_to="${STATUSLINE_GATEWAY_PORT_REWRITE#*:}"
            GATEWAY_BASE="${GATEWAY_BASE/:${_pr_from}/:${_pr_to}}"
            unset _pr_from _pr_to
        fi
    fi
fi
# GATEWAY_CONFIGURED is the single gate for every side effect in this feature:
# outbound probes, /tmp cache files, and the JSONL telemetry append. When no
# gateway is configured it stays 0 and this whole block is inert.
GATEWAY_CONFIGURED=0
[ -n "$GATEWAY_BASE" ] && GATEWAY_CONFIGURED=1

GATEWAY_CACHE=""
[ "$GATEWAY_CONFIGURED" -eq 1 ] && \
    GATEWAY_CACHE="/tmp/statusline-gateway-cache-$(printf '%s' "$GATEWAY_BASE" | shasum | cut -c1-8).json"
GATEWAY_CACHE_TTL=60

# Gateway's minimum wrapper version floor — AUTO-DISCOVERED (L1a, 2026-05-13).
#
# Earlier versions hardcoded "1.2.0" here and required a manual bump whenever
# gateway raised its gate. Now we discover the live floor by probing any
# wrapper-gated route (e.g. /v1/users/me) WITHOUT the wrapper version header;
# gateway returns HTTP 403 with `minimum_wrapper_version_required` in the
# JSON body, which IS the current floor. Cached at /tmp/statusline-gateway-floor
# with a 3600s TTL so we only probe gateway once per hour for this value.
#
# Probe failure modes (any → fall back to compiled-in default):
#   - Gateway unreachable: probe times out, no response
#   - Gateway returns 200 (gate disabled / env var unset): no floor to read
#   - Response body doesn't have the expected error.minimum_wrapper_version_required shape
# The fallback ensures the renderer always has SOMETHING to compare against,
# even when gateway is down. The fallback is updated whenever a fresh probe
# succeeds, so cold-start with a stale fallback only matters for the very
# first render after a new install.
GATEWAY_MIN_WRAPPER_VERSION_FALLBACK="1.2.0"
GATEWAY_FLOOR_CACHE="/tmp/statusline-gateway-floor"
GATEWAY_FLOOR_TTL=3600  # 1 hour

# Cache-aware floor lookup. The cache file holds a single line containing the
# discovered floor semver (or empty if discovery failed). On cache miss or
# expiry, probe gateway; on probe failure, fall back to compiled-in default.
GATEWAY_MIN_WRAPPER_VERSION=""
if [ -f "$GATEWAY_FLOOR_CACHE" ]; then
    floor_cache_mtime=$(stat -f %m "$GATEWAY_FLOOR_CACHE" 2>/dev/null || echo 0)
    floor_cache_age=$(( $(date +%s) - floor_cache_mtime ))
    if [ "$floor_cache_age" -lt "$GATEWAY_FLOOR_TTL" ]; then
        GATEWAY_MIN_WRAPPER_VERSION=$(cat "$GATEWAY_FLOOR_CACHE" 2>/dev/null)
    fi
fi
if [ -z "$GATEWAY_MIN_WRAPPER_VERSION" ] && [ "$GATEWAY_CONFIGURED" -eq 1 ]; then
    # Probe a wrapper-gated route anonymously. The gate runs BEFORE auth, so
    # even without a Bearer header we elicit a 403 with the JSON body that
    # carries `minimum_wrapper_version_required`. Implementation note: the
    # `probe_direct curl` call below uses `-s` (NOT `-sf`) because `-f`
    # suppresses the response body on 4xx — and the body is exactly what we
    # need to parse.
    discovered_floor=$(probe_direct curl -s --connect-timeout 1 --max-time 2 \
        "${GATEWAY_BASE}/v1/users/me" 2>/dev/null | python3 -c "
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
        printf '%s' "$discovered_floor" > "$GATEWAY_FLOOR_CACHE"
        GATEWAY_MIN_WRAPPER_VERSION="$discovered_floor"
    else
        GATEWAY_MIN_WRAPPER_VERSION="$GATEWAY_MIN_WRAPPER_VERSION_FALLBACK"
    fi
fi
# Belt-and-braces: the comparison sites below feed this to `sort -V`, which
# must never receive an empty operand. Unconfigured installs skip the probe
# entirely, so this is the path that gives them a well-formed value.
[ -z "$GATEWAY_MIN_WRAPPER_VERSION" ] && \
    GATEWAY_MIN_WRAPPER_VERSION="$GATEWAY_MIN_WRAPPER_VERSION_FALLBACK"

# Fetch /v1/router-status (cache-aware). Skipped entirely — no curl, no DNS,
# no cache file — when no gateway is configured.
gateway_raw=""
gateway_needs_fetch=0
[ "$GATEWAY_CONFIGURED" -eq 1 ] && gateway_needs_fetch=1
if [ "$GATEWAY_CONFIGURED" -eq 1 ] && [ -f "$GATEWAY_CACHE" ]; then
    gateway_cache_mtime=$(stat -f %m "$GATEWAY_CACHE" 2>/dev/null || echo 0)
    gateway_cache_age=$(( $(date +%s) - gateway_cache_mtime ))
    [ "$gateway_cache_age" -lt "$GATEWAY_CACHE_TTL" ] && gateway_needs_fetch=0
fi
if [ "$gateway_needs_fetch" -eq 1 ]; then
    gateway_fresh=$(probe_direct curl -sf --connect-timeout 1 --max-time 2 \
        "${GATEWAY_BASE}/v1/router-status" 2>/dev/null) || gateway_fresh=""
    if [ -n "$gateway_fresh" ]; then
        echo "$gateway_fresh" > "$GATEWAY_CACHE"
        gateway_raw="$gateway_fresh"
    elif [ -f "$GATEWAY_CACHE" ]; then
        # Fetch failed but cache exists → render stale data rather than going
        # dark. The cache mtime already telegraphs staleness to anyone reading
        # the file directly.
        gateway_raw=$(cat "$GATEWAY_CACHE" 2>/dev/null) || gateway_raw=""
    fi
elif [ "$GATEWAY_CONFIGURED" -eq 1 ]; then
    gateway_raw=$(cat "$GATEWAY_CACHE" 2>/dev/null) || gateway_raw=""
fi

# Local client wrapper version (cached by binary mtime). The subprocess
# only re-runs when the binary file itself changes — rare — so the render-time
# cost amortizes to a file stat per render. Empty when the wrapper isn't
# installed (public cc-skills users), which the renderer treats as "skip the
# wrapper segment entirely".
WRAPPER_BIN="${STATUSLINE_CLIENT_WRAPPER_BIN:-${HOME}/.local/bin/ccmax-claude}"
WRAPPER_VERSION_CACHE="/tmp/statusline-client-version"
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

# Parse the gateway snapshot into primitives. One python invocation emits a
# fixed-shape pipe-delimited line; shell unpacks with `IFS='|' read`. Output:
#   <status>|<schedulable>|<rotation_size>|<errors>|<canary_failures>|<canary_class>
# status      ∈ {healthy, degraded, parse-error}; unreachable is signalled by
#               empty gateway_raw before we enter this block
# canary_class ∈ {healthy, since-start-failure, transient, recent-degradation,
#               unknown} — see classification rules below
#
# Pool denominator semantics — we deliberately EXCLUDE inactive accounts from
# the denominator. gateway's response distinguishes three account states:
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
gateway_status="unreachable"
pool_schedulable=0
pool_rotation_size=0
pool_errors=0
# canary_failures retained as a parsed primitive even though the L1d
# renderer prefers humanized duration over raw count; downstream task #7 (L2
# statistics surface) will append this to the per-render JSONL log.
# shellcheck disable=SC2034
canary_failures=0
canary_class="unknown"
canary_last_observed_http_status_for_render=""
pool_resilience_state_machine_label=""
unified_state_name_for_render_label=""
canary_failure_duration_humanized_short_form=""
if [ -n "$gateway_raw" ]; then
    gateway_parsed=$(echo "$gateway_raw" | python3 -c "
import sys, json

# ===========================================================================
# L1d UNIFIED-RENDER PRIMITIVE EXTRACTOR (cc-skills statusline, 2026-05-13)
# ===========================================================================
# Reads gateway's /v1/router-status response and emits a single pipe-delimited
# line of 10 primitives that the shell side unpacks via IFS='|' read. The
# verbose field names below match the names exported to shell-side variables
# downstream so a future reader can grep across the python<->bash boundary.
# Output line shape:
#   <gate_status>|<pool_schedulable>|<pool_rotation_size>|<pool_errors>
#    |<canary_consecutive_failures>|<canary_classification_four_state>
#    |<canary_last_observed_http_status_for_render>
#    |<pool_resilience_state_machine_label>
#    |<unified_state_name_for_render_label>
#    |<canary_failure_duration_humanized_short_form>

def passthrough_official_canary_http_status_for_render(
    last_observed_http_status_code_from_canary_self_test_block,
):
    # OFFICIAL-VALUES rendering (operator directive 2026-06-11): emit the
    # canary's last_observed_http_status_code VERBATIM. This replaces the
    # retired AU/QT/CF/UP/IN letter-code translation (an RFC-9457-inspired
    # taxonomy, removed because it was a hand-made re-labeling of official
    # HTTP statuses — 401 IS the value the canary observed; no legend
    # needed). The value 0 is also the field's official recorded value
    # (HTTP request never completed — no status observed) and renders
    # verbatim. 2xx/3xx return empty (not a failure token; the render path
    # only attaches this on degraded states anyway). NOTE: this python runs
    # inside a shell double-quoted python3 -c block — NEVER use a literal
    # double-quote character anywhere in it (it terminates the shell string
    # and the parser dies silently behind 2>/dev/null).
    s = int(last_observed_http_status_code_from_canary_self_test_block or 0)
    if 200 <= s < 400:
        return ''
    return str(s)

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
    #   unproven (gray)    ← no recent request carried forward-path evidence
    #   no-health-signal (red) ← gateway exposed neither health block at all
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
    # Contract break outranks 'unproven': a missing signal is a defect to fix,
    # whereas an unproven one is a normal idle state.
    if canary_classification_four_state == 'no-health-signal':
        return 'no-health-signal'
    # 'unproven' + a healthy pool is the ordinary idle case. It must NOT collapse
    # to 'healthy' (we have no forward-path evidence) and must NOT fall through
    # to 'unknown', which the renderer alarms on in red. A quiet fleet is not an
    # incident; claiming either health or failure here would be a fabrication.
    if canary_classification_four_state == 'unproven':
        return 'unproven'
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

    # ── Tolerant reader: new access-log-derived block, else legacy canary ──
    #
    # gateway is migrating OFF the synthetic canary (the guiding rule being that monitoring
    # must never spend inference). The new block derives forward-path health from
    # real forwarded requests that already happened, so it costs nothing.
    #
    # Precedence is deliberate and must not be reordered:
    #   1. upstream_health_observed_from_forwarded_request_log  (new, zero-token)
    #   2. canary_self_test                                    (legacy, synthetic)
    #   3. neither                                             (explicit unknown)
    #
    # This reader ships BEFORE gateway changes, so a statusline on any host keeps
    # working against either binary during the rollout. Do NOT collapse it to the
    # new field alone until every gateway in the fleet emits it — an old binary
    # would then render 'no-health-signal' red across the whole fleet.
    upstream_health = d.get('upstream_health_observed_from_forwarded_request_log') or {}
    canary = d.get('canary_self_test', {}) or {}

    if upstream_health:
        # NEW PATH — evidence from real traffic.
        observed_state = str(upstream_health.get('state') or 'unproven').strip()
        forwarded_in_window = int(upstream_health.get('forwarded_requests_in_window', 0) or 0)
        failed_in_window = int(upstream_health.get('failed_requests_in_window', 0) or 0)
        observation_window_seconds = int(
            upstream_health.get('observation_window_secs', 300) or 300
        )
        # 'unproven' is NOT a failure — it means no recent request carried
        # evidence either way (idle fleet, or fresh restart). Rendering it as a
        # failure would page the operator for being idle, which is the exact
        # trap the deep-probe conversion hit first.
        if observed_state == 'serving':
            canary_classification_four_state = 'healthy'
        elif observed_state == 'degraded':
            canary_classification_four_state = 'recent-degradation'
        else:
            canary_classification_four_state = 'unproven'
        # The evidence token replaces the canary's single HTTP status: a ratio is
        # what this signal actually knows. Empty while serving (nothing to say).
        canary_last_observed_http_status_code = 0
        # Only render the ratio when there IS evidence to summarize. A bare
        # '0/0' on an idle fleet looks like a measurement; it is the absence of
        # one, and the 'unproven' label already says that.
        canary_evidence_token_for_render = (
            f'{failed_in_window}/{forwarded_in_window}'
            if (forwarded_in_window > 0 and canary_classification_four_state != 'healthy')
            else ''
        )
        canary_failure_duration_seconds_lower_bound_override = (
            observation_window_seconds
            if canary_classification_four_state == 'recent-degradation' else 0
        )
        canary_consecutive_failures_count = failed_in_window
    elif canary:
        # LEGACY PATH — synthetic canary. Unchanged L1b four-state classification.
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
        canary_evidence_token_for_render = None  # renderer uses the HTTP status
        canary_failure_duration_seconds_lower_bound_override = None
    else:
        # NEITHER field present. This is a real contract break (gateway answered
        # /v1/router-status but exposes no forward-path health at all), so say so
        # loudly rather than defaulting to 'healthy' — a monitor that reports
        # health it cannot observe is worse than one that admits ignorance.
        canary_classification_four_state = 'no-health-signal'
        canary_consecutive_failures_count = 0
        canary_last_observed_http_status_code = 0
        canary_evidence_token_for_render = ''
        canary_failure_duration_seconds_lower_bound_override = 0
        canary_configured_interval_seconds = 300

    # Gate-status binary (legacy primitive retained for backward-compat with
    # the existing $gateway_status check that triggers render-or-suppress).
    if pool_error_accounts_count > 0 or canary_classification_four_state == 'recent-degradation':
        legacy_gate_status_binary = 'degraded'
    else:
        legacy_gate_status_binary = 'healthy'

    # L1d new primitives. The type-code slot carries whichever evidence the
    # active signal actually has: the canary's official HTTP status (legacy) or
    # the access-log failure ratio (new). Never both, never invented.
    if canary_evidence_token_for_render is not None:
        canary_last_observed_http_status_for_render = canary_evidence_token_for_render
    else:
        canary_last_observed_http_status_for_render = \
            passthrough_official_canary_http_status_for_render(
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
    # Duration. Legacy multiplies consecutive failures by the tick interval (a
    # lower bound). The new signal has no tick cadence, so it reports the
    # observation window instead — the honest statement is 'degraded across the
    # last <window>', not a fabricated streak length.
    if canary_failure_duration_seconds_lower_bound_override is not None:
        canary_failure_duration_seconds_lower_bound = \
            canary_failure_duration_seconds_lower_bound_override
    else:
        canary_failure_duration_seconds_lower_bound = (
            canary_consecutive_failures_count * canary_configured_interval_seconds
        )
    canary_failure_duration_humanized_short_form = (
        format_seconds_as_humanized_short_duration_with_no_ago_suffix(
            canary_failure_duration_seconds_lower_bound,
        )
        if canary_failure_duration_seconds_lower_bound > 0 else ''
    )

    print(
        f'{legacy_gate_status_binary}'
        f'|{schedulable_active_accounts_count}'
        f'|{rotation_working_set_size}'
        f'|{pool_error_accounts_count}'
        f'|{canary_consecutive_failures_count}'
        f'|{canary_classification_four_state}'
        f'|{canary_last_observed_http_status_for_render}'
        f'|{pool_resilience_state_machine_label}'
        f'|{unified_state_name_for_render_label}'
        f'|{canary_failure_duration_humanized_short_form}'
    )
except Exception:
    # Fail-safe shape: same 10 fields, sentinel values that the renderer
    # interprets as 'parse-error' (red, replaces numerics with the literal
    # 'parse-error' word — same UX as 'unreachable').
    print('parse-error|0|0|0|0|unknown||unknown|unknown|')
" 2>/dev/null) || gateway_parsed=""
    if [ -n "$gateway_parsed" ]; then
        IFS='|' read -r gateway_status pool_schedulable pool_rotation_size pool_errors canary_failures canary_class canary_last_observed_http_status_for_render pool_resilience_state_machine_label unified_state_name_for_render_label canary_failure_duration_humanized_short_form <<< "$gateway_parsed"
    fi
fi

# L1c (real-traffic cross-check, 2026-05-13) — second-opinion damper on the
# canary signal. The canary is one synthetic probe; if it's degraded, that
# may or may not reflect actual upstream health. Real traffic is the ground
# truth: when this Mac's Claude Code session is actively pumping requests
# through gateway AND those requests are completing, gateway IS serving,
# regardless of what the canary says.
#
# Detection signals:
#   (a) $ANTHROPIC_BASE_URL points at gateway (bearer-mode routing) AND
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
# Deployment-agnostic "is this session routed through the configured gateway?"
# test (2026-09-04). This previously pattern-matched one private hostname plus
# two loopback forms. We now compare the live $ANTHROPIC_BASE_URL against the
# gateway the operator actually configured, which is both generic AND more
# correct: the old literal list went stale every time the fleet moved hosts,
# silently disabling the damper while still looking like it worked.
real_traffic_recent=0
if [ "$GATEWAY_CONFIGURED" -eq 1 ] && [ -n "${ANTHROPIC_BASE_URL:-}" ] \
   && [ -n "$transcript_file" ] && [ -f "$transcript_file" ]; then
    # Compare on host[:port], ignoring scheme and any trailing path.
    _rt_env_authority="${ANTHROPIC_BASE_URL#*://}"; _rt_env_authority="${_rt_env_authority%%/*}"
    _rt_gw_authority="${GATEWAY_BASE#*://}";       _rt_gw_authority="${_rt_gw_authority%%/*}"
    # Loopback is always accepted: the wrapper's local reverse proxy fronts the
    # gateway on 127.0.0.1, so a loopback base URL still means gateway-routed.
    case "$_rt_env_authority" in
        127.0.0.1:*|localhost:*|"$_rt_gw_authority")
            transcript_mtime=$(stat -f %m "$transcript_file" 2>/dev/null || echo 0)
            transcript_age=$(( $(date +%s) - transcript_mtime ))
            [ "$transcript_age" -lt 60 ] && real_traffic_recent=1
            ;;
    esac
    unset _rt_env_authority _rt_gw_authority
fi
if [ "$real_traffic_recent" -eq 1 ]; then
    case "$canary_class" in
        recent-degradation) canary_class="transient" ;;
        transient)          canary_class="since-start-failure" ;;
    esac
    # Also clear pool-error escalation: if traffic is flowing, error_accounts
    # might be a transient blip the rotation is already routing around.
    if [ "$gateway_status" = "degraded" ] && [ "$pool_errors" -gt 0 ] && [ "$canary_class" != "recent-degradation" ]; then
        gateway_status="healthy"
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
#   Line 1: git stats | model id + inference-mode badges (gray suffix)
#   Line 2: code stats (scc — LOC, files, complexity, top languages, COCOMO)
#   Line 3: UTC time | local time | gateway (inline)
#   Line 4: ~/path | github-url
#   Line 5: session UUID (if available)
#   Line 6: ~/asciinemalogs cast UUID

# === Model identity + inference-mode badges (first-line suffix, 2026-06-10) ===
# NATIVE-FIELDS-ONLY INVARIANT (operator directive 2026-06-11): every token in
# this segment is a DIRECT, parameterless echo of a statusline stdin field —
# no composite/inferred state is ever rendered. Pinned by the bats test
# "model segment renders only native payload echoes (no inferred badges)".
#
# Native statusline-input fields (verified against live ~/.claude/statusline.jsonl):
#   .model.id          raw model id incl. variant suffix (e.g. claude-fable-5[1m])
#   .effort.level      reasoning effort (e.g. high)
#   .thinking.enabled  extended thinking (bool)
#   .fast_mode         fast mode active (bool)
# OFFICIAL-NAMES/VALUES rendering (2026-06-11 operator directive):
#   effort     → bare official level word ("effort:" label dropped)
#   thinking   → official field name + VERBATIM official boolean value
#                (thinking:true / thinking:false); omitted when the payload
#                lacks the field — no invented on/off translation
#   fast_mode  → official field name shown when true, omitted when false
#                (no truncated "fast" label)
# Render (all BRIGHT_BLACK, operator-selected subdued style):
#   ... | v12.43.0 3h ago | claude-fable-5[1m] · xhigh · thinking:true
# .model.id may be empty at session start (no API call yet) — fall back to
# $model_raw (display_name-first decode above); suppress segment if both empty.
#
# ── ✦ ultracode badge RETIRED 2026-06-11 (lived one day) ────────────────────
# The 2026-06-10 heuristic (effort=="xhigh" AND thinking AND NOT fast_mode)
# was REFUTED by live counterexamples within 24h: sessions ea782bfd (project-e)
# and a9861cbf (claude-sys) rendered xhigh with ZERO ultracode activation in
# their transcripts — the operator saw "✦ ultracode" while it was OFF. Root
# cause of the bad heuristic: effort levels persist (saved default / carried
# state) while ultracode itself is session-only in-memory appState
# ({value:"xhigh", ultracode:true}) with NO statusline-payload field, so
# xhigh ⇏ ultracode. The native tokens effort:xhigh · thinking:on already
# carry the full payload truth; interpreting them is the operator's job.
# Reinstate ONLY if upstream ships a native `ultracode` payload field.
# Model segment is its OWN line (moved off line 1 — 2026-06-19 operator
# directive). Renders native payload echoes (.model.id, .effort.level,
# .thinking.enabled, .fast_mode) and ends with the running Claude Code
# version straight from the statusline payload's native .version field
# ("our current version of Claude Code locally") — no subprocess, official
# value verbatim per the NATIVE-FIELDS-ONLY invariant. Starts with the model
# token directly (no leading " | " — that separator existed only when this
# was appended to git_changes).
model_inline=""
model_token="${model_id:-$model_raw}"
if [ -n "$model_token" ]; then
    model_inline="${BRIGHT_BLACK}${model_token}${RESET}"
    [ -n "$effort_level" ] && model_inline="${model_inline}${BRIGHT_BLACK} · ${effort_level}${RESET}"
    [ -n "$thinking_enabled" ] && model_inline="${model_inline}${BRIGHT_BLACK} · thinking:${thinking_enabled}${RESET}"
    [ "$fast_mode_flag" = "true" ] && model_inline="${model_inline}${BRIGHT_BLACK} · fast_mode${RESET}"
    [ -n "$cc_version" ] && model_inline="${model_inline} ${BRIGHT_BLACK}|${RESET} ${BRIGHT_BLACK}${cc_version}${RESET}"
fi

# === Context window bracketed-zone bar (appended to model line) ===
# Design: ▕<safe-fill>·····|≈≈≈≈▏  where | marks the compaction trigger.
# Left zone = safe capacity before compaction fires.
# Right zone = the do-not-enter region past the trigger.
#
# compact_pct from CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (confirmed present in env
# via settings.json; default 73 when absent). Bar suppressed at session start
# when context_window fields are absent OR when model_inline is still empty
# (no model yet — nothing to append to).
#
# Color tiers:
#   far from trigger (>15pp headroom)  — BRIGHT_BLACK (dim, non-distracting)
#   approaching (<= 15pp headroom)     — YELLOW
#   past trigger                       — RED
#
# Readout (right of bar): N% · tok/win · ~Nk until compact
ctx_bar_segment=""
if [ -n "$ctx_window_size" ] && \
   [ "${ctx_window_size:-0}" -gt 0 ] 2>/dev/null && [ -n "$ctx_used_pct" ]; then
    _cpct="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-73}"
    _BLEN=20  # total inner bar width (safe + danger combined)

    # === EXACT THRESHOLD COMPUTATION (mirrors Claude Code bundle math) ===
    # The actual compact trigger is NOT simply pct% of the raw window.
    # Bundle chain: window  = min(modelMax, CLAUDE_CODE_AUTO_COMPACT_WINDOW)  <-- the clamp
    #               cee()   = window - min(ehe(), AFi=20000)
    #               Swn()   = min(floor(effective * pct/100), effective - 13000)
    #               A8r()   = min(effective - round(effective*0.2), Swn())
    # CRITICAL (2026-06-24): CLAUDE_CODE_AUTO_COMPACT_WINDOW caps the window
    # BEFORE pct is applied. Computing against the RAW 1M window over-promised
    # headroom — empirically the readout said "~149k until compact" while Claude
    # Code actually compacted at ~570k ( = (min(1M,800k)-20k)*0.73 ). Apply the
    # same min(modelMax, AUTO_COMPACT_WINDOW) clamp so the readout is truthful.
    # We still approximate effective = window - 20000 (AFi cap), ignoring the
    # per-model ehe() variance and the 0.2 precompute fraction (which only
    # tightens the result to Swn anyway for typical pct values like 73).
    _acw="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-0}"
    _cwin=$ctx_window_size
    [ "${_acw:-0}" -gt 0 ] 2>/dev/null && [ "$_acw" -lt "$_cwin" ] 2>/dev/null && _cwin=$_acw
    _effective=$(( _cwin - 20000 ))
    _thresh=$(( _effective * _cpct / 100 ))
    _thresh_cap=$(( _effective - 13000 ))
    [ "${_thresh:-0}" -gt "${_thresh_cap:-0}" ] 2>/dev/null && _thresh=$_thresh_cap
    # Threshold as % of RAW window (bar separator + color tier land on the
    # visible bar, which is always drawn against the raw model window).
    _trigger_pct=$(( _thresh * 100 / ctx_window_size ))

    # Bar separator at the EXACT trigger percentage, not at raw pct
    _sw=$(( (_BLEN * _trigger_pct + 50) / 100 ))
    _dw=$(( _BLEN - _sw ))

    # Fill position: how far the bar is filled (proportional to used_pct of raw window)
    _ft=$(( (_BLEN * ctx_used_pct + 50) / 100 ))
    _fs=$(( _ft < _sw ? _ft : _sw ))          # filled in safe zone
    _us=$(( _sw - _fs ))                       # empty dots in safe zone
    _fd=$(( _ft > _sw ? _ft - _sw : 0 ))      # filled past separator (past trigger)
    _ud=$(( _dw - _fd ))                       # remaining ≈ in danger zone
    [ "${_ud:-0}" -lt 0 ] && _ud=0

    # Color tier.
    # RED: token-level comparison against the exact threshold (avoids the
    #      integer-% rounding gap where e.g. 72% > 71 but 715k < 715,400).
    # YELLOW: 12pp before the trigger percentage (practical "approaching" zone).
    if [ "${ctx_used_tok:-0}" -ge "${_thresh:-999999999}" ] 2>/dev/null; then
        _bc="$RED"; _sc="$RED"; _dc="$RED"
    elif [ "${ctx_used_pct:-0}" -ge $(( _trigger_pct - 12 )) ] 2>/dev/null; then
        _bc="$YELLOW"; _sc="$YELLOW"; _dc="$BRIGHT_BLACK"
    else
        _bc="$BRIGHT_BLACK"; _sc="$BRIGHT_BLACK"; _dc="$BRIGHT_BLACK"
    fi

    # Build character runs (pure bash, no subshells)
    _bf="";  for ((i=0; i<_fs; i++)); do _bf+="█";  done
    _be="";  for ((i=0; i<_us; i++)); do _be+="·";  done
    _bdf=""; for ((i=0; i<_fd; i++)); do _bdf+="█"; done
    _bde=""; for ((i=0; i<_ud; i++)); do _bde+="≈"; done

    # Distance until the exact computed threshold
    _utok=$(( _thresh - ctx_used_tok ))
    if [ "${_utok:-0}" -le 0 ] 2>/dev/null; then
        _until_part="past compact"
    elif [ "${_utok:-0}" -ge 1000000 ] 2>/dev/null; then
        _until_part="~$(( _utok / 1000000 ))M until compact"
    elif [ "${_utok:-0}" -ge 1000 ] 2>/dev/null; then
        _until_part="~$(( _utok / 1000 ))k until compact"
    else
        _until_part="~${_utok} until compact"
    fi

    # Assemble: ▕<safe-fill><safe-empty>|<danger-fill><danger-empty>▏ N% · tok/win · ~Nk until compact
    ctx_bar_segment="${BRIGHT_BLACK}ctx ▕${RESET}${_bc}${_bf}${RESET}${BRIGHT_BLACK}${_be}${RESET}${_sc}|${RESET}${_bc}${_bdf}${RESET}${_dc}${_bde}${RESET}${BRIGHT_BLACK}▏ ${ctx_used_pct}% · ${ctx_tok_compact}/${ctx_win_compact} · ${_until_part}${RESET}"
fi

line1="${git_changes}"

# Line 3: path | GitHub URL (visibility)
vis_label=""
case "$repo_visibility" in
    "")      ;;  # no remote / repo missing — badge off
    private) vis_label=" ${YELLOW}(private)${RESET}" ;;
    public)  vis_label=" ${BRIGHT_BLACK}(public)${RESET}" ;;
    *)       vis_label=" ${RED}(${repo_visibility})${RESET}" ;;  # gh's own diagnostic, verbatim
esac
if [[ -n "$github_url" ]]; then
    if [[ "$git_branch" == "main" || "$git_branch" == "master" ]]; then
        line_repo="${GREEN}${repo_path}${RESET} | ${BRIGHT_BLACK}${github_url}${RESET}${vis_label}"
    else
        line_repo="${GREEN}${repo_path}${RESET} | ${MAGENTA}${github_url}${RESET}${vis_label}"
    fi
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # OFFICIAL-VALUES-ONLY (2026-06-11): surface git's own diagnostic for
    # the missing origin remote instead of the invented "no remote" label.
    # `2>&1 1>/dev/null` captures stderr only; the severity prefix
    # (fatal:/error:) is stripped — the ⚠ glyph already carries severity.
    git_diag=$(git remote get-url origin 2>&1 1>/dev/null | sed -E 's/^(fatal|error): //')
    line_repo="${GREEN}${repo_path}${RESET} | ${RED}⚠ ${git_diag}${RESET}"
else
    # Same policy outside a work tree: render git's official diagnostic
    # (e.g. "not a git repository ...") instead of the invented "no git".
    git_diag=$(git rev-parse --is-inside-work-tree 2>&1 1>/dev/null | sed -E 's/^(fatal|error): //')
    line_repo="${GREEN}${repo_path}${RESET} | ${RED}⚠ ${git_diag}${RESET}"
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

# Model segment line (own line as of 2026-06-19) — after code stats, before
# the datetime/gateway line. Suppressed entirely when no model token.
[ -n "$model_inline" ] && echo -e "$model_inline"

# Context window bar (own line as of 2026-06-21) — after model line, before
# datetime/gateway. Suppressed when context_window absent (session start).
[ -n "$ctx_bar_segment" ] && echo -e "$ctx_bar_segment"

# =============================================================================
# Gateway gateway summary — render LEGEND + SOURCE-OF-TRUTH map
# =============================================================================
#
# Final output shapes (L1d unified multi-dimensional render, 2026-05-13):
#
#   ... UTC | ... PDT | gateway 3/3 ✓ 1.93.0                                ← all healthy
#   ... UTC | ... PDT | gateway 3/3 ✗401 3d since-boot 1.93.0                ← today (config bug, gray)
#   ... UTC | ... PDT | gateway 2/3 ⚠503 3m flapping 1.93.0                   ← one backend transient
#   ... UTC | ... PDT | gateway 1/3 ⚠503 12m partial-outage 1.93.0            ← last healthy account, pre-warn
#   ... UTC | ... PDT | gateway 0/3 ✗503 47m outage 1.93.0                    ← total outage, alarm
#   ... UTC | ... PDT | gateway 3/3 ✓ 1.2.0=1.2.0                             ← wrapper exactly at floor, pre-warn
#   ... UTC | ... PDT | gateway unreachable 1.93.0                          ← gateway down
#
# The render grammar is:
#   gateway <pool-ratio> <severity-glyph><type-code> [<duration>] [<state-name>] <wrapper-version>
#
# State is conveyed entirely by per-token coloring + the named state label:
#   "all healthy"    → ✓ in GREEN, rest in BRIGHT_BLACK, no state label
#   "since-boot"     → ✗401 (official status) and "since-boot" in BRIGHT_BLACK (calm, config bug)
#   "flapping"       → ⚠<type> and "flapping" in YELLOW (watch, transient)
#   "partial-outage" → ⚠<type> and "partial-outage" in YELLOW, pool ratio also YELLOW (pre-warn — last account standing)
#   "outage"         → ✗<type> and "outage" in RED, pool ratio in RED if 0/N (alarm)
#   "wrapper skewed" → wrapper version in YELLOW with "<floor" suffix
#   "wrapper at floor" → wrapper version in YELLOW with "=floor" suffix (pre-warn)
#   "gateway down"   → literal RED word "unreachable" replaces numerics
#
# Three label-stripping rounds preceded this design (all 2026-05-13):
#   - dropped the "pool", "canary", "wrapper" field labels (redundant within
#     a segment already anchored by "gateway")
#   - dropped the leading 🟢/🟡/🔴 gate-state emoji (redundant with per-token
#     coloring + state name)
#   - retired the "[5th-fleet]" bearer-mode badge (terminology no longer used)
#
# Every visible token, including the labels we stripped, is mapped here so the
# next maintainer can re-derive what each rendered glyph means without
# re-grepping gateway's source or CLAUDE.md. Tokens are listed left-to-right
# in render order.
#
# ── Gate emoji (RETIRED 2026-05-13) ──────────────────────────────────────────
#   Earlier versions led the segment with a 🟢/🟡/🔴 dot synthesised from
#   pool.error_accounts + canary_self_test.is_degraded_per_threshold +
#   reachability. Retired because:
#     - 🟢 "all healthy" was redundant with every trailing token being gray/✓
#     - 🟡 "degraded" was redundant with the RED ✗N glyph or RED pool ratio
#     - 🔴 "unreachable" was redundant with the literal RED word "unreachable"
#   The python parser still produces $gateway_status ∈ {healthy, degraded,
#   parse-error, unreachable} because that variable drives WHICH render
#   branch runs (numeric tokens vs. "unreachable" word), but the value is
#   no longer mapped to a leading visual glyph.
#
# ── "gateway" anchor word ───────────────────────────────────────────────────
#   The single retained label. Identifies which subsystem the segment is
#   reporting on. Without it the trailing numbers would float context-free
#   after the datetime. Rendered in BRIGHT_BLACK (gray) to de-emphasise.
#
# ── "3/3"  ←  pool numerator/denominator ─────────────────────────────────────
#   Render shape: <schedulable_active>/<rotation_working_set_size>
#   Numerator   = /v1/router-status .pool.schedulable_active_accounts
#                 (accounts whose status=="active" AND schedulable==true,
#                  i.e. currently picking traffic from gateway's rotation)
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
#   and the segment is already anchored by "gateway".
#   Live cross-reference: pool.per_account_summaries[] in the same response
#   carries each account's {name, status, schedulable} triple if you need to
#   know WHICH account is in which state.
#
# ── "✓" or "✗401 3d" or "⚠503 12m"  ←  severity-glyph + official status + duration ──
#   The L1d unified render replaced the raw consecutive-failure-count display
#   with a three-token composite that's both more glanceable and more
#   actionable. Each token answers a distinct operator question:
#
#     severity-glyph   How urgent? — ✓ (none), ⚠ (warn), ✗ (alarm or calm)
#     official status   What failed? — the canary's last_observed_http_status_code VERBATIM (401, 429, 503, 0=never completed)
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
#   Status rendering (official-values directive 2026-06-11): the canary's
#   last_observed_http_status_code renders VERBATIM (e.g. 401, 429, 503).
#   0 is the field's official recorded value when the HTTP request never
#   completed (network/timeout before any status was observed). The former
#   AU/QT/CF/UP/IN letter-code translation (RFC-9457-inspired) is RETIRED —
#   it re-labeled official statuses, violating the official-values policy.
#
#   The single source of type information today is the LAST observed canary
#   status code. Richer per-account failure reasons (one type-code per pool
#   account in the rotation) require L3 server work (task #8 — extending the
#   gateway response with .pool.per_account_failure_reason[]).
#
#   Duration formula:
#     duration_secs = consecutive_failures × configured_interval_secs
#     human-readable form: '8s', '47m', '18h', '3d', '5w' (no 'ago' suffix)
#   This is a lower bound — actual duration could be slightly larger because
#   the response only reports the CURRENT consecutive run, not the precise
#   first-failure timestamp. Exact timestamps require L3 server work (adding
#   .canary_self_test.first_failure_at_unix_secs).
#
#   L1c real-traffic damper: when $ANTHROPIC_BASE_URL points at gateway AND
#   the current transcript JSONL has mtime within last 60s (= real prompts
#   are completing through gateway right now), recent-degradation gets
#   downgraded to transient, and transient gets downgraded to since-start-
#   failure. Healthy stays healthy. since-start-failure stays. Damper not
#   silencer — real traffic confirms gateway is serving, so the canary alarm
#   cannot be at "real problem" severity, but residual flapping signal is
#   kept visible.
#
#   What the canary actually IS:
#     A gateway implementing this contract runs a timer on
#     .canary_self_test.configured_interval_secs. Each fire posts a synthetic
#     /v1/messages request to .canary_self_test.target_loopback_url (i.e. the
#     gateway probes ITSELF). If the response isn't 200 the
#     consecutive_failures counter increments; on any success it resets to 0.
#     This reader only consumes the reported fields — it does not depend on
#     any particular gateway implementation.
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
#     "since-boot" → file an issue against gateway; do NOT page
#     "flapping"   → watch for next minute; may self-recover
#     "partial-outage" → intervene now; pool has no redundancy
#     "outage"     → page someone immediately
#
# ── "1.93.0" or "1.93.0<1.2.0"  ←  local client wrapper version ────────
#   Render shape: bare semver, or "X<Y" when X is below floor Y.
#   Source X = $("$WRAPPER_BIN" --version), cached by binary mtime in
#              /tmp/statusline-client-version. Empty when the binary isn't
#              installed (segment then omits the version entirely).
#   Source Y = GATEWAY_MIN_WRAPPER_VERSION — AUTO-DISCOVERED (L1a).
#              On a miss against /tmp/statusline-gateway-floor (3600s TTL), we
#              anonymously probe gateway's /v1/users/me without the wrapper
#              version header and parse .error.minimum_wrapper_version_required
#              out of the 403 response body. Caches the discovered value, so
#              when gateway raises its floor, the next render within the
#              hour picks it up — no manual constant bump required. On probe
#              failure (gateway unreachable, gate disabled, parse error)
#              we fall back to compiled-in GATEWAY_MIN_WRAPPER_VERSION_FALLBACK
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
#   distinguishes "gateway is genuinely down" from "got a response but
#   couldn't parse it" (the latter would just show empty numerics if we
#   omitted this). With the gate emoji retired, this word IS the down-state
#   signal — the red color on the word itself replaces the prior red dot.
#
# ── pin scope+mode badge (RETIRED 2026-05-13) ───────────────────────────────
#   Earlier versions rendered a bracketed scope+mode marker like
#   "[device:soft]" or "[repo:strict]" synthesised from
#   the external pin-helper.s resolver in its
#   pin-helper.sh, with YELLOW for ":soft" and RED for ":strict" coloring.
#   Retired per operator directive 2026-05-13 because under bearer-mode
#   routing gateway picks the upstream OAuth account dynamically per-
#   request, so knowing WHICH scope holds the pin no longer changes the
#   operator's mental model of "what is actually serving me". The pin
#   resolution itself still runs upstream — its output feeds bearer-mode
#   detection (see next section) — but the visible badge is dropped.
#
# ── Bearer-mode detection (NO visible badge) ─────────────────────────────────
#   $gateway_bearer_account is set via pin file's account_mode field, the
#   STATUSLINE_GATEWAY_BEARER_ACCOUNT env var, or by
#   matching $ANTHROPIC_BASE_URL against the configured gateway. It gates
#   whether to render the gateway line at all (so that a red "unreachable"
#   warning still appears on a bearer-routed session even if no pin exists)
#   but no longer produces a visible label — the prior "[5th-fleet]" badge
#   was retired 2026-05-13 alongside the broader fleet-terminology cleanup.
#
# ── Line-suppression rule ────────────────────────────────────────────────────
#   The whole gateway segment is suppressed (only datetime renders) when ALL of:
#     - gateway_status == "unreachable", AND
#     - gateway_bearer_account is empty
#   (The pin_badge render-trigger was retired 2026-05-13; its dead
#   placeholder variable was removed 2026-06-10.)
#   This is the "no integration installed at all" case (most public cc-skills
#   users). They see the bare datetime line and nothing else.
# =============================================================================

# Pin scope+mode badge RETIRED 2026-05-13 (operator directive: "[repo:soft]
# no longer needed"). The upstream pin-resolution cascade still runs because
# pin_account_mode + pin_account feed into gateway_bearer_account
# detection, which gates the render-decision below. The visible badge itself
# is dropped — the operator has no remaining need to see WHICH scope holds
# the pin since under bearer-mode routing gateway picks the upstream
# account dynamically per-request anyway. (2026-06-10: the always-empty
# pin_badge placeholder variable was removed from the render decision
# and echo below — dead-code cleanup, zero behavior change.)

# NOTE: gate-state emoji (🟢/🟡/🔴) was REMOVED 2026-05-13. Rationale: every
# state the emoji could signal is already expressed by a colored token after
# the "gateway" anchor — the RED ✗N glyph carries "canary degraded", the
# RED pool ratio carries "errors in rotation", and the literal RED word
# "unreachable" carries "gateway down". The emoji was therefore pure
# duplication. The state is now read entirely from the per-token coloring of
# the trailing numbers/words.

# =============================================================================
# L1d MULTI-DIMENSIONAL UNIFIED RENDERER (2026-05-13)
# =============================================================================
# Render shape (all tokens after the BRIGHT_BLACK "gateway" anchor):
#
#   gateway <N/M> <severity><type>[<duration>] [<state-name>] <wrapper>
#
#   N/M         pool ratio, colored by pool resilience state machine
#               (BRIGHT_BLACK healthy, YELLOW degraded/partial-outage, RED total-outage)
#   severity    ✓ healthy (GREEN) | ✗ degraded/outage (RED/gray) | ⚠ pre-warn (YELLOW)
#   status      official HTTP status VERBATIM — only when severity != ✓ (the canary's
#               last_observed_http_status_code; letter-code taxonomy retired 2026-06-11)
#   duration    humanized canary failure duration (e.g. 18h, 3m, 2d) — only
#               when severity != ✓
#   state-name  since-boot | flapping | partial-outage | outage — operator-
#               facing label that names the actionable failure category
#   wrapper     local client wrapper version, with <floor suffix (YELLOW) when
#               below GATEWAY_MIN_WRAPPER_VERSION, or =floor suffix (YELLOW)
#               when exactly at floor (pre-warn for next floor bump)
#
# Scenario examples (against today's live state and hypotheticals):
#   gateway 3/3 ✓ 1.93.0                              all healthy
#   gateway 3/3 ✗401 18h since-boot 1.93.0             today (config bug, gray)
#   gateway 2/3 ⚠503 3m flapping 1.93.0                one backend transient
#   gateway 1/3 ⚠503 12m partial-outage 1.93.0         last healthy, pre-warn
#   gateway 0/3 ✗503 47m outage 1.93.0                 total outage, alarm
#   gateway 3/3 ✓ 1.2.0=1.2.0                          wrapper exactly at floor
#
# Full source-of-truth legend for each token lives in the in-script LEGEND
# block earlier in the file (search "Gateway gateway summary — render LEGEND").

# =============================================================================
# L2 STATISTICS SURFACE — JSONL append per render (2026-05-13, task #7)
# =============================================================================
# Persists every parsed gateway state to ~/.claude/gateway-state.jsonl, one
# line per render. Consumed by the sibling analytics CLI:
#   plugins/statusline-tools/scripts/gateway-telemetry-analytics-from-statusline-jsonl-log.py
# which emits time-windowed uptime %, type-code distribution, state-machine
# transition counts, and pre-warning event timelines.
#
# Schema (v1) — 20 fields, verbose snake_case names:
#   schema_version                                          (int, monotonic)
#   wall_clock_unix_seconds                                 (int, epoch seconds)
#   gateway_gateway_legacy_binary_gate_status              ∈ {healthy, degraded, parse-error, unreachable}
#   gateway_pool_schedulable_active_accounts_count         (int)
#   gateway_pool_rotation_working_set_size                 (int, denom = schedulable + errors)
#   gateway_pool_error_accounts_count                      (int)
#   gateway_pool_resilience_state_machine_label            ∈ {healthy, degraded, partial-outage, total-outage, unknown}
#   gateway_canary_consecutive_failures                    (int)
#   gateway_canary_classification_four_state               ∈ {healthy, since-start-failure, transient, recent-degradation, unproven, no-health-signal, unknown}
#     (the name says "four_state" for wire compatibility with the L4 aggregator;
#      the vocabulary grew when gateway's zero-token access-log health landed.
#      'unproven' = no recent request carried evidence; 'no-health-signal' =
#      gateway exposed neither the new nor the legacy health block.)
#   gateway_canary_failure_type_code                       (official HTTP status string verbatim, e.g. "401", "0"; "" when none — letter-code taxonomy retired 2026-06-11, schema v2)
#   gateway_canary_failure_duration_humanized              (str, e.g. "3d", "47m", "")
#   gateway_canary_real_traffic_damper_engaged             (bool)
#   gateway_unified_state_name_for_render                  ∈ {healthy, since-boot, flapping, partial-outage, outage, unproven, no-health-signal, unknown}
#   gateway_local_client_version             (semver str, e.g. "1.93.0")
#   gateway_minimum_supported_wrapper_version_floor        (semver str, e.g. "1.2.0")
#   gateway_wrapper_skew_present                           (bool, wrapper < floor)
#   gateway_wrapper_at_floor_pre_warn                      (bool, wrapper == floor)
#   gateway_pin_scope_active                               ∈ {"", session, repo, device}
#   gateway_pin_mode_active                                ∈ {"", soft, strict}
#   gateway_bearer_mode_routing_active                     (bool)
#
# Safety: all string fields are constrained to ASCII-safe enums (parser output)
# or semver shapes; none can contain quote/backslash characters, so direct
# string interpolation into the JSON is safe and avoids a jq dependency. Match
# the existing terse-echo pattern used at line ~83 for statusline.jsonl.
#
# Failure mode: every write redirects errors to /dev/null. If the log file
# can't be written (disk full, perms), we silently continue — never block the
# statusline render on telemetry persistence.

# Log path is overridable so an operator migrating from an older, differently
# named log can keep appending to their existing history instead of starting a
# second file alongside it.
gateway_state_jsonl_log_absolute_path="${STATUSLINE_GATEWAY_STATE_LOG:-${HOME}/.claude/gateway-state.jsonl}"

gateway_wrapper_skew_present_boolean_serialized="false"
gateway_wrapper_at_floor_pre_warn_boolean_serialized="false"
if [ -n "$wrapper_version" ]; then
    if version_lt "$wrapper_version" "$GATEWAY_MIN_WRAPPER_VERSION"; then
        gateway_wrapper_skew_present_boolean_serialized="true"
    elif [ "$wrapper_version" = "$GATEWAY_MIN_WRAPPER_VERSION" ]; then
        gateway_wrapper_at_floor_pre_warn_boolean_serialized="true"
    fi
fi
gateway_bearer_mode_routing_active_boolean_serialized="false"
[ -n "$gateway_bearer_account" ] && gateway_bearer_mode_routing_active_boolean_serialized="true"
gateway_real_traffic_damper_engaged_boolean_serialized="false"
[ "$real_traffic_recent" -eq 1 ] && gateway_real_traffic_damper_engaged_boolean_serialized="true"

gateway_state_jsonl_log_record_for_this_render="{\
\"schema_version\":3,\
\"wall_clock_unix_seconds\":$(date +%s),\
\"gateway_gateway_legacy_binary_gate_status\":\"${gateway_status}\",\
\"gateway_pool_schedulable_active_accounts_count\":${pool_schedulable},\
\"gateway_pool_rotation_working_set_size\":${pool_rotation_size},\
\"gateway_pool_error_accounts_count\":${pool_errors},\
\"gateway_pool_resilience_state_machine_label\":\"${pool_resilience_state_machine_label}\",\
\"gateway_canary_consecutive_failures\":${canary_failures},\
\"gateway_canary_classification_four_state\":\"${canary_class}\",\
\"gateway_canary_failure_type_code\":\"${canary_last_observed_http_status_for_render}\",\
\"gateway_canary_failure_duration_humanized\":\"${canary_failure_duration_humanized_short_form}\",\
\"gateway_canary_real_traffic_damper_engaged\":${gateway_real_traffic_damper_engaged_boolean_serialized},\
\"gateway_unified_state_name_for_render\":\"${unified_state_name_for_render_label}\",\
\"gateway_local_client_version\":\"${wrapper_version}\",\
\"gateway_minimum_supported_wrapper_version_floor\":\"${GATEWAY_MIN_WRAPPER_VERSION}\",\
\"gateway_wrapper_skew_present\":${gateway_wrapper_skew_present_boolean_serialized},\
\"gateway_wrapper_at_floor_pre_warn\":${gateway_wrapper_at_floor_pre_warn_boolean_serialized},\
\"gateway_pin_scope_active\":\"${pin_scope}\",\
\"gateway_pin_mode_active\":\"${pin_mode}\",\
\"gateway_bearer_mode_routing_active\":${gateway_bearer_mode_routing_active_boolean_serialized}\
}"
# Size-bounded with cascade rotation, matching the 10MB/.1/.2/.3 convention
# gateway's own structured access log already uses.
#
# WHY: this appends ~889 bytes on EVERY statusline render, and nothing ever
# pruned it. Measured 2026-08-02 on the operator's Mac: 257,728,077 bytes across
# 289,604 lines — a quarter of a gigabyte of telemetry about a gateway, growing
# without limit. The L4 pusher `tail -n 1`s this file every 30s, so the cost is
# not only disk: every read walks a file that only ever gets longer.
#
# The check is a single stat() per render, which is nothing next to the work the
# statusline already does. Rotation keeps 3 generations (~40MB ceiling).
#
# Failure stays silent by design — the statusline must never block or error on
# telemetry persistence — but note that "silent" here is bounded to the ROTATION,
# not to the whole file's existence: a rotation that cannot happen degrades to
# "keep appending", which is the pre-existing behaviour, not a new failure.
#
# GATED (2026-09-04): the append below used to run unconditionally, so an
# installer of this marketplace with no gateway configured still grew a
# ~889-byte-per-render log of nothing but "unreachable" records in their home
# directory, forever. Telemetry about a gateway you do not have is not
# telemetry, it is litter. It now writes only when a gateway is configured.
if [ "$GATEWAY_CONFIGURED" -eq 1 ]; then
    gateway_state_jsonl_log_max_bytes_before_rotation=10485760
    gateway_state_jsonl_log_current_size_bytes=$(
        stat -f %z "${gateway_state_jsonl_log_absolute_path}" 2>/dev/null || echo 0
    )
    if [ "${gateway_state_jsonl_log_current_size_bytes}" -gt "${gateway_state_jsonl_log_max_bytes_before_rotation}" ] 2>/dev/null; then
        rm -f "${gateway_state_jsonl_log_absolute_path}.3" 2>/dev/null
        mv -f "${gateway_state_jsonl_log_absolute_path}.2" "${gateway_state_jsonl_log_absolute_path}.3" 2>/dev/null
        mv -f "${gateway_state_jsonl_log_absolute_path}.1" "${gateway_state_jsonl_log_absolute_path}.2" 2>/dev/null
        mv -f "${gateway_state_jsonl_log_absolute_path}" "${gateway_state_jsonl_log_absolute_path}.1" 2>/dev/null
    fi
    echo "${gateway_state_jsonl_log_record_for_this_render}" >> "${gateway_state_jsonl_log_absolute_path}" 2>/dev/null
fi

gateway_inline=""
if [ "$gateway_status" = "healthy" ] || [ "$gateway_status" = "degraded" ]; then
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
            severity_glyph_with_optional_type_code_and_duration="${BRIGHT_BLACK}✗${canary_last_observed_http_status_for_render} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${BRIGHT_BLACK}since-boot${RESET}"
            ;;
        unproven)
            # Calm on purpose. No recent request carried forward-path evidence
            # (idle fleet or fresh gateway restart), so there is nothing to
            # alarm about — and nothing to certify either. Do NOT move this into
            # the red fallback: that would page the operator for being idle.
            severity_glyph_with_optional_type_code_and_duration="${BRIGHT_BLACK}·${RESET}"
            unified_state_name_visible_label_token=" ${BRIGHT_BLACK}unproven${RESET}"
            ;;
        no-health-signal)
            # gateway answered but exposed neither health block. That is a
            # contract break in the binary, not a fleet outage — yellow, and
            # named so the operator knows to look at the deployed version.
            severity_glyph_with_optional_type_code_and_duration="${YELLOW}?${RESET}"
            unified_state_name_visible_label_token=" ${YELLOW}no-health-signal${RESET}"
            ;;
        flapping)
            severity_glyph_with_optional_type_code_and_duration="${YELLOW}⚠${canary_last_observed_http_status_for_render} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${YELLOW}flapping${RESET}"
            ;;
        partial-outage)
            severity_glyph_with_optional_type_code_and_duration="${YELLOW}⚠${canary_last_observed_http_status_for_render} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${YELLOW}partial-outage${RESET}"
            ;;
        outage)
            severity_glyph_with_optional_type_code_and_duration="${RED}✗${canary_last_observed_http_status_for_render} ${canary_failure_duration_humanized_short_form}${RESET}"
            unified_state_name_visible_label_token=" ${RED}outage${RESET}"
            ;;
        *)
            # unknown / parse-error / sentinel — fail-safe to red alarm so we
            # don't hide a real problem behind missing data.
            severity_glyph_with_optional_type_code_and_duration="${RED}?${RESET}"
            unified_state_name_visible_label_token=" ${RED}${unified_state_name_for_render_label:-unknown}${RESET}"
            ;;
    esac

    gateway_inline=" ${BRIGHT_BLACK}${STATUSLINE_GATEWAY_LABEL:-gateway}${RESET} ${pool_part} ${severity_glyph_with_optional_type_code_and_duration}${unified_state_name_visible_label_token}"
elif [ -n "$gateway_status" ] && [ "$gateway_status" != "unreachable" ]; then
    # Non-empty $gateway_status but not the expected healthy/degraded values —
    # surface the raw state token in red so the operator sees the literal
    # parse-error word (or any future sentinel we introduce).
    gateway_inline=" ${BRIGHT_BLACK}${STATUSLINE_GATEWAY_LABEL:-gateway}${RESET} ${RED}${gateway_status}${RESET}"
else
    gateway_inline=" ${BRIGHT_BLACK}${STATUSLINE_GATEWAY_LABEL:-gateway}${RESET} ${RED}unreachable${RESET}"
fi

# Wrapper version: bare semver normally; YELLOW with "<floor" suffix when
# below floor (skew, will be 403'd); YELLOW with "=floor" suffix when exactly
# at floor (pre-warn — next gateway floor-bump will reject us). The "=floor"
# pre-warning is the canonical "at-threshold" SRE pattern (one perturbation
# away from breach). Label "wrapper" deliberately dropped — three-dot semver
# is visually unique against the other tokens.
wrapper_part=""
if [ -n "$wrapper_version" ]; then
    if version_lt "$wrapper_version" "$GATEWAY_MIN_WRAPPER_VERSION"; then
        wrapper_part=" ${YELLOW}${wrapper_version}<${GATEWAY_MIN_WRAPPER_VERSION}${RESET}"
    elif [ "$wrapper_version" = "$GATEWAY_MIN_WRAPPER_VERSION" ]; then
        wrapper_part=" ${YELLOW}${wrapper_version}=${GATEWAY_MIN_WRAPPER_VERSION}${RESET}"
    else
        wrapper_part=" ${BRIGHT_BLACK}${wrapper_version}${RESET}"
    fi
fi

# Decide whether to render the gateway segment at all. Three independent
# triggers, any one is sufficient:
#   - gateway responded (cached or fresh) → status != "unreachable"
#   (pin-badge render-trigger retired 2026-05-13; placeholder removed 2026-06-10)
#   - bearer-mode detection found a bearer account → gateway_bearer_account set
# Otherwise (no integration installed), print the bare datetime line.
# gateway_bearer_account itself produces no visible badge — only the render
# decision uses it; presence of the gateway block already implies bearer-
# mode routing for the operator.
if [ "$GATEWAY_CONFIGURED" -eq 1 ] \
   && { [ "$gateway_status" != "unreachable" ] || [ -n "$gateway_bearer_account" ]; }; then
    # $gateway_inline starts with its own leading space (the "gateway"
    # anchor), so concatenating directly after the BRIGHT_BLACK "|" separator
    # produces exactly one space of padding between them.
    echo -e "${datetime_display} ${BRIGHT_BLACK}|${RESET}${gateway_inline}${wrapper_part}"
else
    echo -e "${datetime_display}"
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
