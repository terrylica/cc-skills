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
LOCK_FILE="/tmp/tts_read_clipboard.lock"

debug_log() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    fi
}

# Acquire lock to prevent simultaneous executions
acquire_lock() {
    local lock_pid

    # Check if lock file exists
    if [[ -f "$LOCK_FILE" ]]; then
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        if [[ -n "$lock_pid" ]]; then
            # Check if this is actually our script (not a recycled PID)
            if kill -0 "$lock_pid" 2>/dev/null; then
                # Verify it's actually a tts script, not a recycled PID
                local proc_cmd
                proc_cmd=$(ps -o command= -p "$lock_pid" 2>/dev/null || echo "")
                if [[ "$proc_cmd" == *"tts_read_clipboard"* ]]; then
                    debug_log "Killing previous instance (PID: $lock_pid)"
                    # Use TERM first to allow cleanup, then KILL as fallback
                    kill -TERM "$lock_pid" 2>/dev/null || true
                    sleep 0.3
                    kill -KILL "$lock_pid" 2>/dev/null || true
                else
                    debug_log "Stale lock: PID $lock_pid is not a TTS process, removing"
                fi
            else
                debug_log "Stale lock: PID $lock_pid no longer running, removing"
            fi
        fi

        # Remove stale lock
        rm -f "$LOCK_FILE"
    fi

    # Kill any remaining say processes
    kill_existing_tts

    # Create lock file with current PID
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

# Cleanup function: kill all child processes before exiting
cleanup_on_exit() {
    debug_log "Cleanup triggered (PID: $$)"

    # Kill all children of this script
    pkill -KILL -P $$ 2>/dev/null || true

    # Kill any orphaned TTS processes
    pkill -KILL say 2>/dev/null || true
    pkill -KILL afplay 2>/dev/null || true
    pkill -f "tts_supertonic_speak" 2>/dev/null || true

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

# Kill all existing TTS processes
kill_existing_tts() {
    debug_log "Killing existing TTS..."

    pkill -KILL say 2>/dev/null || true
    pkill -KILL afplay 2>/dev/null || true
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
        debug_log "Supertonic not available, using macOS say"
    fi

    # Strip markdown from full content
    clipboard_content=$(strip_markdown "$clipboard_content")

    if [[ "$USE_SUPERTONIC" == "true" ]]; then
        # Supertonic path: synthesize entire text in one call (handles chunking internally)
        local TTS_SPEED
        TTS_SPEED=$(wpm_to_supertonic_speed "$SPEECH_RATE")
        export TTS_SPEED
        debug_log "Using Supertonic M3 (speed: $TTS_SPEED)"

        echo "Speaking via Supertonic M3 (speed: $TTS_SPEED)"
        if ! printf '%s' "$clipboard_content" | uv run --quiet --python 3.13 --with supertonic python3 "$SUPERTONIC_SPEAK" 2>/dev/null; then
            local exit_code=$?
            debug_log "Supertonic failed (exit code: $exit_code), falling back to say"
            echo "Supertonic failed, falling back to macOS say"
            # Fall through to say
            USE_SUPERTONIC=false
        fi
    fi

    if [[ "$USE_SUPERTONIC" == "false" ]]; then
        # macOS say fallback: process paragraph by paragraph
        local paragraph_num=0
        local total_paragraphs
        total_paragraphs=$(echo "$clipboard_content" | wc -l | tr -d ' ')
        debug_log "Total paragraphs: $total_paragraphs"

        while IFS= read -r paragraph || [[ -n "$paragraph" ]]; do
            debug_log "Read paragraph (length: ${#paragraph})"

            # Skip empty paragraphs
            if [[ -z "$paragraph" ]]; then
                debug_log "Skipping empty paragraph"
                continue
            fi

            paragraph_num=$((paragraph_num + 1))
            debug_log "Processing paragraph $paragraph_num"

            # Skip if empty text
            if [[ -z "$paragraph" ]]; then
                debug_log "Skipping empty cleaned text"
                continue
            fi

            # Speak the paragraph
            echo "Speaking paragraph $paragraph_num"
            debug_log "Calling say command..."
            debug_log "Text to speak (first 100 chars): ${paragraph:0:100}"

            # Direct piping works fine once Unicode is properly normalized
            if ! printf '%s' "$paragraph" | say -r "$SPEECH_RATE" 2>&1; then
                exit_code=$?
                debug_log "say command failed with exit code: $exit_code"
                # Exit code 143 = SIGTERM (interrupted)
                if [[ $exit_code -eq 143 ]]; then
                    echo "Speech interrupted at paragraph $paragraph_num"
                    debug_log "Speech interrupted"
                    exit 0
                fi
            else
                debug_log "say command completed successfully"
            fi

            # Add pause between paragraphs
            if [[ $paragraph_num -lt $total_paragraphs ]] && (( $(echo "$PAUSE_DURATION > 0" | bc -l 2>/dev/null || echo 0) )); then
                sleep "$PAUSE_DURATION"
            fi
        done <<< "$clipboard_content"
    fi

    echo "TTS completed successfully"
    debug_log "=== TTS Script Completed ==="
}

# Run main function
main "$@"
