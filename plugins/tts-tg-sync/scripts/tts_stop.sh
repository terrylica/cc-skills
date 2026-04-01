#!/bin/bash
# Stop TTS playback immediately — assigned to ⌃ ESC via BetterTouchTool.
# Kills afplay, all queued tts_kokoro.sh instances, and companion pipeline.
set -euo pipefail
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Kill audio immediately (don't wait for HTTP round-trip)
killall -9 afplay 2>/dev/null || true

# Kill ALL queued tts_kokoro.sh instances (they're waiting on shlock)
pkill -9 -f "tts_kokoro.sh" 2>/dev/null || true

# Remove stale lock so next invocation isn't blocked
rm -f /tmp/tts_kokoro.lock

# Tell companion to cancel pipeline (hides subtitles, drains server queue)
curl -sf --max-time 3 -X POST "http://[::1]:8780/tts/stop" >/dev/null 2>&1 || true

echo "[$(date '+%H:%M:%S')] TTS stopped (⌃ ESC)" >> /tmp/kokoro-tts.log
