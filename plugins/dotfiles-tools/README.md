# dotfiles-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-1-blue.svg)]()
[![Hooks](https://img.shields.io/badge/Hooks-2-orange.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

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

Two complementary hooks ensure chezmoi sync:

| Hook                       | Type        | Trigger       | Effect                                |
| -------------------------- | ----------- | ------------- | ------------------------------------- |
| `chezmoi-sync-reminder.sh` | PostToolUse | Edit \| Write | **Reminder** (visibility only)        |
| `chezmoi-stop-guard.mjs`   | Stop        | Session end   | **Enforcement** (blocks until synced) |

### PostToolUse: Chezmoi Sync Reminder

When you edit a file tracked by chezmoi, Claude receives an immediate reminder:

```
[CHEZMOI-SYNC] ~/.zshrc is tracked by chezmoi.
Sync with: chezmoi add ~/.zshrc && chezmoi git -- push
```

**Limitation**: Only triggers on `Edit|Write` tools, not `Bash(cp ...)`.

### Stop: Chezmoi Sync Guard (NEW)

When Claude tries to stop, this hook checks `chezmoi diff`. If uncommitted changes exist:

```
[CHEZMOI-GUARD] Uncommitted dotfile changes detected. Sync before stopping:

Modified files:
  - ~/.config/foo.conf
  - ~/.zshrc

Run these commands:
  chezmoi re-add --verbose
  chezmoi git -- add -A && chezmoi git -- commit -m "sync: dotfiles" && chezmoi git -- push
```

**Key difference**: Stop hooks with `decision: block` **ACTUALLY PREVENT** Claude from stopping.
Claude is FORCED to take action before the session can end.

**Catches everything**: Unlike PostToolUse, this catches `Bash(cp ...)`, `mv`, redirects - any file change.

### Installation

```bash
/dotfiles-tools:hooks install
# Restart Claude Code for changes to take effect
```

### Requirements

| Tool      | Purpose                        | Install                        |
| --------- | ------------------------------ | ------------------------------ |
| `chezmoi` | Dotfile management             | `brew install chezmoi`         |
| `jq`      | JSON parsing (PostToolUse)     | `brew install jq`              |
| `bun`     | JavaScript runtime (Stop hook) | `brew install oven-sh/bun/bun` |

### Technical Notes

- **PostToolUse**: Uses `decision: block` for visibility (tool already ran)
- **Stop**: Uses `decision: block` for enforcement (blocks stopping)
- See ADR: 2025-12-17-posttooluse-hook-visibility in cc-skills source

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
