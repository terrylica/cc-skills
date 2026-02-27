# Operational Commands

Reference for all bot process management commands.

## Status

Check whether the bot is running and display process details:

```bash
# Simple check — both runner and bun process
pgrep -la 'telegram-bot-runner|bun.*src/main.ts'

# Detailed process info (CPU, memory, uptime)
ps aux | grep -E 'telegram-bot-runner|bun.*src/main.ts' | grep -v grep

# Count running instances (should be 0 or 1)
pgrep -c -f 'bun.*src/main.ts'
```

Expected output when running (production — launchd managed):

```
91854 /Users/terryli/.claude/automation/claude-telegram-sync/telegram-bot-runner
91870 /Users/terryli/.local/share/mise/installs/bun/1.3.5/bin/bun --watch run src/main.ts
```

Expected output when stopped: no output, exit code 1.

## Restart (Production)

Kill the bun process — the Swift runner respawns it automatically with `bun --watch`:

```bash
pkill -f 'bun.*src/main.ts'
sleep 2
pgrep -la 'telegram-bot-runner|bun.*src/main.ts'
```

Code changes also auto-restart: `bun --watch` detects `.ts` file modifications via kqueue and restarts the process without intervention.

## Start (via launchd)

```bash
launchctl kickstart -k gui/$(id -u)/com.terryli.telegram-bot
```

## Start (ad-hoc, for debugging)

Launch directly from a shell session:

```bash
cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts >> /private/tmp/telegram-bot.log 2>&1 &
```

**Breakdown**:

- `cd ~/.claude/automation/claude-telegram-sync` - Bot source directory (mise.toml loads env vars)
- `bun --watch run src/main.ts` - Bun with kqueue-based file watcher
- `>> /private/tmp/telegram-bot.log` - Append stdout to legacy log file
- `2>&1` - Redirect stderr to same log
- `&` - Background the process

**Verify after start**:

```bash
sleep 1 && pgrep -la 'bun.*src/main.ts'
```

## Stop (Full)

Terminate both the Swift runner and bun process:

```bash
pkill -f 'telegram-bot-runner'
pkill -f 'bun.*src/main.ts'
```

**Verify after stop**:

```bash
pgrep -la 'telegram-bot-runner|bun.*src/main.ts'
# Should produce no output
```

**Note**: If you only kill the bun process (not the runner), the runner will respawn it automatically. To fully stop, kill both.

## Logs

### Legacy Log File

```bash
# Tail recent output
tail -50 /private/tmp/telegram-bot.log

# Follow live output
tail -f /private/tmp/telegram-bot.log

# Search for errors
grep -i 'error\|exception\|fatal' /private/tmp/telegram-bot.log | tail -20
```

### Structured Logs (NDJSON)

```bash
# List recent log files
ls -lt ~/.local/share/tts-telegram-sync/logs/bot-console/ | head -10

# Read most recent log file
cat "$(ls -t ~/.local/share/tts-telegram-sync/logs/bot-console/*.ndjson 2>/dev/null | head -1)"

# Parse with jq for errors
cat "$(ls -t ~/.local/share/tts-telegram-sync/logs/bot-console/*.ndjson 2>/dev/null | head -1)" | jq 'select(.level == "error")'
```

## Emergency: Kill All Instances

When multiple instances are running or the bot is in a bad state:

```bash
# Kill everything — runner + bun
pkill -KILL -f 'telegram-bot-runner'
pkill -KILL -f 'bun.*src/main.ts'

# Verify all killed
sleep 1
pgrep -la 'telegram-bot-runner|bun.*src/main.ts'

# Clean start via launchd
launchctl kickstart -k gui/$(id -u)/com.terryli.telegram-bot
```

## Environment Verification

Before starting, verify the environment is ready:

```bash
# Check bun is available
which bun && bun --version

# Check bot source exists
ls ~/.claude/automation/claude-telegram-sync/src/main.ts

# Check mise.toml exists (loads env vars)
ls ~/.claude/automation/claude-telegram-sync/mise.toml

# Check secrets file exists
[[ -f ~/.claude/.secrets/ccterrybot-telegram ]] && echo "Secrets OK" || echo "Secrets MISSING"
```
