#!/bin/bash
# TTS Read Clipboard Wrapper
# Reads SPEECH_RATE from BTT persistent variable, then calls the main script
#
# Usage: This script is called by BTT instead of tts_read_clipboard.sh directly
# It preserves full compatibility with the original script while adding
# configurable speed via BTT variable.

BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"

# Read speech rate from BTT persistent variable (default: 220)
if [[ -x "$BTTCLI" ]]; then
    SPEECH_RATE=$("$BTTCLI" get_string_variable variable_name=TTS_SPEECH_RATE 2>/dev/null)
fi

# Use default if variable is empty or bttcli failed
SPEECH_RATE="${SPEECH_RATE:-220}"

# Resolve symlinks so inter-script references work from ~/.local/bin/
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"

# Export and run the original script
export SPEECH_RATE
exec "$SCRIPT_DIR/tts_read_clipboard.sh" "$@"
