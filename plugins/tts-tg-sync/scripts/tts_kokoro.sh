#!/bin/bash
# Kokoro TTS — clipboard to speech via claude-tts-companion Swift service.
# Uses the unified HTTP control API on localhost:8780.
#
# Flow: clipboard → awk unwrap/clean → single POST /tts/speak
#
# The companion handles paragraph splitting and pipelined playback internally:
# first paragraph plays immediately while subsequent ones synthesize in parallel.
#
# Usage:
#   tts_kokoro.sh              # speak clipboard
#   tts_kokoro.sh "some text"  # speak argument text
#   echo "text" | tts_kokoro.sh -  # speak from stdin
#
# Debug: check service health with curl http://127.0.0.1:8780/health

set -euo pipefail

# Ensure standard tools are in PATH (BTT runs with minimal environment)
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# --- Configuration ---
TTS_SERVICE="http://[::1]:8780"
LOG="/tmp/kokoro-tts.log"
CURL_TIMEOUT=300

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

# --- Get text from args, stdin, or clipboard ---
if [[ $# -gt 0 && "$1" == "-" ]]; then
    TEXT="$(cat)"
elif [[ $# -gt 0 ]]; then
    TEXT="$*"
else
    TEXT="$(pbpaste 2>/dev/null)"
fi

if [[ -z "$TEXT" ]]; then
    log "No text provided (args, stdin, or clipboard empty)"
    exit 1
fi

# --- Queue: wait for previous invocation to finish ---
# Consecutive invocations wait their turn. The previous one plays to
# completion. Only manual stop (⌃ESC / SwiftBar) preempts.
LOCKFILE="/tmp/tts_kokoro.lock"
while ! shlock -f "$LOCKFILE" -p $$; do
    sleep 0.3
done
trap 'rm -f "$LOCKFILE"' EXIT

# --- Check companion is running ---
# Only check the companion (port 8780). The companion handles Kokoro server
# recovery internally (awaitServerReady + retry). Don't gate on Kokoro
# directly — it briefly drops after stop operations and auto-recovers.
if ! curl -s --max-time 2 "${TTS_SERVICE}/health" >/dev/null 2>&1; then
    log "ERROR: claude-tts-companion not responding on ${TTS_SERVICE}"
    echo "Error: TTS service not running. Start with: launchctl kickstart gui/$(id -u)/com.terryli.claude-tts-companion" >&2
    exit 1
fi

# --- Unwrap, clean, and send as single request ---
# Awk: Unwrap terminal soft-wraps into clean paragraphs.
#   - Lines starting with ·•*- or N. or # start a new paragraph
#   - Everything else is a continuation (joined with space)
#   - Bullet markers are stripped
#   - Paragraphs joined with \n\n for the companion to split internally

CLEAN_TEXT=$(printf '%s\n' "$TEXT" | awk '
{
    gsub(/^[[:space:]]+/, "")
    if ($0 == "") {
        if (buf != "") { paras[n++] = buf; buf = "" }
        next
    }
    if (match($0, /^[·•*\-] /) || match($0, /^[0-9]+[\.\)] /) || match($0, /^#+ /)) {
        if (buf != "") paras[n++] = buf
        sub(/^[·•*\-] +/, "")
        sub(/^#+ */, "")
        buf = $0
    } else {
        if (buf != "") buf = buf " " $0
        else buf = $0
    }
}
END {
    if (buf != "") paras[n++] = buf
    for (i = 0; i < n; i++) {
        p = paras[i]
        while (match(p, /\*\*[^*]+\*\*/)) {
            pre = substr(p, 1, RSTART-1)
            mid = substr(p, RSTART+2, RLENGTH-4)
            post = substr(p, RSTART+RLENGTH)
            p = pre mid post
        }
        while (match(p, /\*[^*]+\*/)) {
            pre = substr(p, 1, RSTART-1)
            mid = substr(p, RSTART+1, RLENGTH-2)
            post = substr(p, RSTART+RLENGTH)
            p = pre mid post
        }
        gsub(/ \+ /, " plus ", p)
        gsub(/ & /, " and ", p)
        gsub(/  +/, " ", p)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
        paras[i] = p
    }
    # Join all paragraphs with double newline (companion splits internally)
    first = 1
    for (i = 0; i < n; i++) {
        if (paras[i] == "") continue
        if (!first) printf "\n\n"
        printf "%s", paras[i]
        first = 0
    }
}
')

if [[ -z "$CLEAN_TEXT" ]]; then
    log "No text after cleaning"
    exit 0
fi

log "Sending ${#CLEAN_TEXT} chars (single request, pipelined playback)"

JSON_PAYLOAD=$(jq -nc --arg t "$CLEAN_TEXT" '{"text":$t}')

RESPONSE=$(curl -s -w "\n%{http_code}" --max-time "$CURL_TIMEOUT" \
    -X POST "${TTS_SERVICE}/tts/speak" \
    -H "Content-Type: application/json" \
    -H "X-TTS-Priority: user-initiated" \
    -d "$JSON_PAYLOAD" \
    2>>"$LOG")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    log "TTS complete (HTTP ${HTTP_CODE})"
else
    log "ERROR: TTS failed (HTTP ${HTTP_CODE}): ${BODY}"
    echo "Error: TTS synthesis failed (HTTP ${HTTP_CODE})" >&2
    exit 1
fi
