#!/bin/bash
# TTS Speed Reset — back to the documented default of 220 WPM, which maps to
# Kokoro speed 1.0 (the model's natural tempo). Applies to BOTH engines.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

SELF="$0"
if RESOLVED=$(readlink -f "$0" 2>/dev/null); then SELF="$RESOLVED"; fi
SCRIPT_DIR=$(cd "$(dirname "$SELF")" && pwd)

exec "$SCRIPT_DIR/tts_speed_set.sh" 220
