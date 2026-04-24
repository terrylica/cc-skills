#!/usr/bin/env bash
# Focused screenshot of the FloatingClock window only.
#
# Reads the saved window frame from NSUserDefaults, converts bottom-left
# origin → top-left origin (what `screencapture -R` wants), adds a small
# pad, and writes a PNG tightly cropped to the panel. Far cleaner for
# multimodal analysis than full-desktop captures.
#
# Usage: capture-clock.sh [output.png]
#   defaults to /tmp/clock-focused.png

set -euo pipefail

OUT="${1:-/tmp/clock-focused.png}"
PAD=16

FRAME=$(defaults read com.terryli.floating-clock FloatingClockWindowFrame)
# Frame string format: "{{x, y}, {w, h}}"
# tr strips braces, awk splits on comma+optional space, then prints 4 numbers.
read -r X Y W H <<EOF
$(printf '%s' "$FRAME" | tr -d '{}' | awk -F',' '{gsub(/ /,""); print $1, $2, $3, $4}')
EOF

SCREEN_H=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' \
    | awk -F, '{print $4}' | tr -d ' ')

TOP_Y=$((SCREEN_H - Y - H - PAD))
CAP_X=$((X - PAD))
CAP_W=$((W + PAD*2))
CAP_H=$((H + PAD*2))

screencapture -R "${CAP_X},${TOP_Y},${CAP_W},${CAP_H}" -o "$OUT"
echo "$OUT"
