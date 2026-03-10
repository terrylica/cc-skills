# dotfiles-tools Plugin

> Chezmoi dotfile management via natural language workflows.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [productivity-tools CLAUDE.md](../productivity-tools/CLAUDE.md)

## Skills

| Skill               | Purpose                                                              |
| ------------------- | -------------------------------------------------------------------- |
| `chezmoi-workflows` | Dotfile tracking, sync, push, templates, secret detection, migration |
| `chezmoi-sync`      | Interactive on-demand chezmoi drift check and sync                   |

## Hooks

| Hook                       | Event       | Matcher     | Purpose                             |
| -------------------------- | ----------- | ----------- | ----------------------------------- |
| `chezmoi-sync-reminder.sh` | PostToolUse | Edit\|Write | Reminder when editing tracked files |

## Conventions

- **On-demand sync**: Use `/dotfiles-tools:chezmoi-sync` to check drift and sync interactively
- **14 workflows**: Status, track, sync, push, setup, source directory, remote, conflicts, validation, forget, templates, safe update, doctor
- **Template support**: Go templates with OS/arch conditionals
- **Secret detection**: Fail-fast on API keys, tokens, credentials
