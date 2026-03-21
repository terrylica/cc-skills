#!/bin/bash
# TTS Read Clipboard - Bash Version
# Reads clipboard content with markdown stripping and speaks it
# Optimized for BetterTouchTool compatibility
#
# Usage:
#   ./tts_read_clipboard.sh              # Uses defaults
#   SPEECH_RATE=250 ./tts_read_clipboard.sh  # Custom rate
#
# BTT Integration:
#   Action: Execute Shell Script
#   Script: /path/to/tts_read_clipboard.sh

set -euo pipefail

# Debug logging (set DEBUG=1 to enable)
DEBUG="${DEBUG:-0}"
LOG_FILE="/tmp/tts_debug.log"
LOCK_FILE="/tmp/kokoro-tts.lock"

debug_log() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    fi
}

# Acquire lock — respects the shared /tmp/kokoro-tts.lock protocol.
# Waits for existing holder (bot or shell script) to finish before acquiring.
# Only force-kills a previous tts_read_clipboard instance (BTT double-tap).
acquire_lock() {
    local lock_pid lock_age max_wait=60 waited=0 stale_threshold=30

    # Kill previous tts_read_clipboard instance if BTT double-tapped
    if [[ -f "$LOCK_FILE" ]]; then
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            local proc_cmd
            proc_cmd=$(ps -o command= -p "$lock_pid" 2>/dev/null || echo "")
            if [[ "$proc_cmd" == *"tts_read_clipboard"* ]]; then
                debug_log "Killing previous tts_read_clipboard instance (PID: $lock_pid)"
                kill -TERM "$lock_pid" 2>/dev/null || true
                sleep 0.3
                kill -KILL "$lock_pid" 2>/dev/null || true
                rm -f "$LOCK_FILE"
            fi
        fi
    fi

    # Wait for existing lock holder (bot, kokoro shell script) to finish
    while [[ -f "$LOCK_FILE" ]]; do
        if [[ $waited -ge $max_wait ]]; then
            debug_log "Lock wait exceeded ${max_wait}s — force-breaking"
            rm -f "$LOCK_FILE"
            break
        fi

        # Check lock mtime for staleness (mirrors bot's waitForTtsLock)
        if command -v stat >/dev/null 2>&1; then
            local mtime now
            mtime=$(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
            now=$(date +%s)
            lock_age=$((now - mtime))
            if [[ $lock_age -gt $stale_threshold ]]; then
                # Stale lock — but check if audio is actually playing
                if ! pgrep -x afplay >/dev/null 2>&1; then
                    debug_log "Removing stale lock (${lock_age}s old, no audio playing)"
                    rm -f "$LOCK_FILE"
                    break
                fi
            fi
        fi

        sleep 0.5
        waited=$((waited + 1))
    done

    # Acquire lock with PID
    echo $$ > "$LOCK_FILE"
    debug_log "Lock acquired (PID: $$)"
}

# Release lock on exit
release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$LOCK_FILE"
            debug_log "Lock released (PID: $$)"
        fi
    fi
}

# Cleanup function: kill OUR child processes only (not system-wide afplay/say)
cleanup_on_exit() {
    debug_log "Cleanup triggered (PID: $$)"

    # Kill children of this script only — do NOT pkill afplay/say globally
    # as that would kill the Telegram bot's audio playback
    pkill -KILL -P $$ 2>/dev/null || true

    # Release lock
    release_lock

    debug_log "Cleanup completed"
}

# Ensure cleanup runs on exit
trap cleanup_on_exit EXIT INT TERM

# User configurable settings
SPEECH_RATE="${SPEECH_RATE:-220}"  # Words per minute (90-500)
PAUSE_DURATION="${PAUSE_DURATION:-0.0}"  # Seconds between paragraphs
MAX_CONTENT_LENGTH="${MAX_CONTENT_LENGTH:-100000}"  # ~100KB limit

