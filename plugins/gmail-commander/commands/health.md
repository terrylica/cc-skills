---
name: health
description: Gmail Commander health check across all subsystems.
model: haiku
---

# Gmail Commander Health Check

Run diagnostics across all subsystems.

## Check All Subsystems

```bash
echo "=== 1. Gmail CLI Binary ==="
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail" 2>/dev/null && echo "OK" || echo "MISSING — run: cd scripts/gmail-cli && bun install && bun run build"

echo ""
echo "=== 2. Environment Variables ==="
echo "GMAIL_OP_UUID: ${GMAIL_OP_UUID:+SET}"
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+SET}"
echo "TELEGRAM_CHAT_ID: ${TELEGRAM_CHAT_ID:-NOT_SET}"
echo "HAIKU_MODEL: ${HAIKU_MODEL:-NOT_SET}"
echo "OP_SERVICE_ACCOUNT_TOKEN: ${OP_SERVICE_ACCOUNT_TOKEN:+SET}"

echo ""
echo "=== 3. 1Password CLI ==="
op account list 2>&1 | head -3

echo ""
echo "=== 4. Bot Process ==="
if [ -f /tmp/gmail-commander-bot.pid ]; then
  PID=$(cat /tmp/gmail-commander-bot.pid)
  if kill -0 "$PID" 2>/dev/null; then
    echo "Running (PID $PID)"
  else
    echo "STALE PID file (process $PID not found)"
  fi
else
  echo "Not running"
fi

echo ""
echo "=== 5. Digest Process ==="
if [ -f /tmp/gmail-digest.pid ]; then
  PID=$(cat /tmp/gmail-digest.pid)
  if kill -0 "$PID" 2>/dev/null; then
    echo "Running (PID $PID)"
  else
    echo "Not running (stale PID)"
  fi
else
  echo "Not running"
fi

echo ""
echo "=== 6. launchd Jobs ==="
launchctl list | grep gmail-commander 2>/dev/null || echo "No launchd jobs registered"

echo ""
echo "=== 7. Circuit Breakers ==="
for f in /tmp/gmail-digest-circuit.json /tmp/gmail-commander-agent-circuit.json; do
  if [ -f "$f" ]; then
    echo "$(basename $f): $(cat $f)"
  else
    echo "$(basename $f): CLOSED (healthy)"
  fi
done

echo ""
echo "=== 8. Recent Audit Logs ==="
AUDIT_DIR="${AUDIT_DIR:-$HOME/own/amonic/logs/audit}"
if [ -d "$AUDIT_DIR" ]; then
  LATEST=$(ls -t "$AUDIT_DIR"/*.ndjson 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    echo "Latest: $(basename $LATEST)"
    tail -5 "$LATEST" | while read -r line; do
      echo "  $line" | cut -c1-120
    done
  else
    echo "No audit logs found"
  fi
else
  echo "Audit directory not found: $AUDIT_DIR"
fi
```
