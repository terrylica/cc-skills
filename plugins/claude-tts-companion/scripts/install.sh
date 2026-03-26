#!/usr/bin/env bash
set -euo pipefail

# Install claude-tts-companion: build, strip, copy binary, stop old services, bootstrap new service.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY_NAME="claude-tts-companion"
INSTALL_DIR="/usr/local/bin"
PLIST_NAME="com.terryli.claude-tts-companion.plist"
PLIST_SRC="$REPO_DIR/launchd/$PLIST_NAME"
PLIST_DEST="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/.local/state/launchd-logs/claude-tts-companion"
UID_NUM="$(id -u)"

echo "=== Installing claude-tts-companion ==="
echo ""

# Build release binary
echo "[1/7] Building release binary..."
cd "$REPO_DIR"
swift build -c release
echo "       Build complete."

# Strip the binary
echo "[2/7] Stripping binary..."
strip .build/release/"$BINARY_NAME"

# Copy to install directory
echo "[3/7] Installing binary to $INSTALL_DIR/..."
cp .build/release/"$BINARY_NAME" "$INSTALL_DIR/"
ls -lh "$INSTALL_DIR/$BINARY_NAME"

# Create log directory
echo "[4/7] Creating log directory..."
mkdir -p "$LOG_DIR"

# Copy plist to LaunchAgents
echo "[5/7] Installing launchd plist..."
cp "$PLIST_SRC" "$PLIST_DEST/"

# Stop old services (preserve plist files on disk)
echo "[6/7] Stopping old services..."
launchctl bootout "gui/$UID_NUM" "$HOME/Library/LaunchAgents/com.terryli.telegram-bot.plist" 2>/dev/null || true
launchctl bootout "gui/$UID_NUM" "$HOME/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist" 2>/dev/null || true
echo "       Old services stopped (plists preserved on disk)."

# Bootstrap new service
echo "[7/7] Starting claude-tts-companion service..."
launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST/$PLIST_NAME"

# Verify
sleep 2
echo ""
echo "=== Service status ==="
launchctl print "gui/$UID_NUM/com.terryli.claude-tts-companion" | head -5
echo ""

echo "=== Health check ==="
curl -s http://localhost:8780/health | head -1 || echo "(health endpoint not yet responding -- check logs)"
echo ""

echo "=== Installation complete ==="
echo "Logs: $LOG_DIR/"
echo "  stdout: $LOG_DIR/stdout.log"
echo "  stderr: $LOG_DIR/stderr.log"
