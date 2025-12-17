# dotfiles-tools

Chezmoi dotfile backup, sync, and version control for cross-machine configuration management.

## Skills

| Skill                 | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| **chezmoi-workflows** | Dotfile tracking, sync, push, templates, secret detection, migration |

## Commands

| Command                     | Description                            |
| --------------------------- | -------------------------------------- |
| `/dotfiles:hooks install`   | Add chezmoi hook to settings.json      |
| `/dotfiles:hooks uninstall` | Remove chezmoi hook from settings.json |
| `/dotfiles:hooks status`    | Show current installation state        |
| `/dotfiles:hooks restore`   | List/restore backups                   |

## Hooks

### PostToolUse: Chezmoi Sync Reminder

| Trigger       | Files                 | Behavior                         |
| ------------- | --------------------- | -------------------------------- |
| Edit \| Write | chezmoi-managed files | INSTRUCTION to invoke skill/sync |

When you edit a file tracked by chezmoi, the hook emits:

```
INSTRUCTION: ~/.zshrc is tracked by chezmoi. Use Skill(dotfiles-tools:chezmoi-workflows) to sync.
Quick: chezmoi add ~/.zshrc && chezmoi git -- push
```

**Installation Required**: Hooks must be installed to `~/.claude/settings.json`:

```bash
/dotfiles:hooks install
# Restart Claude Code for changes to take effect
```

**Performance**: Uses 5-minute cache of managed files list.

**Requirements**: `chezmoi`, `jq` installed and in PATH.

## Installation

```bash
/plugin install cc-skills@dotfiles-tools
```

## Capabilities

- **10 Workflows**: Status, track, sync, push, setup, source directory, remote, conflicts, validation
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

- Chezmoi 2.66.1+ (`brew install chezmoi`)
- Git 2.51.1+
- jq 1.7+ (`brew install jq`) - for hooks
- Platform: macOS, Linux

## License

MIT
