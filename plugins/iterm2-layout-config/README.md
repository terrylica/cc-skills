# iterm2-layout-config

iTerm2 workspace layout configuration plugin for Claude Code marketplace.

## Overview

This plugin provides skills for configuring iTerm2 workspace layouts with proper separation of concerns:

- **Private data** (workspace paths, project directories) → `~/.config/iterm2/layout.toml`
- **Publishable code** (layout logic, API integration) → `default-layout.py`

## Features

- TOML-based configuration using native Python 3.11+ `tomllib`
- XDG Base Directory compliant (`~/.config/iterm2/`)
- Graceful error handling with Script Console output
- Dynamic git worktree detection support
- Example configuration templates

## Installation

```bash
/plugin install cc-skills@iterm2-layout-config
```

## Configuration

### Config File Location

`~/.config/iterm2/layout.toml` (XDG standard)

### Setup

1. Copy template to config location
2. Edit with your workspace paths
3. Restart iTerm2

### Example Config

```toml
[layout]
left_pane_ratio = 0.20
settle_time = 0.3

[commands]
left = "br --sort-by-type-dirs-first"
right = "zsh"

[[tabs]]
name = "home"
dir = "~"

[[tabs]]
name = "projects"
dir = "~/projects"
```

## Skills

| Skill         | Description                                                 |
| ------------- | ----------------------------------------------------------- |
| iterm2-layout | Configuration patterns, troubleshooting, and best practices |

## Related

- [iTerm2 Python API Documentation](https://iterm2.com/python-api/)
- [TOML Specification](https://toml.io/)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)

## License

MIT
