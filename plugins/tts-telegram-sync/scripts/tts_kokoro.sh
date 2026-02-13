#!/bin/bash
# Kokoro TTS — clipboard to speech with auto language detection
# Uses local Kokoro via Apple Silicon MPS, falls back to macOS say
#
# Usage:
#   bin/tts_kokoro.sh                   # local Kokoro, fallback to say
#   TTS_MODE=local bin/tts_kokoro.sh    # force local only (no fallback)
#   TTS_MODE=fallback bin/tts_kokoro.sh # force macOS say
#
# Debug: tail -f /tmp/kokoro-tts.log

set -euo pipefail

# Ensure standard tools are in PATH (BTT runs with minimal environment)
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:$PATH"

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/tts-common.sh
source "${SCRIPT_DIR}/lib/tts-common.sh"

# --- Configuration ---
KOKORO_VENV="${KOKORO_VENV:-${HOME}/.local/share/kokoro/.venv}"
KOKORO_SCRIPT="${KOKORO_SCRIPT:-${HOME}/.local/share/kokoro/tts_generate.py}"
KOKORO_PYTHON="${KOKORO_VENV}/bin/python"
FALLBACK_SCRIPT="${HOME}/.local/bin/tts_read_clipboard_wrapper.sh"
SPEED="${TTS_SPEED:-1.25}"
TMP_WAV="/tmp/kokoro-tts-$$.wav"
LOG="/tmp/kokoro-tts.log"

cleanup() { rm -f "$TMP_WAV" "$TTS_LOCK"; }
trap cleanup EXIT

# --- Kill any existing TTS playback ---
kill_existing_tts
tts_log "Killed existing TTS playback, cleared lock, cleaned stale WAVs"

# --- Read clipboard ---
TEXT="$(pbpaste 2>/dev/null)"
if [[ -z "$TEXT" ]]; then
    tts_log "Clipboard is empty"
    exit 1
fi
tts_log "Clipboard: ${#TEXT} chars"

# --- Signal that TTS is processing ---
play_tts_signal

# --- Detect language ---
detect_language "$TEXT"
tts_log "Language: $LANG_CODE (voice: $VOICE)"

# --- Fallback function ---
fallback_to_say() {
    tts_log "Falling back to macOS say: $1"
    if [[ -x "$FALLBACK_SCRIPT" ]]; then
        exec "$FALLBACK_SCRIPT"
    else
        tts_log "Fallback script not found: $FALLBACK_SCRIPT"
        exit 1
    fi
}

# --- Choose mode ---
MODE="${TTS_MODE:-auto}"
tts_log "Mode requested: $MODE"

if [[ "$MODE" == "fallback" ]]; then
    fallback_to_say "forced"
fi

# --- Check local Kokoro availability ---
if [[ ! -x "$KOKORO_PYTHON" ]] || [[ ! -f "$KOKORO_SCRIPT" ]]; then
    if [[ "$MODE" == "local" ]]; then
        tts_log "Local Kokoro not found and mode=local, failing"
        exit 1
    fi
    fallback_to_say "local Kokoro not installed"
fi

tts_log "Using local Kokoro | Voice: $VOICE | Speed: $SPEED"

# --- Acquire TTS lock with heartbeat ---
acquire_tts_lock

# --- Generate and play via local Kokoro (Apple Silicon MPS) ---
# Chunked streaming: Kokoro generates each chunk as a WAV and prints the path.
# We play each WAV as soon as it's ready, so audio starts faster for long text.
# The lock file is held for the entire duration so no other TTS slips in between.
CHUNK_FILES=()
trap cleanup_chunks EXIT

PLAYED=0
while IFS= read -r line; do
    if [[ "$line" == DONE* ]]; then
        gen_ms="${line#DONE }"
        tts_log "All chunks done (${gen_ms}ms total generation)"
        break
    fi
    # Each line is a WAV file path ready for playback
    if [[ -s "$line" ]] && [[ "$(wc -c < "$line")" -gt 100 ]]; then
        CHUNK_FILES+=("$line")
        touch "$TTS_LOCK"
        tts_log "Playing chunk: $line ($(wc -c < "$line") bytes)"
        afplay "$line"
        PLAYED=$((PLAYED + 1))
    fi
done < <("$KOKORO_PYTHON" "$KOKORO_SCRIPT" \
    --text "$TEXT" \
    --voice "$VOICE" \
    --lang "$LANG_CODE" \
    --speed "$SPEED" \
    --output "$TMP_WAV" \
    --chunk 2>>"$LOG")

if [[ "$PLAYED" -eq 0 ]]; then
    fallback_to_say "local Kokoro produced no audio"
else
    tts_log "Done — played $PLAYED chunk(s)"
fi
