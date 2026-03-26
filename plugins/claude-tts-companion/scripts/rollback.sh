#!/usr/bin/env bash
set -euo pipefail

# Rollback: stop claude-tts-companion and re-enable the old telegram-bot + kokoro-tts-server services.

UID_NUM="$(id -u)"
START_TIME="$(date +%s)"

echo "=== Rolling back to old services ==="
echo ""

# Stop unified service
echo "[1/3] Stopping claude-tts-companion..."
launchctl bootout "gui/$UID_NUM" "$HOME/Library/LaunchAgents/com.terryli.claude-tts-companion.plist" 2>/dev/null || true
sleep 2
echo "       Stopped."

# Re-enable old services
echo "[2/3] Re-enabling old services..."
launchctl bootstrap "gui/$UID_NUM" "$HOME/Library/LaunchAgents/com.terryli.telegram-bot.plist"
launchctl bootstrap "gui/$UID_NUM" "$HOME/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist"
echo "       Old services started."

# Verify
echo "[3/3] Verifying old services..."
echo ""
echo "--- telegram-bot ---"
launchctl print "gui/$UID_NUM/com.terryli.telegram-bot" | head -3 || echo "WARNING: telegram-bot not running"
echo ""
echo "--- kokoro-tts-server ---"
launchctl print "gui/$UID_NUM/com.terryli.kokoro-tts-server" | head -3 || echo "WARNING: kokoro-tts-server not running"
echo ""

END_TIME="$(date +%s)"
ELAPSED=$(( END_TIME - START_TIME ))
echo "=== Rollback completed in ${ELAPSED} seconds ==="
echo ""
echo "Old services restored. Unified binary still at /usr/local/bin/claude-tts-companion."
echo "To remove the unified binary: rm /usr/local/bin/claude-tts-companion"
