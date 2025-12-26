---
description: Check asciinema chunker daemon status, health, and recent activity. TRIGGERS - daemon status, check backup, chunker health.
allowed-tools: Bash
argument-hint: "[--verbose]"
---

# /asciinema-tools:daemon-status

Check the status of the asciinema chunker daemon.

## Execution

### Collect Status Information

```bash
/usr/bin/env bash << 'STATUS_EOF'
PLIST_PATH="$HOME/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist"
HEALTH_FILE="$HOME/.asciinema/health.json"
LOG_FILE="$HOME/.asciinema/logs/chunker.log"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  asciinema-chunker Daemon Status                               ║"
echo "╠════════════════════════════════════════════════════════════════╣"

# Check installation
if [[ -f "$PLIST_PATH" ]]; then
  echo "║  Installed: Yes                                                ║"
else
  echo "║  Installed: No - run /asciinema-tools:daemon-setup             ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  exit 0
fi

# Check if running
if launchctl list 2>/dev/null | grep -q "asciinema-chunker"; then
  echo "║  Running: Yes                                                  ║"
else
  echo "║  Running: No                                                   ║"
fi

echo "╠════════════════════════════════════════════════════════════════╣"

# Health file
if [[ -f "$HEALTH_FILE" ]]; then
  STATUS=$(jq -r '.status // "unknown"' "$HEALTH_FILE")
  MESSAGE=$(jq -r '.message // ""' "$HEALTH_FILE")
  PID=$(jq -r '.pid // "?"' "$HEALTH_FILE")
  LAST_PUSH=$(jq -r '.last_push // "never"' "$HEALTH_FILE")
  CHUNKS=$(jq -r '.chunks_pushed // 0' "$HEALTH_FILE")
  LAST_UPDATE=$(jq -r '.last_update // ""' "$HEALTH_FILE")

  printf "║  Status: %-52s ║\n" "$STATUS"
  printf "║  PID: %-55s ║\n" "$PID"
  printf "║  Last push: %-49s ║\n" "$LAST_PUSH"
  printf "║  Chunks pushed: %-44s ║\n" "$CHUNKS"
  printf "║  Message: %-51s ║\n" "${MESSAGE:0:51}"
else
  echo "║  Health file: Not found                                        ║"
fi

echo "╠════════════════════════════════════════════════════════════════╣"

# Active recordings
ACTIVE_COUNT=$(ls -1 "$HOME/.asciinema/active/"*.cast 2>/dev/null | wc -l | tr -d ' ')
printf "║  Active recordings: %-41s ║\n" "$ACTIVE_COUNT"

# Log file
if [[ -f "$LOG_FILE" ]]; then
  LOG_SIZE=$(ls -lh "$LOG_FILE" | awk '{print $5}')
  printf "║  Log file: %-50s ║\n" "$LOG_SIZE"
else
  echo "║  Log file: Not created yet                                     ║"
fi

echo "╠════════════════════════════════════════════════════════════════╣"

# Credentials
if security find-generic-password -s "asciinema-github-pat" -a "$USER" -w &>/dev/null 2>&1; then
  echo "║  GitHub PAT: Configured                                        ║"
else
  echo "║  GitHub PAT: Not configured                                    ║"
fi

if security find-generic-password -s "asciinema-pushover-app" -a "$USER" -w &>/dev/null 2>&1; then
  echo "║  Pushover: Configured                                          ║"
else
  echo "║  Pushover: Not configured                                      ║"
fi

echo "╚════════════════════════════════════════════════════════════════╝"

# Recent log entries
echo ""
echo "Recent log entries:"
echo "-------------------"
if [[ -f "$LOG_FILE" ]]; then
  tail -5 "$LOG_FILE"
else
  echo "(no logs yet)"
fi
STATUS_EOF
```

## Output Example

```
╔════════════════════════════════════════════════════════════════╗
║  asciinema-chunker Daemon Status                               ║
╠════════════════════════════════════════════════════════════════╣
║  Installed: Yes                                                ║
║  Running: Yes                                                  ║
╠════════════════════════════════════════════════════════════════╣
║  Status: ok                                                    ║
║  PID: 12345                                                    ║
║  Last push: 2025-12-26T15:30:00Z                               ║
║  Chunks pushed: 7                                              ║
║  Message: Monitoring ~/.asciinema/active                       ║
╠════════════════════════════════════════════════════════════════╣
║  Active recordings: 1                                          ║
║  Log file: 24K                                                 ║
╠════════════════════════════════════════════════════════════════╣
║  GitHub PAT: Configured                                        ║
║  Pushover: Configured                                          ║
╚════════════════════════════════════════════════════════════════╝

Recent log entries:
-------------------
[2025-12-26 15:30:00] Pushed: chunk_20251226_153000.cast.zst
[2025-12-26 15:25:00] Idle detected (32s) for workspace_2025-12-26.cast
```
