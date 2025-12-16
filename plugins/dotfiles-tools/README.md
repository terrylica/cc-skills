# dotfiles-tools

Chezmoi dotfile backup, sync, and version control for cross-machine configuration management.

## Skills

| Skill                 | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| **chezmoi-workflows** | Dotfile tracking, sync, push, templates, secret detection, migration |

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
- Platform: macOS, Linux

## License

MIT
