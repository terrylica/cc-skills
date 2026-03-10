# link-tools Plugin

> Comprehensive link validation: portability checks, lychee broken link detection, path policy linting.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gh-tools CLAUDE.md](../gh-tools/CLAUDE.md)

## Skills

| Skill             | Purpose                                                         |
| ----------------- | --------------------------------------------------------------- |
| `link-validator`  | Validate markdown link portability (relative vs absolute paths) |
| `link-validation` | Lychee broken link detection with path policy linting           |

## Conventions

- Merged from `link-validator` + `link-checker` plugins
- Uses `uv run` for Python dependency management
- Override config via `.lycheerc.toml` in workspace root
