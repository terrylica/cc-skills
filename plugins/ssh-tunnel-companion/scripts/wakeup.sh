#!/bin/bash
# wakeup.sh — sleepwatcher hook: kill stale SSH tunnel on macOS wake
#
# Installed to ~/.wakeup by `make install`. sleepwatcher runs this on every
# wake-from-sleep. Kills the stale SSH tunnel process so launchd (Layer 2)
# restarts it immediately with a fresh connection — instant recovery instead
# of waiting ~90s for SSH keepalive timeout to detect the dead connection.
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (Host bigblack)
#   Layer 2: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Layer 3: sleepwatcher (THIS runs on wake) — ~/.wakeup → this script
#   Control: SwiftBar          — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh
#   Source:  ~/eon/cc-skills/plugins/ssh-tunnel-companion/

# Kill the SSH tunnel process on port 18123
# launchd KeepAlive=true will restart it within ~10s (ThrottleInterval)
PID=$(lsof -ti:18123 2>/dev/null)
if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [wakeup] killed stale tunnel (pid $PID) — launchd will restart" >> /tmp/ssh-tunnel-companion.log
fi
