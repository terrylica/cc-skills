# statusline-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-1-blue.svg)]()
[![Hooks](https://img.shields.io/badge/Hooks-0-gray.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Custom Claude Code status line with git status indicators.

## Skills

| Skill          | Description                                       |
| -------------- | ------------------------------------------------- |
| `session-info` | Get current Claude Code session UUID and registry |

**Trigger phrases:** "current session", "session uuid", "session id", "what session"

## Features

- **Git Status Indicators**: M (modified), D (deleted), S (staged), U (untracked)
- **Remote Tracking**: ↑ (ahead), ↓ (behind)
- **Repository State**: ≡ (stash count), ⚠ (merge conflicts)
- **GitHub URL**: Clickable link to current branch

## Installation

```bash
# The plugin is part of cc-skills marketplace
# If not already installed:
/plugin install cc-skills

# Configure the status line
/statusline-tools:setup install
```

## Commands

### /statusline-tools:setup

```bash
/statusline-tools:setup install    # Install status line to settings.json
/statusline-tools:setup uninstall  # Remove status line from settings.json
/statusline-tools:setup status     # Show current configuration
```

### /statusline-tools:ignore

Manage global ignore patterns for `lint-relative-paths`. Use this when a repository intentionally uses relative paths (e.g., marketplace plugins).

```bash
/statusline-tools:ignore add my-repo     # Add pattern to global ignore
/statusline-tools:ignore list            # Show current patterns
/statusline-tools:ignore remove my-repo  # Remove pattern
```

**Pattern matching**: Substring match - pattern `research-repo` matches paths like `/Users/user/eon/research-repo.worktree-feature`.

**Ignore file location**: `~/.claude/lint-relative-paths-ignore`

## Status Line Display

The status line outputs three lines:

**Line 1**: Repository path, git indicators, local time

```
repo-name/path | M:0 D:0 S:0 U:0 ↑:0 ↓:0 ≡:0 ⚠:0 | 25Jan07 14:32L
```

**Line 2**: GitHub URL (or warning), UTC time

```
https://github.com/user/repo/tree/branch | 25Jan07 14:32Z
```

**Line 3**: ~/.claude/projects JSONL ID

```
~/.claude/projects JSONL ID: abc12345-def4-5678-90ab-cdef12345678
```

### Indicators

| Indicator | Meaning                   | Color When Active |
| --------- | ------------------------- | ----------------- |
| M:n       | Modified files (unstaged) | Yellow            |
| D:n       | Deleted files (unstaged)  | Yellow            |
| S:n       | Staged files (for commit) | Yellow            |
| U:n       | Untracked files           | Yellow            |
| ↑:n       | Commits ahead of remote   | Yellow            |
| ↓:n       | Commits behind remote     | Yellow            |
| ≡:n       | Stash count               | Yellow            |
| ⚠:n       | Merge conflicts           | Red               |

### Color Scheme

- **Green**: Repository path
- **Magenta**: Feature branch name
- **Gray**: Main/master branch, zero-value indicators
- **Yellow**: Non-zero change indicators
- **Red**: Merge conflicts

## Dependencies

### System Dependencies

| Tool | Required | Installation                             |
| ---- | -------- | ---------------------------------------- |
| bash | Yes      | Built-in                                 |
| jq   | Yes      | `brew install jq`                        |
| git  | Yes      | Built-in on macOS                        |
| bun  | Yes      | `brew install oven-sh/bun/bun` or bun.sh |

## How It Works

**Status Line Script**: Reads Claude Code's status JSON from stdin, queries git for repository state, and outputs a formatted status line.

## Files

```
statusline-tools/
├── commands/
│   └── setup.md                  # /statusline-tools:setup command
├── statusline/
│   └── custom-statusline.sh      # Status line renderer
├── scripts/
│   └── manage-statusline.sh      # Install/uninstall statusLine
└── tests/
    └── test_statusline.bats      # Status line tests
```

## Testing

```bash
# Install bats-core
brew install bats-core

# Run all tests
bats tests/

# Run specific test file
bats tests/test_statusline.bats
```

## Troubleshooting

| Issue                   | Cause          | Solution                              |
| ----------------------- | -------------- | ------------------------------------- |
| Status line not showing | Not configured | Run `/statusline-tools:setup install` |

## Credits

- Original status line concept inspired by [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)

## License

MIT License - See [LICENSE](./LICENSE) for details.
