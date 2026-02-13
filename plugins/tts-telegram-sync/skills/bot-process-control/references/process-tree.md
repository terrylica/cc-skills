# Process Tree

Process hierarchy and design rationale for the Telegram sync bot runner.

## Process Hierarchy

```
launchd (PID 1)
  └── zsh (interactive shell or background job)
        └── bun --watch run src/main.ts (bot runner)
              └── src/main.ts (application code)
```

When started from a shell session, the bot runs as a child of that shell. The `&` operator backgrounds it, and `bun --watch` acts as both the runtime and the file watcher.

## Why `bun --watch`

| Property         | `bun --watch`            | `bun --hot`           | External watchers (nodemon, watchexec) |
| ---------------- | ------------------------ | --------------------- | -------------------------------------- |
| Restart strategy | Full process restart     | In-place HMR          | Full process restart                   |
| Memory overhead  | 0 MB (built-in)          | 0 MB (built-in)       | +10-50 MB                              |
| State handling   | Clean slate each restart | **Stale state risk**  | Clean slate each restart               |
| File detection   | kqueue (macOS native)    | kqueue                | Varies (polling or inotify/kqueue)     |
| Dependency       | None (built into Bun)    | None (built into Bun) | Separate install required              |

**Decision**: `bun --watch` is the correct choice for long-running services like the Telegram bot because:

1. **Zero overhead** - No extra process or memory for file watching
2. **Clean restarts** - Full process restart avoids stale state from `--hot` (which uses HMR and can leave stale module state in long-running services)
3. **kqueue-based** - Uses macOS native file system events, not polling
4. **No dependencies** - No need for nodemon, tsx, ts-node-dev, or watchexec

## Anti-Pattern: `bun --hot`

`bun --hot` uses Hot Module Replacement (HMR) which replaces modules in-place without restarting the process. This is problematic for long-running services because:

- **Stale closures** - Event handlers registered in the old module version remain active
- **Leaked connections** - Database connections, WebSocket handles, and timers from previous versions are not cleaned up
- **Module-level state** - Singletons and module-scoped variables retain old values
- **Memory leaks** - Each hot reload can accumulate unreleased resources

For the Telegram bot, which maintains WebSocket connections, timers, and stateful handlers, a full restart via `--watch` is strictly safer.

## Process Detection Patterns

### Find the bot process

```bash
pgrep -la 'bun.*src/main.ts'
```

### Full process tree from PID

```bash
BOT_PID=$(pgrep -f 'bun.*src/main.ts')
ps -o pid,ppid,comm -p $BOT_PID
```

### Check parent-child relationships

```bash
ps -eo pid,ppid,comm | grep -E 'bun|main.ts'
```

## Signal Handling

| Signal                  | Behavior                                                      |
| ----------------------- | ------------------------------------------------------------- |
| SIGTERM (default pkill) | Graceful shutdown, Bun cleans up child processes              |
| SIGKILL (-KILL)         | Immediate termination, no cleanup                             |
| SIGHUP                  | Ignored by backgrounded processes (nohup not needed with `&`) |

The bot should handle SIGTERM gracefully by closing Telegram polling and flushing logs. If it does not respond to SIGTERM within 2 seconds, escalate to SIGKILL.
