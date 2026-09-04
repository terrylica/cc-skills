#!/bin/bash
# install.sh — Deploy ssh-tunnel-companion (launchd + sleepwatcher + SwiftBar)
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (Host $TUNNEL_HOST, ServerAliveInterval=30)
#   Layer 2: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Layer 3: sleepwatcher      — ~/.wakeup (kills stale SSH on wake for instant reconnect)
#   Control: SwiftBar          — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh
#   Source:  THIS repo         — <repo>/plugins/ssh-tunnel-companion/

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.terryli.ssh-tunnel-companion"

# Target host comes from config, never from a baked-in default — see
# libexec/ssh-tunnel-companion-runner for the rationale.
SSH_TUNNEL_CONFIG="${SSH_TUNNEL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ssh-tunnel-companion/config}"
if [ -f "$SSH_TUNNEL_CONFIG" ]; then
  # shellcheck source=/dev/null
  . "$SSH_TUNNEL_CONFIG"
fi
TUNNEL_HOST="${SSH_TUNNEL_COMPANION_HOST:-${TUNNEL_HOST:-}}"
if [ -z "$TUNNEL_HOST" ]; then
  echo "ERROR: no tunnel host configured." >&2
  echo "  Create $SSH_TUNNEL_CONFIG containing:" >&2
  echo "      TUNNEL_HOST=<ssh-alias-or-fqdn>" >&2
  echo "  The host must also be a reachable entry in your ~/.ssh/config." >&2
  exit 78
fi
PLIST_SRC="${REPO_DIR}/launchd/${LABEL}.plist"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SWIFTBAR_SRC="${REPO_DIR}/swiftbar/ssh-tunnel.5s.sh"
SWIFTBAR_DST="$HOME/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh"
WAKEUP_SRC="${REPO_DIR}/scripts/wakeup.sh"

echo "=== ssh-tunnel-companion install ==="
echo "Stack: pure SSH + launchd KeepAlive + sleepwatcher (no autossh)"
echo ""

# Step 1: Verify SSH config
echo "[1/6] Checking SSH keepalive for $TUNNEL_HOST (Layer 1)..."
if grep -A15 "Host $TUNNEL_HOST" ~/.ssh/config 2>/dev/null | grep -q ServerAliveInterval; then
  echo "  ~/.ssh/config: ServerAliveInterval configured"
else
  echo "  WARNING: ServerAliveInterval not found for Host $TUNNEL_HOST"
  echo "  Layer 1 degraded — reconnect will be slower without keepalive"
fi

# Step 2: Install launchd plist (Layer 2)
echo ""
echo "[2/6] Installing launchd plist (Layer 2)..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
# The tracked plist carries __RUNNER_PATH__ rather than an absolute path, so the
# public repo does not ship one maintainer's home directory (and so this actually
# works for anyone who checks the repo out somewhere else). Substitute it here.
RUNNER_PATH="${REPO_DIR}/libexec/ssh-tunnel-companion-runner"
if [ ! -x "$RUNNER_PATH" ]; then
  echo "ERROR: runner not found or not executable: $RUNNER_PATH" >&2
  exit 1
fi
sed "s|__RUNNER_PATH__|${RUNNER_PATH}|" "$PLIST_SRC" > "$PLIST_DST"
if grep -q '__RUNNER_PATH__' "$PLIST_DST"; then
  echo "ERROR: placeholder substitution failed — refusing to install a broken plist." >&2
  rm -f "$PLIST_DST"
  exit 1
fi
if ! plutil -lint "$PLIST_DST" >/dev/null; then
  echo "ERROR: generated plist is not valid — refusing to install." >&2
  rm -f "$PLIST_DST"
  exit 1
fi
echo "  Installed to $PLIST_DST (Program: $RUNNER_PATH)"

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
      echo "# Source: <repo>/plugins/ssh-tunnel-companion/scripts/wakeup.sh"
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
    echo "  localhost:18123 → $TUNNEL_HOST:8123 (ClickHouse)"
    echo "  localhost:18081 → $TUNNEL_HOST:8081 (SSE sidecar — crypto ODB)"
    echo "  localhost:18082 → $TUNNEL_HOST:8082 (fxview-sidecar — forex ticks)"
    echo "  localhost:5900  → $TUNNEL_HOST:5900 (VNC — MT5/WINE)"
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
echo "  Check: Is $TUNNEL_HOST reachable? Run: tailscale ping $TUNNEL_HOST"
exit 1
