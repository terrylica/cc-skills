# iterm2-layout-config

iTerm2 workspace layout configuration plugin for Claude Code marketplace.

## Overview

This plugin provides skills for configuring iTerm2 workspace layouts with proper separation of concerns:

- **Private data** (workspace paths, project directories) → `~/.config/iterm2/layout.toml`
- **Publishable code** (layout logic, API integration) → `default-layout.py`

## Architecture

```
                       🏗️ Configuration Flow

╭──────────────────────────────╮
│       iTerm2 Launches        │
╰──────────────────────────────╯
  │
  │
  ∨
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃      default-layout.py       ┃
┃       [+] git-tracked        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
  │
  │
  ∨
╔══════════════════════════════╗
║ ~/.config/iterm2/layout.toml ║
║   [+] private (user paths)   ║
╚══════════════════════════════╝
  │
  │
  ∨
╭──────────────────────────────╮
│    Workspace Tabs Created    │
╰──────────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Configuration Flow"; flow: south; }

[ iterm2 ] { label: "iTerm2 Launches"; shape: rounded; }
[ script ] { label: "default-layout.py\n[+] git-tracked"; border: bold; }
[ config ] { label: "~/.config/iterm2/layout.toml\n[+] private (user paths)"; border: double; }
[ tabs ] { label: "Workspace Tabs Created"; shape: rounded; }

[ iterm2 ] -> [ script ]
[ script ] -> [ config ]
[ config ] -> [ tabs ]
```

</details>

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

```
                       📋 Setup Flow

╭──────────╮     ┌─────────┐     ┌────────────┐      ══════
│ 1. Copy  │     │ 2. Edit │     │ 3. Restart │     ║ Done ║
│ Template │ ──> │  Paths  │ ──> │   iTerm2   │ ──> ║      ║
╰──────────╯     └─────────┘     └────────────┘      ══════
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "📋 Setup Flow"; flow: east; }

[ copy ] { label: "1. Copy\nTemplate"; shape: rounded; }
[ edit ] { label: "2. Edit\nPaths"; }
[ restart ] { label: "3. Restart\niTerm2"; }
[ done ] { label: "Done"; shape: rounded; border: double; }

[ copy ] -> [ edit ] -> [ restart ] -> [ done ]
```

</details>

```bash
cp ~/scripts/iterm2/layout.example.toml ~/.config/iterm2/layout.toml
```

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