# Normalize Unicode characters to ASCII for TTS compatibility
# IMPORTANT: iconv + sed is the ONLY approach that works reliably from BTT
# Tried and failed: Perl, Python (shell alias issues), sed character classes
# This hybrid approach handles BTT's non-standard execution environment
normalize_unicode() {
    local text="$1"

    # Try iconv first (works in most environments)
    local result
    result=$(printf '%s' "$text" | iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null)

    # Fallback: sed with explicit hex byte sequences (BTT-compatible)
    # Required when iconv fails or shell environment is restricted
    if [[ -z "$result" ]] || [[ ${#result} -lt 10 ]]; then
        result=$(printf '%s' "$text" | \
            sed -e 's/\xe2\x80\x9c/"/g' \
                -e 's/\xe2\x80\x9d/"/g' \
                -e 's/\xe2\x80\x98/'\''/g' \
                -e 's/\xe2\x80\x99/'\''/g' \
                -e 's/\xe2\x80\x94/--/g' \
                -e 's/\xe2\x80\x93/-/g' \
                -e 's/\xe2\x80\xa6/.../g')
    fi

    printf '%s' "$result"
}

# Strip markdown formatting
strip_markdown() {
    local text="$1"
    # Remove bold/italic, headers, bullet points in one sed call
    printf '%s' "$text" | sed -e 's/\*\*//g' -e 's/\*//g' -e 's/^#\+\s*//g' -e 's/^-\s*//g'
}

# Validate speech rate
validate_speech_rate() {
    local rate="$1"
    if [[ $rate -lt 90 || $rate -gt 500 ]]; then
        echo "220"  # Default fallback
    else
        echo "$rate"
    fi
}

# Convert WPM speech rate to Supertonic speed multiplier
# 220 WPM ≈ speed 1.25 (linear mapping)
wpm_to_supertonic_speed() {
    local wpm="$1"
    python3 -c "print(round($wpm * 1.25 / 220, 2))"
}

# Kill existing tts_read_clipboard processes only (not system-wide audio)
kill_existing_tts() {
    debug_log "Killing existing tts_read_clipboard TTS..."

    # Only kill supertonic spawned by this script path — never global afplay/say
    pkill -f "tts_supertonic_speak" 2>/dev/null || true

    # Clean up temp files
    rm -f /tmp/tts_*.txt /tmp/supertonic-tts.* 2>/dev/null || true
}

# Show notification (for errors)
notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-Basso}"
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

# Main execution
main() {
    debug_log "=== TTS Script Started ==="

    # Acquire lock to prevent race conditions with BTT
    acquire_lock

    # Validate speech rate
    SPEECH_RATE=$(validate_speech_rate "$SPEECH_RATE")
    debug_log "Speech rate: $SPEECH_RATE"

    # Get clipboard content
    local clipboard_content
    clipboard_content=$(pbpaste 2>/dev/null) || {
        debug_log "ERROR: Failed to read clipboard"
        notify "TTS Error" "Failed to read clipboard"
        exit 1
    }

    if [[ -z "$clipboard_content" ]]; then
        debug_log "ERROR: Clipboard is empty"
        notify "TTS Error" "Clipboard is empty"
        exit 1
    fi

    # Normalize Unicode BEFORE any processing
    # This fixes "Input text is not UTF-8 encoded" errors from say command
    debug_log "Original content length: ${#clipboard_content}"
    clipboard_content=$(normalize_unicode "$clipboard_content")
    debug_log "After normalization length: ${#clipboard_content}"

    # Check content length
    local content_length=${#clipboard_content}
    debug_log "Clipboard content length: $content_length"
    debug_log "First 100 chars: ${clipboard_content:0:100}"

    if [[ $content_length -gt $MAX_CONTENT_LENGTH ]]; then
        debug_log "ERROR: Content too large"
        notify "TTS Error" "Content too large: $content_length chars (max $MAX_CONTENT_LENGTH)"
        exit 1
    fi

    echo "Processing clipboard: $content_length characters"

    # Detect Supertonic availability
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
    local SUPERTONIC_SPEAK="$SCRIPT_DIR/tts_supertonic_speak.py"

    local USE_SUPERTONIC=false
    if [[ -f "$SUPERTONIC_SPEAK" ]] && command -v uv >/dev/null 2>&1 && \
       [[ -d "$HOME/.cache/supertonic2/onnx" ]]; then
        USE_SUPERTONIC=true
        debug_log "Supertonic M3 available"
    else
        debug_log "Supertonic not available — Kokoro-only policy, no macOS say fallback"
        notify "TTS Error" "Supertonic not available. Use Kokoro server via tts_kokoro.sh"
        exit 1
    fi

    # Strip markdown from full content
    clipboard_content=$(strip_markdown "$clipboard_content")

    # Supertonic path: synthesize entire text in one call (handles chunking internally)
    local TTS_SPEED
    TTS_SPEED=$(wpm_to_supertonic_speed "$SPEECH_RATE")
    export TTS_SPEED
    debug_log "Using Supertonic M3 (speed: $TTS_SPEED)"

    echo "Speaking via Supertonic M3 (speed: $TTS_SPEED)"
    if ! printf '%s' "$clipboard_content" | uv run --quiet --python 3.13 --with supertonic python3 "$SUPERTONIC_SPEAK" 2>/dev/null; then
        local exit_code=$?
        debug_log "Supertonic failed (exit code: $exit_code) — no fallback (Kokoro-only policy)"
        notify "TTS Error" "Supertonic synthesis failed (exit $exit_code)"
        exit 1
    fi

    echo "TTS completed successfully"
    debug_log "=== TTS Script Completed ==="
}

# Run main function
main "$@"
