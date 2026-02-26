# statusline-tools Plugin

> Custom status line with git status, link validation, and path linting indicators.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Skills

| Skill          | Purpose                                           |
| -------------- | ------------------------------------------------- |
| `session-info` | Get current Claude Code session UUID and registry |

## Hooks

| Hook                  | Event | Purpose                                  |
| --------------------- | ----- | ---------------------------------------- |
| `lychee-stop-hook.sh` | Stop  | Validates links and paths at session end |

## Commands

| Command                    | Purpose                                               |
| -------------------------- | ----------------------------------------------------- |
| `/statusline-tools:setup`  | Install/uninstall/check status line configuration     |
| `/statusline-tools:hooks`  | Install/uninstall Stop hook for link validation       |
| `/statusline-tools:ignore` | Manage global ignore patterns for lint-relative-paths |

## Status Line Indicators

| Indicator | Meaning                                    |
| --------- | ------------------------------------------ |
| M/D/S/U   | Modified, Deleted, Staged, Untracked files |
| ↑/↓       | Commits ahead/behind remote                |
| ≡         | Stash count                                |
| ⚠         | Merge conflicts                            |
| L         | Broken links (lychee)                      |
| P         | Path violations (lint-relative-paths)      |
