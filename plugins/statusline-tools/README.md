# statusline-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) ![Skills](https://img.shields.io/badge/Skills-4-blue.svg) ![Hooks](https://img.shields.io/badge/Hooks-2-blue.svg) ![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)

Custom Claude Code status line with git status indicators.

## Skills

| Skill          | Description                                                         |
| -------------- | ------------------------------------------------------------------- |
| `setup`        | Install/uninstall/status for statusline + dependencies              |
| `ignore`       | Manage global ignore patterns for lint-relative-paths               |
| `session-info` | Display current session UUID, chain, registry info                  |
| `tether`       | Install/uninstall link validation stop hooks (renamed from `hooks`) |

**Trigger phrases:** "current session", "session uuid", "session id", "what session"

## Features

- **Git Status Indicators**: M (modified), D (deleted), S (staged), U (untracked)
- **Remote Tracking**: ↑ (ahead), ↓ (behind)
- **Repository State**: ≡ (stash count), ⚠ (merge conflicts)
- **GitHub URL**: Clickable link to current branch

### Optional: admission-gateway health

If your Claude Code traffic goes through an admission gateway that serves inference from a rotating pool of upstream accounts, the status line can show that gateway's health inline: pool ratio, forward-path health glyph, and your client wrapper's version against the gateway's minimum.

This is **opt-in and off by default.** With nothing configured, the segment makes no network request, writes no files, and renders nothing. Point `STATUSLINE_GATEWAY_BASE_URL` at a gateway exposing `GET /v1/router-status` to enable it; see the "OPTIONAL INTEGRATION SEAM" comment block at the top of `statusline/custom-statusline.sh` for the full list of environment variables.

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

### /statusline-tools:tether

Install or uninstall link validation stop hooks.

```bash
/statusline-tools:tether install    # Install link validation hooks
/statusline-tools:tether uninstall  # Remove link validation hooks
```

## Status Line Display

Lines, top to bottom. Each has a name for `STATUSLINE_HIDE` (below); a line whose data is absent is simply omitted.

| Name       | Line                                                                  | Example                                                                   |
| ---------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `git`      | ccmax group (when the wrapper sets it) + git indicators + release     | `eon \| M:0 D:0 S:0 U:0 ↑:0 ↓:0 ≡:0 ⚠:0 \| v3.55.10 16h ago`              |
| `code`     | Code statistics (scc): LOC, files, complexity, languages, COCOMO      | `Σ 210k LOC · 1.2k files · cx 30k · Go 33% Py 21% MD 14% · ~$7.4M COCOMO` |
| `model`    | Model id, effort, thinking + Claude Code version                      | `claude-opus-5-5[1m] · medium · thinking:true \| 2.1.308`                 |
| `ctx`      | Context window bar                                                    | `ctx ▕██████········\|≈≈≈≈≈≈▏ 30% · 300k/1M · ~414k until compact`        |
| `datetime` | UTC + local time (with `gateway`: optional gateway health, same line) | `Thu 22 Oct 2026 20:46 UTC \| 13:46 PDT \| gateway 9/9 ✓ 3.55.10`         |
| `repo`     | Repo path + GitHub URL (visibility)                                   | `~/eon/cc-skills \| https://github.com/user/repo (public)`                |
| `session`  | Claude Code session JSONL ID                                          | `~/.claude/projects JSONL ID: abc12345-def4-5678-90ab-cdef12345678`       |
| `cast`     | Asciinema cast UUID                                                   | `~/asciinemalogs cast: def45678-abcd-1234-5678-abcdef123456`              |
| `cron`     | Active cron jobs, one line each                                       |                                                                           |

### Hiding segments — `STATUSLINE_HIDE`

Set a comma-separated list of the names above to leave them out, for example in `~/.claude/settings.json`:

```json
{ "env": { "STATUSLINE_HIDE": "code,datetime,gateway" } }
```

- Hiding `code` also skips running scc; hiding `gateway` switches the gateway feature off entirely (no probe, no cache file, no telemetry), as if it were not configured.
- The datetime line disappears only when both `datetime` and `gateway` are hidden; hiding just `datetime` leaves the gateway health on its own line.
- Unknown names are ignored, so a typo never breaks the render. Unset means everything shows, as before.

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
