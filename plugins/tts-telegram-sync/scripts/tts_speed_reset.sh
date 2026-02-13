#!/bin/bash
# TTS Speed Reset - back to 220 WPM
BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"
"$BTTCLI" set_persistent_string_variable variable_name=TTS_SPEECH_RATE to=220
afplay /System/Library/Sounds/Tink.aiff &
