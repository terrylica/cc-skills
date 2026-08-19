#!/bin/bash
# Stop TTS playback immediately — assigned to ⌃ ESC via BetterTouchTool.
# Kills afplay, all queued tts_kokoro.sh instances, and companion pipeline.
set -euo pipefail
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Kill audio immediately (don't wait for HTTP round-trip)
killall -9 afplay 2>/dev/null || true

# Kill ALL queued tts_kokoro.sh instances (they're waiting on shlock)
pkill -9 -f "tts_kokoro.sh" 2>/dev/null || true

# The Supertonic path is a SEPARATE process tree with a SEPARATE lock, so it
# needs stopping explicitly. Historically ⌃ESC missed it entirely: this script
# only cleared /tmp/tts_kokoro.lock, while tts_read_clipboard.sh holds
# /tmp/kokoro-tts.lock — a confusingly similar but different filename. A
# Supertonic run therefore kept speaking, and its stale lock then made the next
# press wait out the 30s staleness timer.
# Patterns are specific script basenames, never a bare word, so they cannot
# match unrelated processes.
pkill -9 -f "tts_read_clipboard" 2>/dev/null || true
pkill -9 -f "tts_supertonic_speak" 2>/dev/null || true

# Remove stale locks so the next invocation isn't blocked (both engines)
rm -f /tmp/tts_kokoro.lock /tmp/kokoro-tts.lock

# Tell companion to cancel pipeline (hides subtitles, drains server queue)
curl -sf --max-time 3 -X POST "http://[::1]:8780/tts/stop" >/dev/null 2>&1 || true

echo "[$(date '+%H:%M:%S')] TTS stopped (⌃ ESC)" >> /tmp/kokoro-tts.log
