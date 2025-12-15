# Link Checker Plugin

Universal link validation for Claude Code sessions using [lychee](https://github.com/lycheeverse/lychee).

**ADR**: [Link Checker Plugin Extraction](../../docs/adr/2025-12-11-link-checker-plugin-extraction.md)

## Features

- **Lychee Integration**: Validates markdown links at session end
- **Path Policy Linting**: Detects absolute paths and excessive parent traversal
- **JSON Output**: Programmatic results for integration with other tools
- **Configurable**: Cascade config resolution (repo -> workspace -> plugin default)
- **ULID Tracing**: Correlation IDs for debugging across systems

## Installation

This plugin is part of the cc-skills marketplace. Install via:

```bash
# From cc-skills marketplace
claude /plugin install cc-skills
```

Or add to your Claude Code settings manually.

## Requirements

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (Python package manager)
- [lychee](https://github.com/lycheeverse/lychee) (optional, for link validation)

Install lychee:

```bash
# macOS
brew install lychee

# Cargo
cargo install lychee
```

## Usage

The plugin runs automatically at session end (Stop hook). No manual invocation needed.

### Output

Results are output as JSON to stdout:

```json
{
  "status": "pass",
  "error_count": 0,
  "lychee_errors": 0,
  "path_violations": 0,
  "correlation_id": "01JEGQXV8KHTNF3YD8G7ZC9XYK",
  "results_file": "/path/to/workspace/.link-check-results.md"
}
```

### Status Values

| Status    | Meaning                               |
| --------- | ------------------------------------- |
| `pass`    | No errors found                       |
| `fail`    | Broken links or path violations found |
| `skipped` | Validation skipped (loop prevention)  |
| `error`   | Execution error (invalid input, etc.) |

## Configuration

### Lychee Config

The plugin searches for lychee configuration in this order:

1. `{workspace}/.lycheerc.toml`
2. `{workspace}/lychee.toml`
3. `~/.claude/.lycheerc.toml`
4. Plugin default (`config/lychee.toml`)

### Path Policy Rules

| Rule                 | Severity | Description                                |
| -------------------- | -------- | ------------------------------------------ |
| NO_ABSOLUTE_PATHS    | Error    | `/Users/...` or `/home/...` paths detected |
| NO_PARENT_ESCAPES    | Warning  | Excessive `../` traversal (5+ levels)      |
| MARKETPLACE_RELATIVE | Warning  | Plugin files should use relative paths     |

## Manual Testing

Test the hook directly:

```bash
cd /path/to/workspace
echo '{"cwd": "'"$(pwd)"'"}' | uv run ~/.claude/plugins/marketplaces/cc-skills/plugins/link-checker/hooks/stop-link-check.py
```

## Architecture

```text
plugins/link-checker/
  plugin.json           # Plugin manifest
  hooks/
    hooks.json          # Hook configuration (Stop event)
    stop-link-check.py  # Main hook script (PEP 723)
  lib/
    __init__.py
    ulid_gen.py         # ULID generation
    lychee_runner.py    # Lychee subprocess wrapper
    path_linter.py      # Path policy validation
  config/
    lychee.toml         # Default lychee configuration
```

## Integration

### With claude-orchestrator

The orchestrator can consume plugin output by:

1. Reading JSON from hook stdout
2. Reading `.link-check-results.md` for details
3. Correlating via ULID

### With Other Tools

JSON output enables integration with:

- CI/CD pipelines
- Notification systems (Telegram, Slack)
- Issue trackers (GitHub Issues)

## License

MIT
