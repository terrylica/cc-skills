# link-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../../LICENSE)
![Skills](https://img.shields.io/badge/Skills-2-blue.svg)
![Hooks](https://img.shields.io/badge/Hooks-0-gray.svg)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)

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

**Trigger phrases:**

- "check links", "validate portability", "fix broken links" → link-validator
- "lychee", "broken link detection", "path policy" → link-validation

## Usage

```bash
# Validate link portability in a directory
uv run plugins/link-tools/scripts/validate_links.py ./skills/

# Offline link check over every markdown file (cc-skills repo)
moon run repo:link-check        # or: bash tasks/link-check.sh

# Run link validation on demand via skill
/link-tools:link-validation
```

## Features

### Link Portability (link-validator)

- Detects absolute filesystem paths (`/Users/...`)
- Validates relative path usage in plugins
- Ensures links still resolve after install, under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/` — the version segment changes every release, so absolute paths rot

### Broken Link Detection (link-validation)

- Uses lychee for fast link checking: relative links, root-relative links and `#anchors`
- Offline mode (local files only), so the verdict is deterministic
- In cc-skills the check is `tasks/link-check.sh`, part of `moon run repo:check`

## Configuration

lychee reads `lychee.toml` from the workspace root. cc-skills keeps exactly one, [`lychee.toml`](../../lychee.toml), shared by `tasks/link-check.sh` and the statusline-tools Stop hook.

## Scripts

| Script              | Purpose                               |
| ------------------- | ------------------------------------- |
| `validate_links.py` | Standalone link portability validator |

## Troubleshooting

| Issue            | Cause                      | Solution                                                        |
| ---------------- | -------------------------- | --------------------------------------------------------------- |
| lychee not found | Not installed              | `brew install lychee`                                           |
| False positives  | Exclude patterns missing   | Add patterns to the `exclude` list in `lychee.toml`             |
| Timeout errors   | Network issues             | Use `--offline` flag for local-only validation                  |
| Path violations  | Absolute paths in markdown | Convert to relative paths: `./file.md` not `/full/path/file.md` |

## Dependencies

| Component | Required | Installation                  |
| --------- | -------- | ----------------------------- |
| lychee    | Yes      | `brew install lychee`         |
| Python    | Yes      | 3.11+ via `uv python install` |
| uv        | Yes      | `brew install uv`             |

## References

- [ADR: Link Checker Plugin Extraction](/docs/adr/2025-12-11-link-checker-plugin-extraction.md)

## License

MIT
