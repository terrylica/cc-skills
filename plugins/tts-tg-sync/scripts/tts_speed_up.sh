#!/bin/bash
# TTS Speed Up — +30 WPM. Applies to BOTH engines via tts_speed_set.sh.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"

SELF="$0"
if RESOLVED=$(readlink -f "$0" 2>/dev/null); then SELF="$RESOLVED"; fi
SCRIPT_DIR=$(cd "$(dirname "$SELF")" && pwd)

# bttcli may be missing, fail, or return a non-numeric string — any of those
# must fall back to the documented default rather than break the arithmetic.
CURRENT=""
if [[ -x "$BTTCLI" ]]; then
    CURRENT=$("$BTTCLI" get_string_variable variable_name=TTS_SPEECH_RATE 2>/dev/null) || CURRENT=""
fi
[[ "$CURRENT" =~ ^[0-9]+$ ]] || CURRENT=220

NEW=$((CURRENT + 30))
((NEW > 500)) && NEW=500

exec "$SCRIPT_DIR/tts_speed_set.sh" "$NEW"
