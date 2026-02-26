# dotfiles-tools Plugin

> Chezmoi dotfile management via natural language workflows.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [productivity-tools CLAUDE.md](../productivity-tools/CLAUDE.md)

## Skills

| Skill               | Purpose                                                              |
| ------------------- | -------------------------------------------------------------------- |
| `chezmoi-workflows` | Dotfile tracking, sync, push, templates, secret detection, migration |

## Hooks

| Hook                       | Event       | Matcher     | Purpose                                  |
| -------------------------- | ----------- | ----------- | ---------------------------------------- |
| `chezmoi-sync-reminder.sh` | PostToolUse | Edit\|Write | Reminder when editing tracked files      |
| `chezmoi-stop-guard.mjs`   | Stop        | (all)       | Blocks session end until dotfiles synced |

## Conventions

- **Stop hook enforcement**: `chezmoi diff` must be clean before Claude stops
- **10 workflows**: Status, track, sync, push, setup, source directory, remote, conflicts, validation
- **Template support**: Go templates with OS/arch conditionals
- **Secret detection**: Fail-fast on API keys, tokens, credentials
