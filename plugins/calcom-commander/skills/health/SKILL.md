---
name: health
description: "Cal.com Commander health check across all subsystems. TRIGGERS - calcom health, calendar bot status, cal.com diagnostics, booking bot check."
model: haiku
---

# Cal.com Commander Health Check

Run diagnostics across all subsystems.

## Check All Subsystems

```bash
echo "=== 1. Cal.com CLI Binary ==="
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli/calcom" 2>/dev/null && echo "OK" || echo "MISSING — run: cd scripts/calcom-cli && bun install && bun run build"

echo ""
echo "=== 2. Environment Variables ==="
echo "CALCOM_OP_UUID: ${CALCOM_OP_UUID:+SET}"
echo "CALCOM_API_URL: ${CALCOM_API_URL:-NOT_SET}"
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+SET}"
echo "TELEGRAM_CHAT_ID: ${TELEGRAM_CHAT_ID:-NOT_SET}"
echo "HAIKU_MODEL: ${HAIKU_MODEL:-NOT_SET}"
echo "OP_SERVICE_ACCOUNT_TOKEN: ${OP_SERVICE_ACCOUNT_TOKEN:+SET}"

echo ""
echo "=== 3. GCP Configuration ==="
echo "CALCOM_GCP_PROJECT: ${CALCOM_GCP_PROJECT:-NOT_SET}"
echo "CALCOM_GCP_ACCOUNT: ${CALCOM_GCP_ACCOUNT:-NOT_SET}"
echo "CALCOM_GCP_REGION: ${CALCOM_GCP_REGION:-NOT_SET}"

echo ""
echo "=== 4. Supabase Configuration ==="
echo "SUPABASE_PROJECT_REF: ${SUPABASE_PROJECT_REF:-NOT_SET}"
echo "SUPABASE_DB_URL_REF: ${SUPABASE_DB_URL_REF:+SET}"

echo ""
echo "=== 5. 1Password CLI ==="
op account list 2>&1 | head -3

echo ""
echo "=== 6. Bot Process ==="
if [ -f /tmp/calcom-commander-bot.pid ]; then
  PID=$(cat /tmp/calcom-commander-bot.pid)
  if kill -0 "$PID" 2>/dev/null; then
    echo "Running (PID $PID)"
  else
    echo "STALE PID file (process $PID not found)"
  fi
else
  echo "Not running"
fi

echo ""
echo "=== 7. Sync Process ==="
if [ -f /tmp/calcom-sync.pid ]; then
  PID=$(cat /tmp/calcom-sync.pid)
  if kill -0 "$PID" 2>/dev/null; then
    echo "Running (PID $PID)"
  else
    echo "Not running (stale PID)"
  fi
else
  echo "Not running"
fi

echo ""
echo "=== 8. launchd Jobs ==="
launchctl list | grep calcom-commander 2>/dev/null || echo "No launchd jobs registered"

echo ""
echo "=== 9. Circuit Breakers ==="
for f in /tmp/calcom-sync-circuit.json /tmp/calcom-commander-agent-circuit.json; do
  if [ -f "$f" ]; then
    echo "$(basename $f): $(cat $f)"
  else
    echo "$(basename $f): CLOSED (healthy)"
  fi
done

echo ""
echo "=== 10. Recent Audit Logs ==="
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
