# statusline-tools

Custom Claude Code status line with git status, link validation, and path linting indicators.

## Skills

| Skill          | Description                                       |
| -------------- | ------------------------------------------------- |
| `session-info` | Get current Claude Code session UUID and registry |

**Trigger phrases:** "current session", "session uuid", "session id", "what session"

## Features

- **Git Status Indicators**: M (modified), D (deleted), S (staged), U (untracked)
- **Remote Tracking**: ↑ (ahead), ↓ (behind)
- **Repository State**: ≡ (stash count), ⚠ (merge conflicts)
- **Link Validation**: L (broken links via lychee)
- **Path Linting**: P (path violations via lint-relative-paths)
- **GitHub URL**: Clickable link to current branch

## Installation

```bash
# The plugin is part of cc-skills marketplace
# If not already installed:
/plugin install cc-skills

# Install dependencies (lychee for link validation)
/statusline-tools:setup deps

# Configure the status line
/statusline-tools:setup install

# Optional: Install the Stop hook (for link validation cache)
/statusline-tools:hooks install
```

## Commands

### /statusline-tools:setup

```bash
/statusline-tools:setup install    # Install status line to settings.json
/statusline-tools:setup uninstall  # Remove status line from settings.json
/statusline-tools:setup status     # Show current configuration
/statusline-tools:setup deps       # Install lychee via mise
```

### /statusline-tools:hooks

```bash
/statusline-tools:hooks install    # Add Stop hook for link validation
/statusline-tools:hooks uninstall  # Remove Stop hook
/statusline-tools:hooks status     # Show hook configuration
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

## Status Line Display

The status line outputs three lines:

**Line 1**: Repository path, git indicators, local time

```
repo-name/path | M:0 D:0 S:0 U:0 ↑:0 ↓:0 ≡:0 ⚠:0 | L:0 P:0 | 25Jan07 14:32L
```

**Line 2**: GitHub URL (or warning), UTC time

```
https://github.com/user/repo/tree/branch | 25Jan07 14:32Z
```

**Line 3**: Session UUID

```
Session UUID: abc12345-def4-5678-90ab-cdef12345678
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
| L:n       | Broken links (lychee)     | Red               |
| P:n       | Path violations           | Red               |

### Color Scheme

- **Green**: Repository path
- **Magenta**: Feature branch name
- **Gray**: Main/master branch, zero-value indicators
- **Yellow**: Non-zero change indicators
- **Red**: Conflicts, broken links, path violations

## Dependencies

### System Dependencies

| Tool   | Required | Installation                                |
| ------ | -------- | ------------------------------------------- |
| bash   | Yes      | Built-in                                    |
| jq     | Yes      | `brew install jq`                           |
| git    | Yes      | Built-in on macOS                           |
| bun    | Yes      | `brew install oven-sh/bun/bun` or bun.sh    |
| lychee | Optional | `mise install lychee` (for link validation) |

### npm Dependencies (for lint-relative-paths)

The `lint-relative-paths` script is implemented in TypeScript and requires npm packages:

| Package          | Purpose                                       |
| ---------------- | --------------------------------------------- |
| simple-git       | Git operations (git ls-files, repo detection) |
| remark-parse     | Markdown AST parsing                          |
| unified          | AST processor                                 |
| unist-util-visit | AST traversal for link extraction             |

**Post-installation step**: After installing the plugin, run:

```bash
cd ~/.claude/plugins/cache/cc-skills/statusline-tools/<version>
bun install --frozen-lockfile
```

This installs the npm dependencies needed for the TypeScript linter.

## How It Works

1. **Status Line Script**: Reads Claude Code's status JSON from stdin, queries git for repository state, reads cached validation results, and outputs a formatted status line.

2. **Stop Hook**: Runs at session end to validate markdown links (lychee) and check path formatting (lint-relative-paths). Results are cached in `.lychee-results.json` and `.lint-relative-paths-results.txt` at the git root.

3. **lint-relative-paths**: TypeScript-based linter that enforces repository-relative path conventions in markdown files.

### .gitignore Respect

Both validators use `git ls-files` to scan only **tracked files**, automatically respecting `.gitignore`. This prevents false positives from:

- Cloned repositories (`repos/`, `vendor/`)
- Build artifacts (`target/`, `dist/`, `build/`)
- Dependencies (`node_modules/`, `.venv/`)
- Cache directories (`.cache/`, `coverage/`)

**Fallback behavior**: If not in a git repository, the validators use directory walking with an expanded exclusion list.

## Files

```
statusline-tools/
├── commands/
│   ├── setup.md                  # /statusline-tools:setup command
│   ├── hooks.md                  # /statusline-tools:hooks command
│   └── ignore.md                 # /statusline-tools:ignore command
├── statusline/
│   └── custom-statusline.sh      # Status line renderer
├── hooks/
│   └── lychee-stop-hook.sh       # Link validation Stop hook
├── scripts/
│   ├── manage-statusline.sh      # Install/uninstall statusLine
│   ├── manage-hooks.sh           # Install/uninstall Stop hook
│   ├── manage-ignore.sh          # Manage global ignore patterns
│   └── lint-relative-paths       # Bundled path linter
└── tests/
    ├── test_statusline.bats      # Status line tests
    ├── test_stop_hook.bats       # Stop hook tests
    └── test_lint_relative.bats   # Path linter tests
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

## Credits

- Original status line concept inspired by [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)
- Link validation powered by [lychee](https://github.com/lycheeverse/lychee)

## License

MIT License - See [LICENSE](./LICENSE) for details.
