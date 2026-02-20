---
name: bot-process-control
description: Gmail Commander daemon lifecycle - start, stop, restart, status, logs, launchd plist management. TRIGGERS - bot start, bot stop, bot restart, bot status, bot logs, launchd, daemon, process control, gmail-commander service.
allowed-tools: Read, Bash, Grep, Glob
---

# Bot Process Control

Manage the Gmail Commander bot daemon and scheduled digest via launchd.

## Mandatory Preflight

### Step 1: Check Current Process Status

```bash
echo "=== Gmail Commander Processes ==="
pgrep -fl "gmail-commander" 2>/dev/null || echo "No processes found"

echo ""
echo "=== launchd Status ==="
launchctl list | grep gmail-commander 2>/dev/null || echo "No launchd jobs"

echo ""
echo "=== PID Files ==="
cat /tmp/gmail-commander-bot.pid 2>/dev/null && echo " (bot)" || echo "No bot PID file"
cat /tmp/gmail-digest.pid 2>/dev/null && echo " (digest)" || echo "No digest PID file"
```

## Two Services

| Service    | Type          | Trigger                    | PID File                     |
| ---------- | ------------- | -------------------------- | ---------------------------- |
| Bot Daemon | KeepAlive     | Always-on (grammY polling) | /tmp/gmail-commander-bot.pid |
| Digest     | StartInterval | Every 6 hours (21600s)     | /tmp/gmail-digest.pid        |

## launchd Plist Templates

### Bot Daemon — `com.terryli.gmail-commander-bot.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.terryli.gmail-commander-bot</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{HOME}}/own/amonic/bin/gmail-commander-bot</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
    </dict>
    <key>StandardOutPath</key>
    <string>{{HOME}}/own/amonic/logs/bot-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>{{HOME}}/own/amonic/logs/bot-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>{{HOME}}/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
```

### Scheduled Digest — `com.terryli.gmail-commander-digest.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.terryli.gmail-commander-digest</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{HOME}}/own/amonic/bin/gmail-commander-digest</string>
    </array>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>StandardOutPath</key>
    <string>{{HOME}}/own/amonic/logs/digest-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>{{HOME}}/own/amonic/logs/digest-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>{{HOME}}/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

## Quick Operations

### Start Bot

```bash
launchctl load ~/Library/LaunchAgents/com.terryli.gmail-commander-bot.plist
```

### Stop Bot

```bash
launchctl unload ~/Library/LaunchAgents/com.terryli.gmail-commander-bot.plist
```

### Restart Bot

```bash
launchctl unload ~/Library/LaunchAgents/com.terryli.gmail-commander-bot.plist
launchctl load ~/Library/LaunchAgents/com.terryli.gmail-commander-bot.plist
```

### Force Kill (Emergency)

```bash
pkill -f "gmail-commander.*bot.ts"
rm -f /tmp/gmail-commander-bot.pid
```

### View Logs

```bash
# Recent bot output
tail -50 ~/own/amonic/logs/bot-stderr.log

# Recent digest output
tail -50 ~/own/amonic/logs/digest-stderr.log

# Audit log (NDJSON)
cat ~/own/amonic/logs/audit/$(date +%Y-%m-%d).ndjson | jq .
```

## System Resources (Expected)

- **Memory**: ~20-30 MB RSS (Bun runtime + grammY)
- **CPU**: Negligible (idle polling, wakes on message)
- **Network**: Minimal (single long-poll connection to Telegram API)
- **Disk**: ~1 MB/day audit logs (14-day rotation)

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] launchd plist templates match actual launcher scripts
