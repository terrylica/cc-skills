#!/bin/bash
# install.sh — Deploy ssh-tunnel-companion (launchd + sleepwatcher + SwiftBar)
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (Host bigblack, ServerAliveInterval=30)
#   Layer 2: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Layer 3: sleepwatcher      — ~/.wakeup (kills stale SSH on wake for instant reconnect)
#   Control: SwiftBar          — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh
#   Source:  THIS repo         — ~/eon/cc-skills/plugins/ssh-tunnel-companion/

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.terryli.ssh-tunnel-companion"
PLIST_SRC="${REPO_DIR}/launchd/${LABEL}.plist"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SWIFTBAR_SRC="${REPO_DIR}/swiftbar/ssh-tunnel.5s.sh"
SWIFTBAR_DST="$HOME/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh"
WAKEUP_SRC="${REPO_DIR}/scripts/wakeup.sh"

echo "=== ssh-tunnel-companion install ==="
echo "Stack: pure SSH + launchd KeepAlive + sleepwatcher (no autossh)"
echo ""

# Step 1: Verify SSH config
echo "[1/6] Checking SSH keepalive for bigblack (Layer 1)..."
if grep -A15 'Host bigblack' ~/.ssh/config 2>/dev/null | grep -q ServerAliveInterval; then
  echo "  ~/.ssh/config: ServerAliveInterval configured"
else
  echo "  WARNING: ServerAliveInterval not found for Host bigblack"
  echo "  Layer 1 degraded — reconnect will be slower without keepalive"
fi

# Step 2: Install launchd plist (Layer 2)
echo ""
echo "[2/6] Installing launchd plist (Layer 2)..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
cp "$PLIST_SRC" "$PLIST_DST"
echo "  Copied to $PLIST_DST"

# Step 3: Install wakeup hook (Layer 3)
echo ""
echo "[3/6] Installing sleepwatcher wakeup hook (Layer 3)..."
if [ -f "$HOME/.wakeup" ]; then
  # Check if our hook is already in the file
  if grep -q "ssh-tunnel-companion" "$HOME/.wakeup" 2>/dev/null; then
    echo "  ~/.wakeup: already contains tunnel hook"
  else
    echo "  ~/.wakeup: exists — appending tunnel hook"
    {
      echo ""
      echo "# --- ssh-tunnel-companion: kill stale tunnel on wake (Layer 3) ---"
      echo "# Source: ~/eon/cc-skills/plugins/ssh-tunnel-companion/scripts/wakeup.sh"
      grep -v '^#!/bin/bash' "$WAKEUP_SRC" | grep -v '^#'
      echo "# --- end ssh-tunnel-companion ---"
    } >> "$HOME/.wakeup"
  fi
else
  echo "  Creating ~/.wakeup"
  cp "$WAKEUP_SRC" "$HOME/.wakeup"
fi
chmod +x "$HOME/.wakeup"

# Step 4: Ensure sleepwatcher is running
echo ""
echo "[4/6] Checking sleepwatcher daemon..."
if pgrep -x sleepwatcher >/dev/null 2>&1; then
  echo "  sleepwatcher: running"
elif command -v brew >/dev/null 2>&1; then
  echo "  Starting sleepwatcher via brew services..."
  brew services start sleepwatcher 2>/dev/null
  echo "  sleepwatcher: started"
else
  echo "  WARNING: sleepwatcher not running. Install: brew install sleepwatcher"
  echo "  Then: brew services start sleepwatcher"
fi

# Step 5: Install SwiftBar plugin (symlink so edits auto-propagate)
echo ""
echo "[5/6] Installing SwiftBar plugin..."
if [ -d "$HOME/Library/Application Support/SwiftBar/Plugins" ]; then
  rm -f "$SWIFTBAR_DST"
  chmod +x "$SWIFTBAR_SRC"
  ln -s "$SWIFTBAR_SRC" "$SWIFTBAR_DST"
  echo "  Symlinked → $SWIFTBAR_DST"
else
  echo "  WARNING: SwiftBar plugins directory not found. Skipping."
fi

# Step 6: Load and verify
echo ""
echo "[6/6] Loading launchd agent..."
launchctl load "$PLIST_DST"

for i in $(seq 1 5); do
  sleep 2
  if lsof -ti:18123 >/dev/null 2>&1; then
    echo "  Tunnel UP"
    echo ""
    echo "=== Install complete ==="
    echo "  localhost:18123 → bigblack:8123 (ClickHouse)"
    echo "  localhost:18081 → bigblack:8081 (SSE sidecar)"
    echo ""
    echo "  SwiftBar: look for the tunnel indicator in your menu bar"
    echo "  Logs: /tmp/ssh-tunnel-companion.log"
    echo "  Status: make status (from repo root)"
    exit 0
  fi
  echo "  Waiting for tunnel... attempt $i/5"
done

echo ""
echo "WARNING: Tunnel did not come up within 10s"
echo "  Check: /tmp/ssh-tunnel-companion.log"
echo "  Check: Is bigblack reachable? Run: make zt-probe"
exit 1
