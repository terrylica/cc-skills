---
name: bot-process-control
description: Start, stop, or restart the Telegram sync bot process. TRIGGERS - start bot, stop bot, restart bot, bot process, bot status, bot control.
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Bot Process Control

Start, stop, restart, and monitor the Telegram sync bot process. Provides lifecycle management for the `bun --watch` bot runner with process verification and log access.

> **Platform**: macOS (Apple Silicon)

## When to Use This Skill

- Start or restart the Telegram bot after configuration changes
- Stop the bot before maintenance or debugging
- Check whether the bot is running and healthy
- Tail recent bot logs to diagnose issues
- Recover from multiple-instance or zombie process scenarios

## Requirements

- Bun runtime installed via mise
- Bot source at `~/.claude/automation/claude-telegram-sync/`
- Secrets file at `~/.claude/.secrets/ccterrybot-telegram`
- mise.toml configured in the bot source directory

## Workflow Phases

### Phase 1: Status Check

Show current bot process state using `pgrep`:

```bash
pgrep -la 'bun.*src/main.ts'
```

If no output, the bot is not running. If multiple lines appear, there are duplicate instances that need cleanup.

### Phase 2: Ask User Intent

Use `AskUserQuestion` to determine the desired action:

- **start** - Launch the bot in background with `bun --watch`
- **stop** - Kill the bot process cleanly
- **restart** - Stop then start
- **logs** - Tail recent log output

### Phase 3: Execute Action

**Start**:

```bash
cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts >> /private/tmp/telegram-bot.log 2>&1 &
```

**Stop**:

```bash
pkill -f 'bun.*src/main.ts'
```

**Restart**:

```bash
pkill -f 'bun.*src/main.ts'
sleep 1
cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts >> /private/tmp/telegram-bot.log 2>&1 &
```

**Logs**:

```bash
tail -50 /private/tmp/telegram-bot.log
# Or structured logs:
ls -lt ~/.local/share/tts-telegram-sync/logs/bot-console/ | head -5
```

### Phase 4: Verify

Confirm the process state changed as expected:

```bash
pgrep -la 'bun.*src/main.ts'
```

## TodoWrite Task Templates

```
1. [Check] Show current bot process status with pgrep
2. [Action] Present start/stop/restart/logs options via AskUserQuestion
3. [Execute] Run the selected action command
4. [Verify] Confirm process state changed as expected
5. [Logs] Optionally tail recent logs for confirmation
6. [Done] Report final process status to user
```

## Post-Change Checklist

- [ ] Verified no duplicate bot instances running
- [ ] Confirmed bot responds to Telegram messages (if started)
- [ ] Checked log output for startup errors (if started)
- [ ] Ensured previous process fully terminated (if stopped/restarted)

## Troubleshooting

| Issue                              | Cause                                 | Solution                                                                                              |
| ---------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Bot not running                    | Process crashed or was never started  | Check with `pgrep`, restart with start command                                                        |
| Multiple instances                 | Previous stop did not fully terminate | `pkill -f 'bun.*src/main.ts'`, wait, then start fresh                                                 |
| Port conflict                      | Another process occupying the port    | Identify with `lsof -i :PORT`, kill conflicting process                                               |
| Logs not writing                   | Log directory missing or permissions  | Verify `/private/tmp/` is writable; check `~/.local/share/tts-telegram-sync/logs/bot-console/` exists |
| bun not found                      | mise shims not in PATH                | Ensure `~/.local/share/mise/shims` is in PATH                                                         |
| Bot starts but crashes immediately | Missing env vars or secrets           | Check `~/.claude/.secrets/ccterrybot-telegram` exists; verify mise.toml env section                   |
| `--watch` not reloading            | File outside watch scope changed      | Restart manually; `bun --watch` monitors the entry file's dependency tree                             |

## Reference Documentation

- [Operational Commands](./references/operational-commands.md) - All start/stop/restart/status/logs commands
- [Process Tree](./references/process-tree.md) - Process hierarchy and `bun --watch` design rationale
- [Evolution Log](./references/evolution-log.md) - Change history for this skill
