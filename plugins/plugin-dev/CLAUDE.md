# plugin-dev Plugin

> Plugin and skill development: structure validation, silent failure auditing, skill architecture meta-skill with TodoWrite templates.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp CLAUDE.md](../itp/CLAUDE.md)

## Skills

- [create](./skills/create/SKILL.md)
- [plugin-validator](./skills/plugin-validator/SKILL.md)
- [skill-architecture](./skills/skill-architecture/SKILL.md)

## Commands

| Command              | Purpose                                                           |
| -------------------- | ----------------------------------------------------------------- |
| `/plugin-dev:create` | Create a new plugin with full workflow (ADR, validation, release) |

## Validator Scripts (TypeScript/Bun)

| Script               | Purpose                                            |
| -------------------- | -------------------------------------------------- |
| `validate-skill.ts`  | Comprehensive skill validation (11+ checks)        |
| `validate-links.ts`  | Markdown link portability (strict `/docs/` policy) |
| `fix-bash-blocks.ts` | Auto-fix bash blocks for zsh compatibility         |

## Conventions

- **5 TodoWrite Templates** (A-E) for different skill creation scenarios
- **YAML Frontmatter** standards (name, description, allowed-tools)
- **Progressive Disclosure** patterns (SKILL.md + references/)
- **Bash Compatibility** heredoc wrappers for zsh
