# statusline-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-4-blue.svg)]()
[![Hooks](https://img.shields.io/badge/Hooks-2-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Custom Claude Code status line with git status indicators.

## Skills

| Skill          | Description                                            |
| -------------- | ------------------------------------------------------ |
| `setup`        | Install/uninstall/status for statusline + dependencies |
| `ignore`       | Manage global ignore patterns for lint-relative-paths  |
| `session-info` | Display current session UUID, chain, registry info     |
| `hooks`        | Install/uninstall link validation stop hooks           |

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

**Pattern matching**: Substring match - pattern `alpha-forge` matches paths like `/Users/user/eon/alpha-forge.worktree-feature`.

**Ignore file location**: `~/.claude/lint-relative-paths-ignore`

### /statusline-tools:hooks

Install or uninstall link validation stop hooks.

```bash
/statusline-tools:hooks install    # Install link validation hooks
/statusline-tools:hooks uninstall  # Remove link validation hooks
```

## Status Line Display

The status line outputs 5 lines (plus optional cron lines):

**Line 1**: Git indicators + version tag + release age

```
M:0 D:0 S:0 U:0 ↑:0 ↓:0 ≡:0 ⚠:0 | v<version> | 2d ago
```

**Line 2**: Datetime (UTC + local TZ) + ccmax account usage

```
Tue 04 Mar 2026 23:36 UTC | 15:36 PST | ccmax: 42%
```

**Line 3**: Repo path + GitHub URL (public/private badge)

```
~/eon/cc-skills | https://github.com/user/repo [public]
```

**Line 4**: Session UUID + chain

```
Session: abc12345-def4-5678-90ab-cdef12345678 | chain: 3
```

**Line 5**: Asciinema cast UUID

```
Cast: def45678-abcd-1234-5678-abcdef123456
```

**Additional lines**: Active cron jobs (if any)

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

| Tool     | Required | Installation                             |
| -------- | -------- | ---------------------------------------- |
| bash     | Yes      | Built-in                                 |
| jq       | Yes      | `brew install jq`                        |
| git      | Yes      | Built-in on macOS                        |
| bun      | Yes      | `brew install oven-sh/bun/bun` or bun.sh |
| python3  | Yes      | Built-in on macOS                        |
| curl     | Yes      | Built-in on macOS                        |
| security | Yes      | Built-in (macOS Keychain)                |
| gh       | Yes      | `brew install gh`                        |
| gtimeout | Yes      | `brew install coreutils`                 |

## How It Works

**Status Line Script**: Reads Claude Code's status JSON from stdin, queries git for repository state, and outputs a formatted status line.

## Files

```
plugins/statusline-tools/
├── CLAUDE.md                    ← Plugin docs hub
├── README.md                    ← This file
├── hooks/
│   ├── hooks.json               ← Hook registration
│   ├── cron-tracker.ts          ← PostToolUse: tracks CronCreate/Delete/List
│   ├── stop-cron-gc.ts          ← Stop: prunes stale cron entries
│   └── lychee-stop-hook.sh      ← Link validation (installed via manage-hooks.sh)
├── lib/
│   ├── config.ts                ← Session registry config loader
│   ├── session-registry.ts      ← Session chain persistence
│   ├── chain-formatter.ts       ← ANSI session ID formatting
│   ├── path-encoder.ts          ← Project path encoding
│   └── logger.ts                ← NDJSON structured logging
├── scripts/
│   ├── manage-statusline.sh     ← Install/uninstall/status
│   ├── manage-hooks.sh          ← Hook install/uninstall
│   ├── manage-ignore.sh         ← Global ignore patterns
│   ├── get-session-info.ts      ← Session info display
│   ├── update-session-registry.ts
│   ├── session-chain.ts         ← Session ancestry chain
│   ├── lint-relative-paths.ts   ← Link validation linter
│   ├── lint-relative-paths      ← Compiled bash wrapper
│   └── iterm2-cron-countdown.py ← iTerm2 cron component
├── skills/
│   ├── setup/SKILL.md
│   ├── ignore/SKILL.md
│   ├── session-info/SKILL.md
│   └── hooks/SKILL.md
├── statusline/
│   └── custom-statusline.sh     ← Main statusline script
├── tests/
│   ├── test_statusline.bats
│   ├── test_lint_relative.bats
│   └── test_stop_hook.bats
└── types/
    └── session.d.ts
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
