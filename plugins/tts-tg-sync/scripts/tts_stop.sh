#!/bin/bash
# Stop TTS playback immediately — assigned to ⌃ ESC via BetterTouchTool.
# Kills afplay (audio) and tells the companion to cancel pipeline (subtitles).
set -euo pipefail
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Kill audio immediately (don't wait for HTTP round-trip)
killall -9 afplay 2>/dev/null || true

# Tell companion to cancel pipeline (hides subtitles, drains queue)
curl -sf --max-time 3 -X POST "http://[::1]:8780/tts/stop" >/dev/null 2>&1 || true

echo "[$(date '+%H:%M:%S')] TTS stopped (⌃ ESC)" >> /tmp/kokoro-tts.log
