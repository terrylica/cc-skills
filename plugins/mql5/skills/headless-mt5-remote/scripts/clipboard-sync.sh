#!/bin/bash
# Clipboard sync: macOS → remote Linux via SSH side-channel
# Bypasses broken VNC clipboard protocol (libvncserver 0.9.14 bug)
# Usage: ./clipboard-sync.sh [hostname] [display]
#   defaults: hostname=gpu-host, display=:99

HOST="${1:-gpu-host}"
DISPLAY_NUM="${2:-:99}"
LAST=""

while true; do
    CURRENT=$(pbpaste 2>/dev/null)
    if [ "$CURRENT" != "$LAST" ] && [ -n "$CURRENT" ]; then
        echo -n "$CURRENT" | ssh -o ConnectTimeout=2 "$HOST" \
            "DISPLAY=$DISPLAY_NUM xclip -selection clipboard" 2>/dev/null
        LAST="$CURRENT"
    fi
    sleep 0.5
done
