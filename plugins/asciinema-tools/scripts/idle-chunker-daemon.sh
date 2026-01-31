#!/usr/bin/env bash
# idle-chunker-daemon.sh - Background daemon for asciinema chunking
# Runs via launchd, independent of Claude Code CLI
#
# This daemon:
# - Monitors ~/.asciinema/active/*.cast files
# - Pushes chunks to GitHub on idle (using Keychain PAT, not gh auth)
# - Logs to ~/.asciinema/logs/chunker.log
# - Updates ~/.asciinema/health.json
# - Sends Pushover notifications on failure
#
# ADR: /docs/adr/2025-12-26-asciinema-daemon-architecture.md

# NOTE: Intentionally using `set -uo pipefail` WITHOUT `-e` (errexit).
# Daemons should NOT exit on individual command failures - they should
# handle errors gracefully and continue monitoring. Each function has
# explicit error handling for critical operations.
set -uo pipefail

# Configuration
ASCIINEMA_DIR="$HOME/.asciinema"
ACTIVE_DIR="$ASCIINEMA_DIR/active"
LOG_DIR="$ASCIINEMA_DIR/logs"
LOG_FILE="$LOG_DIR/chunker.log"
HEALTH_FILE="$ASCIINEMA_DIR/health.json"
IDLE_THRESHOLD="${IDLE_THRESHOLD:-30}"
ZSTD_LEVEL="${ZSTD_LEVEL:-3}"

# State tracking
CHUNKS_PUSHED=0
LAST_PUSH="never"
declare -A LAST_POS  # Track last position per cast file

# ============================================================================
# LOGGING
# ============================================================================

log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $*" >> "$LOG_FILE"
}

log_rotate() {
    # Rotate log if over 10MB
    if [[ -f "$LOG_FILE" ]]; then
        local size
        if [[ "$(uname)" == "Darwin" ]]; then
            size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        else
            size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        fi

        if (( size > 10485760 )); then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d_%H%M%S).old"
            log "Log rotated"
            # Keep only last 5 rotated logs (SC2012: use find instead of ls)
            find "$LOG_DIR" -maxdepth 1 -name "chunker.log.*.old" -print0 2>/dev/null | \
                xargs -0 ls -t 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
        fi
    fi
}

# ============================================================================
# HEALTH FILE
# ============================================================================

update_health() {
    local status="$1"
    local message="${2:-}"

    cat > "$HEALTH_FILE" <<EOF
{
    "status": "$status",
    "message": "$message",
    "last_update": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "last_push": "$LAST_PUSH",
    "chunks_pushed": $CHUNKS_PUSHED,
    "pid": $$,
    "idle_threshold": $IDLE_THRESHOLD,
    "zstd_level": $ZSTD_LEVEL
}
EOF
}

# ============================================================================
# CREDENTIALS
# ============================================================================

load_credentials() {
    # Load GitHub PAT from macOS Keychain
    GITHUB_PAT=$(security find-generic-password \
        -s "asciinema-github-pat" \
        -a "$USER" \
        -w 2>/dev/null) || {
        log "ERROR: GitHub PAT not found in Keychain. Run /asciinema-tools:daemon-setup"
        update_health "error" "GitHub PAT not found in Keychain"
        return 1
    }

    # Load Pushover credentials (optional)
    PUSHOVER_APP_TOKEN=$(security find-generic-password \
        -s "asciinema-pushover-app" \
        -a "$USER" \
        -w 2>/dev/null) || PUSHOVER_APP_TOKEN=""

    PUSHOVER_USER_KEY=$(security find-generic-password \
        -s "asciinema-pushover-user" \
        -a "$USER" \
        -w 2>/dev/null) || PUSHOVER_USER_KEY=""

    log "Credentials loaded (Pushover: ${PUSHOVER_APP_TOKEN:+enabled}${PUSHOVER_APP_TOKEN:-disabled})"
    return 0
}

# ============================================================================
# NOTIFICATIONS
# ============================================================================

