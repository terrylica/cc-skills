#!/bin/bash
# Kokoro TTS — clipboard to speech via claude-tts-companion Swift service.
# Uses the unified HTTP control API on localhost:8780.
#
# Flow: clipboard → awk unwrap → progressive chunking → POST /tts/speak
#
# Progressive chunking: sends paragraph 1 first for fast startup (~3s),
# then exponentially larger batches (2, 4, 8...) while earlier ones play.
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

# --- Check service is running ---
if ! curl -s --max-time 2 "${TTS_SERVICE}/health" >/dev/null 2>&1; then
    log "ERROR: claude-tts-companion not responding on ${TTS_SERVICE}"
    echo "Error: TTS service not running. Start with: launchctl kickstart gui/$(id -u)/com.terryli.claude-tts-companion" >&2
    exit 1
fi

# --- Unwrap, clean, and progressively send ---
# Phase 1 (awk): Unwrap terminal soft-wraps into clean paragraphs.
#   - Lines starting with ·•*- or N. or # start a new paragraph
#   - Everything else is a continuation (joined with space)
#   - Bullet markers are stripped
#   - Output: one paragraph per line
#
# Phase 2 (awk): Progressive batching (1, 2, 4, 8... paragraphs per chunk).
#   - NUL-delimited output for bash read -d ''
#   - Paragraphs within a chunk separated by \n\n
#
# Phase 3 (bash): Send each chunk as user-initiated TTS request.

CHUNK_IDX=0
while IFS= read -r -d '' CHUNK; do
    CHUNK_IDX=$((CHUNK_IDX + 1))

    JSON_PAYLOAD=$(jq -nc --arg t "$CHUNK" '{"text":$t}')

    if [[ -z "$JSON_PAYLOAD" || "$JSON_PAYLOAD" == "{}" ]]; then
        log "ERROR: empty payload for chunk ${CHUNK_IDX}"
        continue
    fi

    log "Progressive chunk ${CHUNK_IDX}: ${#CHUNK} chars"

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
done < <(printf '%s\n' "$TEXT" | awk '
# Phase 1: Unwrap terminal soft-wraps into paragraphs.
# Detects structural elements (bullets, numbers, headings) as paragraph starters.
# Joins continuation lines. Strips bullet markers and markdown.
{
    # Strip leading whitespace
    gsub(/^[[:space:]]+/, "")
    # Skip blank lines (they become paragraph breaks via double-newline in input)
    if ($0 == "") {
        if (buf != "") { paras[n++] = buf; buf = "" }
        next
    }
    # Structural element: starts a new paragraph
    if (match($0, /^[·•*\-] /) || match($0, /^[0-9]+[\.\)] /) || match($0, /^#+ /)) {
        if (buf != "") paras[n++] = buf
        # Strip bullet markers (not numbered — those provide spoken structure)
        sub(/^[·•*\-] +/, "")
        sub(/^#+ */, "")
        buf = $0
    } else {
        # Continuation line: join with previous
        if (buf != "") buf = buf " " $0
        else buf = $0
    }
}
END {
    if (buf != "") paras[n++] = buf

    # Clean for TTS: strip markdown bold/italic, emoji, symbol→word
    for (i = 0; i < n; i++) {
        p = paras[i]
        # **bold** → bold
        while (match(p, /\*\*[^*]+\*\*/)) {
            pre = substr(p, 1, RSTART-1)
            mid = substr(p, RSTART+2, RLENGTH-4)
            post = substr(p, RSTART+RLENGTH)
            p = pre mid post
        }
        # *italic* → italic (single star, not **)
        while (match(p, /\*[^*]+\*/)) {
            pre = substr(p, 1, RSTART-1)
            mid = substr(p, RSTART+1, RLENGTH-2)
            post = substr(p, RSTART+RLENGTH)
            p = pre mid post
        }
        # " + " → " plus ", " & " → " and "
        gsub(/ \+ /, " plus ", p)
        gsub(/ & /, " and ", p)
        # Collapse multiple spaces
        gsub(/  +/, " ", p)
        # Trim
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
        if (p != "") paras[i] = p
        else paras[i] = ""
    }

    # Phase 2: Progressive batching (1, 2, 4, 8...)
    idx = 0
    batch = 1
    while (idx < n) {
        end = idx + batch
        if (end > n) end = n
        chunk = ""
        for (j = idx; j < end; j++) {
            if (paras[j] == "") continue
            if (chunk != "") chunk = chunk "\n\n"
            chunk = chunk paras[j]
        }
        if (chunk != "") printf "%s%c", chunk, 0
        idx = end
        batch = batch * 2
    }
}
')

log "TTS complete: ${CHUNK_IDX} chunks played"
