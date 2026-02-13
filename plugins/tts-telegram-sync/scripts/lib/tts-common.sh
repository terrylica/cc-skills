#!/bin/bash
# tts-common.sh — Shared functions for TTS shell scripts
# Source this from TTS scripts: source "$(dirname "$0")/lib/tts-common.sh"

# --- Configuration (can be overridden before sourcing) ---
TTS_LOCK="${TTS_LOCK:-/tmp/kokoro-tts.lock}"
TTS_SIGNAL_SOUND="${TTS_SIGNAL_SOUND:-/System/Library/Sounds/Tink.aiff}"
EN_VOICE="${EN_VOICE:-af_heart}"
ZH_VOICE="${ZH_VOICE:-zf_xiaobei}"

# Heartbeat PID (set by acquire_tts_lock, used by release_tts_lock)
_TTS_HEARTBEAT_PID=""

# --- Logging ---

# Plain text log (legacy, human-readable)
tts_log() {
    local log_file="${LOG:-/tmp/kokoro-tts.log}"
    echo "$(date '+%H:%M:%S') $*" >> "$log_file"
}

# --- TTS Lock Protocol ---
# Shared lock at /tmp/kokoro-tts.lock with heartbeat every 5s.
# Bot's waitForTtsLock() checks mtime freshness + pgrep defense.

acquire_tts_lock() {
    echo "$$" > "$TTS_LOCK"

    # Background heartbeat: touch lock every 5s while parent is alive
    (
        while kill -0 $$ 2>/dev/null; do
            touch "$TTS_LOCK" 2>/dev/null || true
            sleep 5
        done
    ) &
    _TTS_HEARTBEAT_PID=$!
}

release_tts_lock() {
    if [[ -n "$_TTS_HEARTBEAT_PID" ]]; then
        kill "$_TTS_HEARTBEAT_PID" 2>/dev/null || true
        wait "$_TTS_HEARTBEAT_PID" 2>/dev/null || true
        _TTS_HEARTBEAT_PID=""
    fi
    rm -f "$TTS_LOCK"
}

# --- Kill Existing TTS ---
# Stop any active afplay/say, clear lock, clean stale WAVs.

kill_existing_tts() {
    pkill -x afplay 2>/dev/null || true
    pkill -x say 2>/dev/null || true
    rm -f "$TTS_LOCK"
    find /tmp -maxdepth 1 -name "kokoro-tts-*.wav" -mmin +2 -delete 2>/dev/null || true
}

# --- Language Detection ---
# CJK character ratio heuristic. Sets LANG_CODE and VOICE globals.

detect_language() {
    local text="$1"
    local total_chars="${#text}"
    local cjk_chars
    cjk_chars=$(printf '%s' "$text" | perl -CS -ne 'print' | perl -CS -ne '$n += () = /\p{Han}/g; END { print $n // 0 }')

    local ratio=0
    if [[ "$total_chars" -gt 0 ]] && [[ "$cjk_chars" -gt 0 ]]; then
        ratio=$((cjk_chars * 100 / total_chars))
    fi

    # LANG_CODE and VOICE are consumed by the sourcing script
    # shellcheck disable=SC2034
    if [[ "$ratio" -ge 20 ]]; then
        LANG_CODE="cmn"
        VOICE="$ZH_VOICE"
    else
        LANG_CODE="en-us"
        VOICE="$EN_VOICE"
    fi
}

# --- Signal Sound ---
# Play a short system sound to indicate TTS is starting.
# Non-blocking (background), never fails the caller.

play_tts_signal() {
    [[ -n "$TTS_SIGNAL_SOUND" ]] && [[ -f "$TTS_SIGNAL_SOUND" ]] && \
        afplay "$TTS_SIGNAL_SOUND" &>/dev/null &
}

# --- Chunk Cleanup ---
# Remove an array of chunk WAV files + release lock.
# Usage: CHUNK_FILES=(...); cleanup_chunks

cleanup_chunks() {
    release_tts_lock
    for f in "${CHUNK_FILES[@]}"; do
        rm -f "$f"
    done
    rm -f "${TMP_WAV:-}"
}
