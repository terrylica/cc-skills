#!/bin/bash
# Kokoro TTS — clipboard to speech via claude-tts-companion Swift service.
# Uses the unified HTTP control API on localhost:8780.
#
# Flow: clipboard → POST /tts/speak → Kokoro MLX synthesis → karaoke subtitles + audio
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
# User-initiated blocks until playback completes (synthesis + audio = 20-120s)
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

# --- Unwrap terminal soft-wraps and clean for TTS ---
# Terminal output wraps at column width (80-120 chars), creating single \n
# breaks mid-sentence. The TTS system splits on \n\n for paragraphs, but
# single \n within a paragraph causes words like "but" or "positions" to
# be treated as separate sentences.
#
# Rules:
#   - Blank line (\n\n)          → paragraph break (keep)
#   - Line starting with N.      → numbered list item (new paragraph)
#   - Line starting with -/*/•   → bullet item (new paragraph)
#   - Line starting with #       → heading (new paragraph)
#   - Everything else            → continuation (join with space)
TEXT=$(printf '%s' "$TEXT" | python3 -c '
import sys, re

text = sys.stdin.read()

# Split into paragraphs on blank lines (2+ newlines)
paragraphs = re.split(r"\n{2,}", text)

result = []
for para in paragraphs:
    lines = para.split("\n")
    merged = []
    buf = ""
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        # New structural element: numbered item, bullet, or heading
        if re.match(r"^\d+[\.\)]\s", stripped) or re.match(r"^[-*•]\s", stripped) or re.match(r"^#+\s", stripped):
            if buf:
                merged.append(buf)
                buf = ""
            buf = stripped
        else:
            # Continuation of previous line (soft wrap)
            if buf:
                buf += " " + stripped
            else:
                buf = stripped
    if buf:
        merged.append(buf)
    result.append("\n\n".join(merged))

# Strip markdown bold/italic markers for cleaner TTS
output = "\n\n".join(result)
output = re.sub(r"\*\*(.+?)\*\*", r"\1", output)  # **bold**
output = re.sub(r"\*(.+?)\*", r"\1", output)       # *italic*
output = re.sub(r"^#+\s*", "", output, flags=re.MULTILINE)  # # headings
output = re.sub(r"[⚠️🔴🟢🟡✅❌•]", "", output)  # emoji/bullets
output = re.sub(r"[^\S\n]{2,}", " ", output)  # collapse spaces/tabs but NOT newlines
print(output.strip())
')

log "TTS request: ${#TEXT} chars (after unwrap)"

# --- Check service is running ---
if ! curl -s --max-time 2 "${TTS_SERVICE}/health" >/dev/null 2>&1; then
    log "ERROR: claude-tts-companion not responding on ${TTS_SERVICE}"
    echo "Error: TTS service not running. Start with: launchctl kickstart gui/$(id -u)/com.terryli.claude-tts-companion" >&2
    exit 1
fi

# --- Build JSON payload ---
# Use jq for reliable JSON encoding of arbitrary text (handles unicode,
# newlines, quotes, control chars). Falls back to python3 if jq unavailable.
if command -v jq >/dev/null 2>&1; then
    JSON_PAYLOAD=$(jq -nc --arg t "$TEXT" '{"text":$t}')
elif command -v python3 >/dev/null 2>&1; then
    JSON_PAYLOAD=$(printf '%s' "$TEXT" | python3 -c 'import json,sys; print(json.dumps({"text": sys.stdin.read()}))')
else
    log "ERROR: neither jq nor python3 available for JSON encoding"
    echo "Error: jq or python3 required" >&2
    exit 1
fi

# Validate we got non-empty JSON
if [[ -z "$JSON_PAYLOAD" || "$JSON_PAYLOAD" == "{}" ]]; then
    log "ERROR: JSON encoding produced empty payload"
    exit 1
fi

log "Sending ${#JSON_PAYLOAD} bytes JSON"

# --- Send to TTS service ---
# POST /tts/speak synthesizes text, plays audio, and shows karaoke subtitles.
# X-TTS-Priority: user-initiated blocks until playback completes.
RESPONSE=$(curl -s -w "\n%{http_code}" --max-time "$CURL_TIMEOUT" \
    -X POST "${TTS_SERVICE}/tts/speak" \
    -H "Content-Type: application/json" \
    -H "X-TTS-Priority: user-initiated" \
    -d "$JSON_PAYLOAD" \
    2>>"$LOG")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    log "TTS dispatched successfully (HTTP ${HTTP_CODE})"
else
    log "ERROR: TTS failed (HTTP ${HTTP_CODE}): ${BODY}"
    echo "Error: TTS synthesis failed (HTTP ${HTTP_CODE})" >&2
    exit 1
fi
