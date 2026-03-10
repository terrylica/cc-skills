# statusline-tools Plugin

> Custom status line with git status indicators.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Skills

| Skill          | Purpose                                           |
| -------------- | ------------------------------------------------- |
| `session-info` | Get current Claude Code session UUID and registry |

## Commands

| Command                   | Purpose                                           |
| ------------------------- | ------------------------------------------------- |
| `/statusline-tools:setup` | Install/uninstall/check status line configuration |

## Status Line Indicators

| Indicator | Meaning                                    |
| --------- | ------------------------------------------ |
| M/D/S/U   | Modified, Deleted, Staged, Untracked files |
| ↑/↓       | Commits ahead/behind remote                |
| ≡         | Stash count                                |
| ⚠         | Merge conflicts                            |
