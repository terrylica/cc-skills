# dotfiles-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-2-blue.svg)]()
[![Hooks](https://img.shields.io/badge/Hooks-1-orange.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Chezmoi dotfile backup, sync, and version control for cross-machine configuration management.

## Skills

| Skill                 | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| **chezmoi-workflows** | Dotfile tracking, sync, push, templates, secret detection, migration |
| **chezmoi-sync**      | Interactive on-demand chezmoi drift check and sync                   |

## Hooks

| Hook                       | Type        | Trigger       | Effect                         |
| -------------------------- | ----------- | ------------- | ------------------------------ |
| `chezmoi-sync-reminder.sh` | PostToolUse | Edit \| Write | **Reminder** (visibility only) |

### PostToolUse: Chezmoi Sync Reminder

When you edit a file tracked by chezmoi, Claude receives an immediate reminder:

```
[CHEZMOI-SYNC] ~/.zshrc is tracked by chezmoi.
Sync with: chezmoi add ~/.zshrc && chezmoi git -- push
```

**Limitation**: Only triggers on `Edit|Write` tools, not `Bash(cp ...)`.

### On-Demand Sync

Use `/dotfiles-tools:chezmoi-sync` to interactively check drift and sync. Options:

- **Sync all** — Re-add all drifted files, commit, push
- **Review each** — Per-file choices (sync, diff, forget, skip)
- **Ignore** — Skip for now

## Installation

```bash
/plugin install cc-skills@dotfiles-tools
```

## Capabilities

- **14 Workflows**: Status, track, sync, push, setup, source directory, remote, conflicts, validation, forget, templates, safe update, doctor
- **Template Support**: Go templates with OS/arch conditionals
- **Secret Detection**: Fail-fast on detected API keys, tokens, credentials
- **Multi-Account SSH**: Directory-based GitHub account selection
- **Private Repos**: Recommended for dotfile backup

## Configuration

The skill guides users through their own chezmoi setup:

- Source directory: configurable (default `~/.local/share/chezmoi`)
- Remote: user's own GitHub repository (private recommended)
- Settings: `~/.config/chezmoi/chezmoi.toml`

## Requirements

- Chezmoi (`brew install chezmoi`)
- Git
- jq (`brew install jq`) - for hooks
- Platform: macOS, Linux

## Troubleshooting

| Issue                         | Cause                | Solution                                 |
| ----------------------------- | -------------------- | ---------------------------------------- |
| chezmoi not found             | Not installed        | `brew install chezmoi`                   |
| Hook not triggering           | File not tracked     | Run `chezmoi managed` to verify tracking |
| Git push fails                | No remote configured | `chezmoi git -- remote add origin <url>` |
| Diff shows unexpected changes | Template variables   | Check `chezmoi data` for correct values  |
| Permission denied             | File mode mismatch   | `chezmoi re-add --verbose` to refresh    |

## License

MIT
