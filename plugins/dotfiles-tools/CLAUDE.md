# dotfiles-tools Plugin

> Chezmoi dotfile management via natural language workflows.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [productivity-tools CLAUDE.md](../productivity-tools/CLAUDE.md)

## Skills

- [chezmoi-sync](./skills/chezmoi-sync/SKILL.md)
- [chezmoi-workflows](./skills/chezmoi-workflows/SKILL.md)

## Hooks

| Hook                       | Event       | Matcher                | Purpose                             |
| -------------------------- | ----------- | ---------------------- | ----------------------------------- |
| `chezmoi-sync-reminder.sh` | PostToolUse | Edit\|Write\|MultiEdit | Reminder when editing tracked files |

`hooks/hooks.json` is the only registration — Claude Code loads it from the plugin. The `tether` skill and `scripts/manage-hooks.sh` that used to copy this same hook into `~/.claude/settings.json` were retired in issue #127; the second registration would have fired the reminder twice per edit.

## Conventions

- **On-demand sync**: Use `/dotfiles-tools:chezmoi-sync` to check drift and sync interactively
- **14 workflows**: Status, track, sync, push, setup, source directory, remote, conflicts, validation, forget, templates, safe update, doctor
- **Template support**: Go templates with OS/arch conditionals
- **Secret detection**: Fail-fast on API keys, tokens, credentials
