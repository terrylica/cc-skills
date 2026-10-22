# link-tools Plugin

> Comprehensive link validation: portability checks, lychee broken link detection, path policy linting.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gh-tools CLAUDE.md](../gh-tools/CLAUDE.md)

## Skills

- [link-validation](./skills/link-validation/SKILL.md)
- [link-validator](./skills/link-validator/SKILL.md)

## Conventions

- Merged from `link-validator` + `link-checker` plugins
- Uses `uv run` for Python dependency management
- No hooks: link-tools has no `hooks.json`. The link check that runs is `tasks/link-check.sh` (`moon run repo:link-check`), configured by the root `lychee.toml`
