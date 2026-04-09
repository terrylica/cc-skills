# statusline-tools Plugin

> Custom status line with git status indicators.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Siblings**: [itp-hooks](../itp-hooks/CLAUDE.md) | [asciinema-tools](../asciinema-tools/CLAUDE.md) | [link-tools](../link-tools/CLAUDE.md)

## Skills

| Skill          | Purpose                                                |
| -------------- | ------------------------------------------------------ |
| `setup`        | Install/uninstall/status for statusline + dependencies |
| `ignore`       | Manage global ignore patterns for lint-relative-paths  |
| `session-info` | Display current session UUID, chain, registry info     |
| `hooks`        | Install/uninstall link validation stop hooks           |

## Commands

| Command                    | Purpose                      |
| -------------------------- | ---------------------------- |
| `/statusline-tools:setup`  | Configure statusline         |
| `/statusline-tools:ignore` | Manage ignore patterns       |
| `/statusline-tools:hooks`  | Manage link validation hooks |

## Hooks

| Hook                  | Trigger                              | Purpose                                   |
| --------------------- | ------------------------------------ | ----------------------------------------- |
| `cron-tracker.ts`     | PostToolUse (CronCreate/Delete/List) | Tracks active cron jobs in session state  |
| `stop-cron-gc.ts`     | Stop                                 | Prunes stale cron entries on session exit |
| `lychee-stop-hook.sh` | Stop (installed via manage-hooks.sh) | Link validation on session exit           |

## Status Line Indicators

| Indicator | Meaning                                    |
| --------- | ------------------------------------------ |
| M/D/S/U   | Modified, Deleted, Staged, Untracked files |
| ↑/↓       | Commits ahead/behind remote                |
| ≡         | Stash count                                |
| ⚠         | Merge conflicts                            |
