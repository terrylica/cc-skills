# Pueue Reminder for Long-Running Tasks

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Pueue Reminder for Long-Running Tasks

The `posttooluse-reminder.ts` hook detects long-running tasks and suggests using [Pueue](https://github.com/Nukesor/pueue) for job orchestration.

### Why Pueue?

| Benefit                 | Description                                   |
| ----------------------- | --------------------------------------------- |
| SSH disconnect survival | Daemon runs independently of terminal session |
| Crash recovery          | Queue persisted to disk, auto-resumes         |
| Resource management     | Per-group parallelism limits                  |
| Easy restart            | `pueue restart <id>` for failed jobs          |

### Detection Patterns

The hook triggers on commands matching these patterns:

| Pattern                    | Example                                   |
| -------------------------- | ----------------------------------------- |
| `populate_cache` scripts   | `python populate_full_cache.py --phase 1` |
| `bulk_insert/load/import`  | `python bulk_insert_data.py`              |
| Symbol + threshold         | `--symbol BTCUSDT --threshold 250`        |
| Shell for/while loops      | `for symbol in ...; do ...; done`         |
| SSH with long-running cmds | `ssh bigblack 'python populate_cache.py'` |

### Exceptions (No Reminder)

- Already using `pueue add`
- Status/plan/help flags (`--status`, `--plan`, `--help`)
- Already backgrounded (`nohup`, `screen`, `tmux`, `&`)
- Documentation (`echo`, comments)

### Example Reminder

```
[PUEUE-REMINDER] Long-running task detected - consider using Pueue

EXECUTED: ssh bigblack 'python populate_cache.py --phase 1'
PREFERRED: ssh bigblack "~/.local/bin/pueue add -- python populate_cache.py --phase 1"

WHY PUEUE:
- Daemon survives SSH disconnects, crashes, reboots
- Queue persisted to disk - auto-resumes after failure
- Per-group parallelism limits (avoid resource exhaustion)
- Easy restart of failed jobs: pueue restart <id>
```

### Reference

- Issue: [rangebar-py#77](https://github.com/terrylica/rangebar-py/issues/77)
- Pueue: [github.com/Nukesor/pueue](https://github.com/Nukesor/pueue)

