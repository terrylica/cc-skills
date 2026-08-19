#!/bin/bash
# TTS Speed Set — the ONE place that applies a speech rate to BOTH engines.
#
# Usage: tts_speed_set.sh <wpm>
#
# WHY THIS EXISTS
# ---------------
# ⌥+ / ⌥- / ⌥0 used to write only the BetterTouchTool persistent variable
# TTS_SPEECH_RATE. That variable is read by the Supertonic path
# (tts_read_clipboard.sh), but the PRIMARY path — Kokoro via
# claude-tts-companion — never saw it: the companion takes its speed from its
# own persisted settings store, and POST /tts/speak carries no speed field
# (TTSSpeakRequest in HTTPControlServer.swift declares only `text`).
#
# Net effect: after the hotkey was repointed at the resident Kokoro server, the
# speed keys silently did nothing. This script closes that gap by ALSO pushing
# the rate to the companion's real knob, POST /settings/tts {"speed": <Double>},
# which the companion persists and TTSQueue reads on every synthesis
# (TTSQueue.swift:301 `let speed = Float(ttsSettings.speed)`).
#
# UNITS
# -----
# BTT stores words-per-minute. Kokoro wants a multiplier where 1.0 is the
# model's natural tempo (KOKORO_DEFAULT_SPEED=1.0 in the launchd plist, and
# TTSSettings.default.speed = 1.0). So:
#
#     multiplier = wpm / 220
#
# 220 WPM is the documented default rate, so ⌥0 (reset to 220) lands exactly on
# Kokoro's own default of 1.0. The multiplier is clamped to [0.5, 3.0] because
# the model degrades outside that range.
#
# No speed is sent per-request: a persisted setting is the right model here,
# since the rate is a standing user preference, not a property of one utterance.

set -euo pipefail

# BTT runs these from an XPC service with PATH=/usr/bin:/bin:/usr/sbin:/sbin.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"
COMPANION="http://[::1]:8780"
LOG="/tmp/kokoro-tts.log"

log() { printf '[%s] speed: %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"; }

WPM="${1:-}"
if ! [[ "$WPM" =~ ^[0-9]+$ ]]; then
    log "ERROR: non-numeric wpm '${WPM}'"
    exit 2
fi

# Clamp WPM to the range tts_read_clipboard.sh's validate_speech_rate accepts,
# so the two engines never disagree about what is in bounds.
((WPM < 90)) && WPM=90
((WPM > 500)) && WPM=500

# --- 1. Supertonic path: the BTT persistent variable -------------------------
if [[ -x "$BTTCLI" ]]; then
    "$BTTCLI" set_persistent_string_variable variable_name=TTS_SPEECH_RATE to="$WPM" >/dev/null 2>&1 \
        || log "WARN: bttcli could not persist TTS_SPEECH_RATE"
fi

# --- 2. Kokoro path: the companion's persisted speed setting -----------------
# awk, not bc: bc is not present under BTT's minimal PATH on a stock macOS.
MULT=""
MULT=$(awk -v w="$WPM" 'BEGIN {
    m = w / 220
    if (m < 0.5) m = 0.5
    if (m > 3.0) m = 3.0
    printf "%.2f", m
}')

if curl -sf --max-time 3 -X POST "${COMPANION}/settings/tts" \
        -H 'Content-Type: application/json' \
        -d "{\"speed\":${MULT}}" >/dev/null 2>&1; then
    log "set ${WPM} wpm (kokoro speed ${MULT})"
else
    # Not fatal: the BTT variable is still updated, so the Supertonic fallback
    # honours the new rate and Kokoro picks it up next time the companion is up.
    log "set ${WPM} wpm (companion unreachable — kokoro speed NOT applied)"
fi

# Audible confirmation, matching the previous behaviour of these keys.
afplay /System/Library/Sounds/Tink.aiff >/dev/null 2>&1 &

exit 0
