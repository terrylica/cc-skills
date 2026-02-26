# Verification and Troubleshooting

## Phase 7: Verification

### Check daemon status

```bash
/usr/bin/env bash << 'VERIFY_DAEMON_EOF'
HEALTH_FILE="$HOME/.asciinema/health.json"

# Wait for health file
sleep 3

if [[ -f "$HEALTH_FILE" ]]; then
  STATUS=$(jq -r '.status' "$HEALTH_FILE")
  MESSAGE=$(jq -r '.message' "$HEALTH_FILE")
  PID=$(jq -r '.pid' "$HEALTH_FILE")
  echo "HEALTH_STATUS:$STATUS"
  echo "HEALTH_MESSAGE:$MESSAGE"
  echo "HEALTH_PID:$PID"
else
  echo "HEALTH_FILE_MISSING"
fi

# Check launchctl
if launchctl list 2>/dev/null | grep -q "asciinema-chunker"; then
  echo "LAUNCHCTL_OK"
else
  echo "LAUNCHCTL_NOT_FOUND"
fi
VERIFY_DAEMON_EOF
```

### Post-verification prompt

**Use AskUserQuestion:**

```
Question: "Setup complete! Daemon status: {status}. What would you like to do next?"
Header: "Complete"
Options:
  - label: "Show health status"
    description: "Display daemon health information"
  - label: "View logs"
    description: "Show recent log entries"
  - label: "Done"
    description: "Exit setup wizard"
```

**If "Show health status":**

```bash
cat ~/.asciinema/health.json | jq .
```

**If "View logs":**

```bash
tail -20 ~/.asciinema/logs/chunker.log
```

## Final Success Message

```markdown
## Success: Daemon Setup Complete

**Status**: Running
**PID**: {pid}
**Health file**: ~/.asciinema/health.json
**Logs**: ~/.asciinema/logs/chunker.log

### Quick Commands

| Command                          | Description         |
| -------------------------------- | ------------------- |
| `/asciinema-tools:daemon-status` | Check daemon health |
| `/asciinema-tools:daemon-logs`   | View logs           |
| `/asciinema-tools:daemon-stop`   | Stop daemon         |
| `/asciinema-tools:daemon-start`  | Start daemon        |

### Next Steps

1. Run `/asciinema-tools:bootstrap` to start a recording session
2. The daemon will automatically push chunks to GitHub
3. You'll receive Pushover notifications if pushes fail

The daemon is now completely independent of Claude Code CLI.
You can switch `gh auth` accounts freely without affecting backups.
```

## Troubleshooting

| Issue                  | Cause                          | Solution                               |
| ---------------------- | ------------------------------ | -------------------------------------- |
| Keychain access denied | macOS permission not granted   | Grant access in System Settings        |
| PAT test failed        | Token expired or invalid scope | Generate new token with `repo` scope   |
| launchctl load failed  | plist syntax error             | Check `plutil -lint <plist-path>`      |
| Daemon keeps stopping  | Script error or crash          | Check `/asciinema-tools:daemon-logs`   |
| Pushover not working   | Invalid credentials            | Re-run setup with correct app/user key |
| Health file missing    | Daemon not running             | Run `/asciinema-tools:daemon-start`    |
