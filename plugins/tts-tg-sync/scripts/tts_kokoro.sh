#!/bin/bash
# Kokoro TTS — clipboard to speech via claude-tts-companion Swift service.
# Uses the unified HTTP control API on localhost:8780.
#
# Flow: clipboard → unwrap → progressive chunking → POST /tts/speak → karaoke subtitles + audio
#
# Progressive chunking: sends paragraph 1 first for fast startup (~3s),
# then exponentially larger batches (2, 4, 8...) while earlier ones play.
# This gives 5-10x faster time-to-first-audio for long text.
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

# --- Check service is running ---
if ! curl -s --max-time 2 "${TTS_SERVICE}/health" >/dev/null 2>&1; then
    log "ERROR: claude-tts-companion not responding on ${TTS_SERVICE}"
    echo "Error: TTS service not running. Start with: launchctl kickstart gui/$(id -u)/com.terryli.claude-tts-companion" >&2
    exit 1
fi

# --- Unwrap terminal soft-wraps, clean for TTS, and send progressive chunks ---
# Outputs NUL-delimited chunks with exponential paragraph batching (1, 2, 4, 8, ...).
# First chunk = 1 paragraph (fast startup), subsequent chunks grow exponentially.
#
# Unwrap rules:
#   - Blank line (\n\n)          → paragraph break (keep)
#   - Line starting with N.      → numbered list item (new paragraph)
#   - Line starting with -/*/•   → bullet item (new paragraph)
#   - Line starting with #       → heading (new paragraph)
#   - Everything else            → continuation (join with space)
CHUNK_IDX=0
while IFS= read -r -d '' CHUNK; do
    CHUNK_IDX=$((CHUNK_IDX + 1))

    # Build JSON payload
    JSON_PAYLOAD=$(jq -nc --arg t "$CHUNK" '{"text":$t}')

    if [[ -z "$JSON_PAYLOAD" || "$JSON_PAYLOAD" == "{}" ]]; then
        log "ERROR: JSON encoding produced empty payload for chunk ${CHUNK_IDX}"
        continue
    fi

    log "Progressive chunk ${CHUNK_IDX}: ${#CHUNK} chars"

    # Send chunk — user-initiated blocks until playback completes.
    # Each chunk plays fully before the next one is sent, so no preemption conflict.
    RESPONSE=$(curl -s -w "\n%{http_code}" --max-time "$CURL_TIMEOUT" \
        -X POST "${TTS_SERVICE}/tts/speak" \
        -H "Content-Type: application/json" \
        -H "X-TTS-Priority: user-initiated" \
        -d "$JSON_PAYLOAD" \
        2>>"$LOG")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
        log "Chunk ${CHUNK_IDX} played (HTTP ${HTTP_CODE})"
    else
        log "ERROR: Chunk ${CHUNK_IDX} failed (HTTP ${HTTP_CODE}): ${BODY}"
        echo "Error: TTS synthesis failed (HTTP ${HTTP_CODE})" >&2
        exit 1
    fi
done < <(printf '%s' "$TEXT" | python3 -c '
import sys, re

text = sys.stdin.read()

# --- Unwrap terminal soft-wraps ---
raw_paragraphs = re.split(r"\n{2,}", text)
paragraphs = []
for para in raw_paragraphs:
    lines = para.split("\n")
    merged = []
    buf = ""
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if re.match(r"^\d+[\.\)]\s", stripped) or re.match(r"^[-*•·]\s", stripped) or re.match(r"^#+\s", stripped):
            if buf:
                merged.append(buf)
                buf = ""
            buf = stripped
        else:
            if buf:
                buf += " " + stripped
            else:
                buf = stripped
    if buf:
        merged.append(buf)
    paragraphs.extend(merged)

# Filter empty
paragraphs = [p.strip() for p in paragraphs if p.strip()]

# --- Clean for TTS ---
def clean(t):
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", t)  # **bold**
    t = re.sub(r"\*(.+?)\*", r"\1", t)       # *italic*
    t = re.sub(r"^#+\s*", "", t, flags=re.MULTILINE)  # # headings
    t = re.sub(r"[⚠️🔴🟢🟡✅❌•]", "", t)  # emoji/bullets
    t = re.sub(r"\s\+\s", " plus ", t)    # " + " → " plus "
    t = re.sub(r"\s&\s", " and ", t)       # " & " → " and "
    t = re.sub(r"[^\S\n]{2,}", " ", t)    # collapse spaces/tabs
    return t.strip()

paragraphs = [clean(p) for p in paragraphs]
paragraphs = [p for p in paragraphs if p]

# --- Progressive batching: 1, 2, 4, 8, ... paragraphs per chunk ---
idx = 0
batch_size = 1
while idx < len(paragraphs):
    end = min(idx + batch_size, len(paragraphs))
    chunk = "\n\n".join(paragraphs[idx:end])
    sys.stdout.write(chunk + "\0")
    idx = end
    batch_size *= 2
')

log "TTS complete: ${CHUNK_IDX} chunks played"
