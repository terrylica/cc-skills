#!/bin/bash

# <bitbar.title>SSH Tunnel Companion</bitbar.title>
# <bitbar.version>v2.0</bitbar.version>
# <bitbar.author>terrylica</bitbar.author>
# <bitbar.author.github>terrylica</bitbar.author.github>
# <bitbar.desc>3-layer SSH tunnel resilience: SSH keepalive + launchd KeepAlive + sleepwatcher. No autossh.</bitbar.desc>
# <bitbar.dependencies>curl</bitbar.dependencies>
# <bitbar.abouturl>https://github.com/terrylica/cc-skills</bitbar.abouturl>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>

# ssh-tunnel.5s.sh — SwiftBar plugin for ssh-tunnel-companion
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (Host bigblack)
#   Layer 2: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Layer 3: sleepwatcher      — ~/.wakeup (kills stale SSH on wake)
#   Control: SwiftBar (THIS)   — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh
#   Source:  ~/eon/cc-skills/plugins/ssh-tunnel-companion/

# --- Configuration ---
LABEL="com.terryli.ssh-tunnel-companion"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
TUNNEL_PORT=18123
LOG="/tmp/ssh-tunnel-companion.log"
ZT_PROBE="$HOME/eon/cc-skills/plugins/ssh-tunnel-companion/scripts/zt-probe.sh"

# --- Actions ---
if [ "$1" = "start" ]; then
    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" 2>/dev/null
    exit 0
fi
if [ "$1" = "stop" ]; then
    launchctl unload "$PLIST" 2>/dev/null
    PID=$(lsof -ti:${TUNNEL_PORT} 2>/dev/null)
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    exit 0
fi
if [ "$1" = "restart" ]; then
    # Kill current → launchd restarts automatically
    PID=$(lsof -ti:${TUNNEL_PORT} 2>/dev/null)
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    exit 0
fi
if [ "$1" = "zt-probe" ]; then
    [ -x "$ZT_PROBE" ] && "$ZT_PROBE"
    exit 0
fi

# --- Status checks ---
TUNNEL_PID=$(lsof -ti:${TUNNEL_PORT} 2>/dev/null)
LAUNCHD_LOADED=$(launchctl list 2>/dev/null | grep -c "$LABEL")

# ClickHouse connectivity (only if tunnel port is open)
CH_OK=false
if [ -n "$TUNNEL_PID" ]; then
    CH_RESULT=$(/usr/bin/curl -sf --connect-timeout 2 --max-time 3 "http://localhost:${TUNNEL_PORT}" --data "SELECT 'ok' FORMAT TabSeparated" 2>/dev/null)
    [ "$CH_RESULT" = "ok" ] && CH_OK=true
fi

# --- Menu bar icon ---
if [ -n "$TUNNEL_PID" ] && $CH_OK; then
    echo ":bolt.horizontal.circle.fill: | symbolColor=#34C759 sfsize=14"
elif [ -n "$TUNNEL_PID" ]; then
    echo ":bolt.horizontal.circle.fill: | symbolColor=#FF9500 sfsize=14"
else
    echo ":bolt.horizontal.circle.fill: | symbolColor=#FF3B30 sfsize=14"
fi

echo "---"

# --- Status section ---
if [ -n "$TUNNEL_PID" ] && $CH_OK; then
    echo "ClickHouse: connected | sfimage=checkmark.circle color=green"
    echo "Tunnel: UP (pid ${TUNNEL_PID}) | sfimage=lock.shield color=green"
elif [ -n "$TUNNEL_PID" ]; then
    echo "Tunnel: UP but CH unreachable | sfimage=exclamationmark.triangle color=orange"
else
    echo "Tunnel: DOWN | sfimage=xmark.circle color=red"
fi

echo "---"

# --- Layer health ---
echo "Resilience Layers | sfimage=square.stack.3d.up"

# Layer 1: SSH keepalive
SSH_KEEPALIVE=$(grep -A15 'Host bigblack' ~/.ssh/config 2>/dev/null | grep -c ServerAliveInterval)
if [ "$SSH_KEEPALIVE" -gt 0 ]; then
    echo "-- L1 SSH Keepalive: configured | sfimage=checkmark.circle.fill color=green"
else
    echo "-- L1 SSH Keepalive: MISSING | sfimage=xmark.circle.fill color=red"
fi

# Layer 2: launchd
if [ "$LAUNCHD_LOADED" -gt 0 ]; then
    echo "-- L2 launchd: loaded | sfimage=checkmark.circle.fill color=green"
else
    echo "-- L2 launchd: not loaded | sfimage=xmark.circle.fill color=red"
fi

# Layer 3: sleepwatcher
SLEEPWATCHER_RUNNING=$(pgrep -x sleepwatcher 2>/dev/null)
WAKEUP_EXISTS=$([ -x "$HOME/.wakeup" ] && echo 1 || echo 0)
if [ -n "$SLEEPWATCHER_RUNNING" ] && [ "$WAKEUP_EXISTS" = "1" ]; then
    echo "-- L3 sleepwatcher: active | sfimage=checkmark.circle.fill color=green"
elif [ "$WAKEUP_EXISTS" = "1" ]; then
    echo "-- L3 sleepwatcher: script OK, daemon not running | sfimage=exclamationmark.triangle.fill color=orange"
else
    echo "-- L3 sleepwatcher: not configured | sfimage=xmark.circle.fill color=red"
fi

echo "---"

# --- Ports ---
echo "Ports | sfimage=network"
echo "-- :18123 → bigblack:8123 (ClickHouse)"
echo "-- :18081 → bigblack:8081 (SSE sidecar)"

echo "---"

# --- Actions ---
if [ -n "$TUNNEL_PID" ]; then
    echo "Restart Tunnel | sfimage=arrow.clockwise bash='$0' param1=restart terminal=false refresh=true"
    echo "Stop Tunnel | sfimage=stop.circle bash='$0' param1=stop terminal=false refresh=true"
else
    echo "Start Tunnel | sfimage=play.circle bash='$0' param1=start terminal=false refresh=true"
fi
echo "ZeroTier Probe | sfimage=antenna.radiowaves.left.and.right bash='$0' param1=zt-probe terminal=true"

echo "---"

# --- Diagnostics ---
echo "View Log | sfimage=doc.text bash=/usr/bin/open param1=-a param2=Console param3=${LOG} terminal=false"
echo "Log: ${LOG} | size=10 color=gray"
echo "Plist: ${PLIST} | size=10 color=gray"
echo "Repo: ~/eon/cc-skills/plugins/ssh-tunnel-companion | size=10 color=gray"
