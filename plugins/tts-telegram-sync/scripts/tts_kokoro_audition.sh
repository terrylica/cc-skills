#!/bin/bash
# Kokoro voice audition — plays a long passage with each top voice
# Each voice announces its name before reading the passage
# Uses local Kokoro via Apple Silicon MPS
set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
# shellcheck source=lib/tts-common.sh
source "${SCRIPT_DIR}/lib/tts-common.sh"

KOKORO_VENV="${KOKORO_VENV:-${HOME}/.local/share/kokoro/.venv}"
KOKORO_SCRIPT="${KOKORO_SCRIPT:-${HOME}/.local/share/kokoro/tts_generate.py}"
KOKORO_PYTHON="${KOKORO_VENV}/bin/python"
TMP_WAV="/tmp/kokoro-audition-$$.wav"

# Kill existing playback and acquire lock with heartbeat
kill_existing_tts
acquire_tts_lock

trap 'release_tts_lock; rm -f "$TMP_WAV"' EXIT

if [[ ! -x "$KOKORO_PYTHON" ]] || [[ ! -f "$KOKORO_SCRIPT" ]]; then
    echo "ERROR: Local Kokoro not found at $KOKORO_VENV" >&2
    exit 1
fi

# Read from clipboard, fall back to default passage
PASSAGE="$(pbpaste 2>/dev/null)"
if [[ -z "$PASSAGE" ]]; then
    PASSAGE="The afternoon sun cast long shadows across the library floor. She picked up the old leather-bound book and began to read aloud, her voice filling the quiet room. The story spoke of distant lands and forgotten kingdoms, of heroes who dared to dream beyond the walls that confined them. Each page turned was a door opening to another world, and she found herself lost in the beauty of words that had survived centuries."
fi

# Top voices by quality grade (A, A-, B-, C+, plus best males)
declare -a VOICES=(
    "af_heart:Heart:A"
    "af_bella:Bella:A-"
    "af_nicole:Nicole:B-"
    "af_aoede:Aoede:C+"
    "af_kore:Kore:C+"
    "af_sarah:Sarah:C+"
    "am_adam:Adam:F+"
    "am_michael:Michael:unrated"
    "am_echo:Echo:D"
    "am_puck:Puck:unrated"
)

tts() {
    local voice="$1" text="$2"
    local played=0
    while IFS= read -r line; do
        if [[ "$line" == DONE* ]]; then
            break
        fi
        if [[ -s "$line" ]] && [[ "$(wc -c < "$line")" -gt 100 ]]; then
            touch "$TTS_LOCK"
            afplay "$line"
            rm -f "$line"
            played=$((played + 1))
        fi
    done < <("$KOKORO_PYTHON" "$KOKORO_SCRIPT" \
        --text "$text" \
        --voice "$voice" \
        --lang "en-us" \
        --speed 1.0 \
        --output "$TMP_WAV" \
        --chunk 2>/dev/null)
    if [[ "$played" -eq 0 ]]; then
        echo "  FAILED" >&2
    fi
}

echo "=== Kokoro Voice Audition (Local MPS) ==="
echo "Playing ${#VOICES[@]} voices with a long passage"
echo ""

for entry in "${VOICES[@]}"; do
    IFS=: read -r voice_id name grade <<< "$entry"
    echo ">>> $name ($voice_id) — Grade: $grade"

    # Read the passage
    tts "$voice_id" "$PASSAGE"

    echo ""
    sleep 1
done

echo "=== Audition complete ==="
