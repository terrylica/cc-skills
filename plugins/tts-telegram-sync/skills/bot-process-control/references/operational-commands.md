# Operational Commands

Reference for all bot process management commands.

## Status

Check whether the bot is running and display process details:

```bash
# Simple check (returns PID and command line)
pgrep -la 'bun.*src/main.ts'

# Detailed process info (CPU, memory, uptime)
ps aux | grep 'bun.*src/main.ts' | grep -v grep

# Count running instances (should be 0 or 1)
pgrep -c -f 'bun.*src/main.ts'
```

Expected output when running:

```
12345 $HOME/.local/share/mise/installs/bun/latest/bin/bun --watch run src/main.ts
```

Expected output when stopped: no output, exit code 1.

## Start

Launch the bot in background with file watching enabled:

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

## Stop

Terminate the bot process:

```bash
pkill -f 'bun.*src/main.ts'
```

**Graceful stop** (SIGTERM first, SIGKILL fallback):

```bash
pkill -TERM -f 'bun.*src/main.ts'
sleep 2
# If still running, force kill
pgrep -f 'bun.*src/main.ts' && pkill -KILL -f 'bun.*src/main.ts'
```

**Verify after stop**:

```bash
pgrep -la 'bun.*src/main.ts'
# Should produce no output
```

## Restart

Stop then start in sequence:

```bash
pkill -f 'bun.*src/main.ts'
sleep 1
cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts >> /private/tmp/telegram-bot.log 2>&1 &
sleep 1
pgrep -la 'bun.*src/main.ts'
```

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
# Kill all matching processes
pkill -KILL -f 'bun.*src/main.ts'

# Verify all killed
sleep 1
pgrep -la 'bun.*src/main.ts'

# Clean start
cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts >> /private/tmp/telegram-bot.log 2>&1 &
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
