# link-tools

Comprehensive link validation for Claude Code: portability checks, lychee broken link detection, and path policy linting.

Merged from `link-validator` + `link-checker` plugins.

## Skills

| Skill             | Description                                                     |
| ----------------- | --------------------------------------------------------------- |
| `link-validator`  | Validate markdown link portability (relative vs absolute paths) |
| `link-validation` | Lychee broken link detection with path policy linting           |

## Installation

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install link-tools@cc-skills
```

## Hooks

| Hook                 | Event | Timeout | Description                                 |
| -------------------- | ----- | ------- | ------------------------------------------- |
| `stop-link-check.py` | Stop  | 60s     | Validates links at session end using lychee |

### Stop Hook: Session-End Link Validation

Runs automatically when Claude stops responding:

1. Scans markdown files in the current repository
2. Validates links with lychee (offline mode by default)
3. Reports broken links and path policy violations

Uses `uv run` for Python dependency management.

**Trigger phrases:**

- "check links", "validate portability", "fix broken links" → link-validator
- "lychee", "broken link detection", "path policy" → link-validation

## Usage

```bash
# Validate link portability in a directory
uv run plugins/link-tools/scripts/validate_links.py ./skills/

# The Stop hook runs automatically at session end
```

## Features

### Link Portability (link-validator)

- Detects absolute filesystem paths (`/Users/...`)
- Validates relative path usage in plugins
- Ensures links work after installation to `~/.claude/skills/`

### Broken Link Detection (link-validation)

- Uses lychee for fast link checking
- Offline mode (local files only)
- Path policy linting (NO_ABSOLUTE_PATHS, NO_PARENT_ESCAPES)
- ULID correlation IDs for tracing

## Configuration

Override lychee config by placing `.lycheerc.toml` in your workspace root.

See [config/lychee.toml](./config/lychee.toml) for defaults.

## Scripts

| Script              | Purpose                               |
| ------------------- | ------------------------------------- |
| `validate_links.py` | Standalone link portability validator |

## References

- [ADR: Link Checker Plugin Extraction](/docs/adr/2025-12-11-link-checker-plugin-extraction.md)

## License

MIT