notify_pushover() {
    local title="$1"
    local message="$2"
    local priority="${3:-0}"

    # Skip if Pushover not configured
    [[ -z "$PUSHOVER_APP_TOKEN" || -z "$PUSHOVER_USER_KEY" ]] && return 0

    # Strip any HTML for Pushover (plain text only)
    # shellcheck disable=SC2001  # sed is clearer for HTML stripping
    message=$(echo "$message" | sed 's/<[^>]*>//g')

    local response
    response=$(curl -s \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "title=$title" \
        --form-string "message=$message" \
        --form-string "priority=$priority" \
        --form-string "sound=siren" \
        https://api.pushover.net/1/messages.json 2>&1)

    if echo "$response" | grep -q '"status":1'; then
        log "Pushover notification sent: $title"
    else
        log "Pushover notification failed: $response"
    fi
}

# ============================================================================
# GIT OPERATIONS
# ============================================================================

push_chunk() {
    local cast_file="$1"
    local repo_url="$2"
    local branch="$3"
    local local_repo="$4"
    local chunk_name="$5"

    # Inject PAT into HTTPS URL
    local auth_url
    auth_url="${repo_url/https:\/\//https://${GITHUB_PAT}@}"

    # Push with authentication
    if ! git -C "$local_repo" push "$auth_url" "$branch" 2>>"$LOG_FILE"; then
        log "ERROR: Push failed for $(basename "$cast_file")"
        notify_pushover "asciinema Push Failed" "Failed to push chunk for $(basename "$cast_file") to $repo_url" 1
        update_health "error" "Push failed: $(basename "$cast_file")"
        return 1
    fi

    CHUNKS_PUSHED=$((CHUNKS_PUSHED + 1))
    LAST_PUSH="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "Pushed: $chunk_name to $repo_url ($branch)"
    update_health "ok" "Last push: $chunk_name"
    return 0
}

process_cast_file() {
    local cast_file="$1"

    # Read config for this recording
    local config_file="${cast_file%.cast}.json"
    if [[ ! -f "$config_file" ]]; then
        log "WARN: No config for $(basename "$cast_file"), skipping"
        return 0
    fi

    # Parse config
    local repo_url branch local_repo
    repo_url=$(jq -r '.repo_url // empty' "$config_file" 2>/dev/null)
    branch=$(jq -r '.branch // "asciinema-recordings"' "$config_file" 2>/dev/null)
    local_repo=$(jq -r '.local_repo // empty' "$config_file" 2>/dev/null)

    if [[ -z "$repo_url" || -z "$local_repo" ]]; then
        log "WARN: Invalid config for $(basename "$cast_file")"
        return 0
    fi

    # Get current file stats (cross-platform)
    local mtime size
    if [[ "$(uname)" == "Darwin" ]]; then
        mtime=$(stat -f%m "$cast_file" 2>/dev/null || echo 0)
        size=$(stat -f%z "$cast_file" 2>/dev/null || echo 0)
    else
        mtime=$(stat -c%Y "$cast_file" 2>/dev/null || echo 0)
        size=$(stat -c%s "$cast_file" 2>/dev/null || echo 0)
    fi

    local now idle
    now=$(date +%s)
    idle=$((now - mtime))

    # Get last processed position for this file
    local last_pos="${LAST_POS[$cast_file]:-0}"

    # Check if idle threshold reached and new content available
    if (( idle >= IDLE_THRESHOLD && size > last_pos )); then
        log "Idle detected (${idle}s) for $(basename "$cast_file"), creating chunk..."

        # Ensure chunks directory exists
        mkdir -p "$local_repo/chunks"

        # Extract new content and compress (SC2155: declare and assign separately)
        local chunk_name
        chunk_name="chunk_$(date +%Y%m%d_%H%M%S).cast.zst"
        local chunk_path="$local_repo/chunks/$chunk_name"
        local temp_chunk="$local_repo/chunks/_temp_chunk.cast"

        # Extract bytes since last position
        tail -c +$((last_pos + 1)) "$cast_file" > "$temp_chunk" 2>/dev/null || {
            log "ERROR: Failed to extract chunk from $(basename "$cast_file")"
            return 1
        }

        # Compress
        if ! zstd -"$ZSTD_LEVEL" --rm "$temp_chunk" -o "$chunk_path" 2>/dev/null; then
            log "ERROR: Compression failed for chunk"
            rm -f "$temp_chunk"
            return 1
        fi

        # Commit
        cd "$local_repo" || return 1
        if ! git add chunks/ 2>&1 | tee -a "$LOG_FILE"; then
            log "ERROR: git add failed for chunks/"
        fi
        git commit -m "chunk $(date +%H:%M) - $(basename "$cast_file")" 2>/dev/null || {
            log "WARN: Nothing to commit for $(basename "$cast_file")"
            return 0
        }

        # Push
        if push_chunk "$cast_file" "$repo_url" "$branch" "$local_repo" "$chunk_name"; then
            LAST_POS[$cast_file]=$size
        fi
    fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

cleanup() {
    log "Daemon stopping (signal received)"
    update_health "stopped" "Daemon stopped"
    exit 0
}

main() {
    # Setup signal handlers
    trap cleanup SIGTERM SIGINT SIGHUP

    # Create directories
    mkdir -p "$ACTIVE_DIR" "$LOG_DIR"

    log "=== Daemon started (PID: $$) ==="
    log "Config: idle=${IDLE_THRESHOLD}s, zstd=${ZSTD_LEVEL}, active_dir=$ACTIVE_DIR"

    # Load credentials
    if ! load_credentials; then
        exit 1
    fi

    update_health "starting" "Initializing..."

    # Clear SSH caches on startup (prevent stale ControlMaster)
    rm -f ~/.ssh/control-* 2>/dev/null || true
    ssh -O exit git@github.com 2>/dev/null || true
    ssh -O exit -p 443 git@ssh.github.com 2>/dev/null || true
    log "SSH caches cleared"

    update_health "ok" "Monitoring $ACTIVE_DIR"

    # Main monitoring loop
    while true; do
        # Rotate log if needed
        log_rotate

        # Process each active recording
        for cast_file in "$ACTIVE_DIR"/*.cast; do
            [[ -f "$cast_file" ]] || continue
            process_cast_file "$cast_file"
        done

        # Sleep between checks
        sleep 5
    done
}

main "$@"
