#!/bin/bash
# uninstall.sh — Remove ssh-tunnel-companion (launchd + sleepwatcher hook + SwiftBar)
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (NOT removed — shared config)
#   Layer 2: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Layer 3: sleepwatcher      — ~/.wakeup tunnel hook section
#   Control: SwiftBar          — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh

set -e

LABEL="com.terryli.ssh-tunnel-companion"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SWIFTBAR="$HOME/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh"

echo "=== ssh-tunnel-companion uninstall ==="
echo ""

# Step 1: Unload launchd (Layer 2)
echo "[1/4] Unloading launchd agent..."
if launchctl list 2>/dev/null | grep -q "$LABEL"; then
  launchctl unload "$PLIST" 2>/dev/null
  echo "  Agent unloaded"
else
  echo "  Agent not loaded (skipping)"
fi

# Step 2: Remove plist
echo ""
echo "[2/4] Removing launchd plist..."
if [ -f "$PLIST" ]; then
  rm "$PLIST"
  echo "  Removed $PLIST"
else
  echo "  Not found (skipping)"
fi

# Step 3: Clean wakeup hook (Layer 3)
echo ""
echo "[3/4] Removing wakeup hook from ~/.wakeup..."
if [ -f "$HOME/.wakeup" ] && grep -q "ssh-tunnel-companion" "$HOME/.wakeup" 2>/dev/null; then
  # Remove the marked section
  sed -i '' '/# --- ssh-tunnel-companion/,/# --- end ssh-tunnel-companion ---/d' "$HOME/.wakeup" 2>/dev/null
  # If the file is now empty (or only whitespace), remove it
  if [ ! -s "$HOME/.wakeup" ] || ! grep -q '[^[:space:]]' "$HOME/.wakeup" 2>/dev/null; then
    rm "$HOME/.wakeup"
    echo "  Removed ~/.wakeup (was only tunnel hook)"
  else
    echo "  Removed tunnel hook from ~/.wakeup (other hooks preserved)"
  fi
else
  echo "  No tunnel hook found in ~/.wakeup (skipping)"
fi

# Step 4: Remove SwiftBar plugin
echo ""
echo "[4/4] Removing SwiftBar plugin..."
if [ -e "$SWIFTBAR" ]; then
  rm "$SWIFTBAR"
  echo "  Removed $SWIFTBAR"
else
  echo "  Not found (skipping)"
fi

# Kill any orphaned tunnel process
PID=$(lsof -ti:18123 2>/dev/null)
if [ -n "$PID" ]; then
  kill "$PID" 2>/dev/null
  echo ""
  echo "Killed orphaned tunnel process (pid $PID)"
fi

echo ""
echo "=== Uninstall complete ==="
echo "  SSH config (Layer 1) was NOT removed."
echo "  sleepwatcher daemon was NOT stopped (may serve other hooks)."
