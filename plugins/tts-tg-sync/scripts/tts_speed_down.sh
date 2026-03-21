#!/bin/bash
# TTS Speed Down - decreases by 30 WPM
BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"
CURRENT=$("$BTTCLI" get_string_variable variable_name=TTS_SPEECH_RATE 2>/dev/null)
CURRENT=${CURRENT:-220}
NEW=$((CURRENT - 30))
[ $NEW -lt 90 ] && NEW=90
"$BTTCLI" set_persistent_string_variable variable_name=TTS_SPEECH_RATE to=$NEW
afplay /System/Library/Sounds/Tink.aiff &
