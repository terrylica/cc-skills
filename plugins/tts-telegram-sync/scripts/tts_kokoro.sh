#!/bin/bash
# Kokoro TTS — clipboard to speech via centralized Kokoro HTTP server.
# All TTS sources (BTT shortcut, Telegram bot) share one server queue.
#
# Flow: clipboard → language detect → POST /v1/audio/speak (server preprocesses)
# Fallback: macOS say (if server is down)
#
# Usage:
#   tts_kokoro.sh                       # speak clipboard via server
#   TTS_MODE=fallback tts_kokoro.sh     # force macOS say
#
# Debug: tail -f /tmp/kokoro-tts.log

set -euo pipefail

# Ensure standard tools are in PATH (BTT runs with minimal environment)
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Source shared library (for tts_log, detect_language, play_tts_signal)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
# shellcheck source=lib/tts-common.sh
source "${SCRIPT_DIR}/lib/tts-common.sh"

# --- Configuration ---
KOKORO_SERVER="${KOKORO_SERVER_URL:-http://127.0.0.1:8779}"
SPEED="${TTS_SPEED:-1.25}"
LOG="/tmp/kokoro-tts.log"

# --- Forced fallback mode ---
if [[ "${TTS_MODE:-auto}" == "fallback" ]]; then
    tts_log "Mode: forced fallback to macOS say"
    TEXT="$(pbpaste 2>/dev/null)"
    [[ -z "$TEXT" ]] && exit 0
    say "$TEXT"
    exit 0
fi

# --- Read clipboard ---
TEXT="$(pbpaste 2>/dev/null)"
if [[ -z "$TEXT" ]]; then
    tts_log "Clipboard is empty"
    exit 1
fi
tts_log "Clipboard: ${#TEXT} chars"

# --- Signal sound (fire-and-forget) ---
play_tts_signal

# --- Detect language ---
detect_language "$TEXT"
tts_log "Language: $LANG_CODE (voice: $VOICE)"

# --- Speak via centralized Kokoro server ---
# Server handles preprocessing (sanitisation, markdown strip, reflow, chunking).
# Uses python3 (always available on macOS) for safe JSON encoding + HTTP POST.
tts_log "Sending to server: ${#TEXT} chars (voice=$VOICE, lang=$LANG_CODE, speed=$SPEED)"

if printf '%s' "$TEXT" | python3 -c "
import json, sys, urllib.request, urllib.error
text = sys.stdin.read().strip()
if not text:
    sys.exit(0)
server = '${KOKORO_SERVER}'
voice = '${VOICE}'
lang = '${LANG_CODE}'
speed = ${SPEED}

# Interrupt current playback first
try:
    req = urllib.request.Request(f'{server}/v1/audio/stop', method='POST',
                                 headers={'Content-Length': '0'})
    urllib.request.urlopen(req, timeout=2)
except Exception:
    pass

# Queue new text — server preprocesses (markdown, reflow, sanitise)
data = json.dumps({
    'input': text, 'voice': voice, 'language': lang,
    'speed': speed, 'preprocess': True,
}).encode()
req = urllib.request.Request(f'{server}/v1/audio/speak', data=data,
                              headers={'Content-Type': 'application/json'})
try:
    resp = urllib.request.urlopen(req, timeout=5)
    result = json.loads(resp.read())
    print(json.dumps(result))
except urllib.error.URLError as e:
    print(f'Server unavailable: {e}', file=sys.stderr)
    sys.exit(1)
" 2>>"$LOG"; then
    tts_log "Queued on server successfully"
else
    # Server unavailable — fallback to macOS say
    tts_log "Server unavailable — falling back to macOS say"
    say "$TEXT" &
fi
