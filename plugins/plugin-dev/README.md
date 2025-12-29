# plugin-dev

Plugin and skill development tools for Claude Code marketplace.

## Commands

| Command              | Description                                                       |
| -------------------- | ----------------------------------------------------------------- |
| `/plugin-dev:create` | Create a new plugin with full workflow (ADR, validation, release) |

## Skills

| Skill                | Description                                                         |
| -------------------- | ------------------------------------------------------------------- |
| `plugin-validator`   | Validate plugin structure, manifests, and silent failure patterns   |
| `skill-architecture` | Meta-skill for creating Claude Code skills with TodoWrite templates |

## Usage

```bash
# Create a new plugin
/plugin-dev:create my-plugin

# Validate a plugin for silent failures
/plugin-dev:plugin-validator plugins/my-plugin/

# Create a new skill (invoke the skill-architecture meta-skill)
/plugin-dev:skill-architecture
```

## Plugin Validator

### Validation Checks

- **Structure**: Plugin directory exists, plugin.json valid, required fields present
- **Silent Failures**: Hook entry points must emit to stderr on failure
- **Shellcheck**: Shell scripts checked for common issues
- **Python Exceptions**: `except: pass` must emit to stderr

### Integration

Invoked by `/plugin-dev:create` during Phase 3 validation.

## Skill Architecture

The `skill-architecture` skill provides:

- **5 TodoWrite Templates** (A-E) for different skill creation scenarios
- **YAML Frontmatter** standards (name, description, allowed-tools)
- **Progressive Disclosure** patterns (SKILL.md + references/)
- **Security Practices** (tool restrictions, input validation)
- **Bash Compatibility** patterns (heredoc wrappers for zsh)

### Validator Scripts (TypeScript/Bun)

| Script               | Purpose                                           |
| -------------------- | ------------------------------------------------- |
| `validate-skill.ts`  | Comprehensive skill validation (11+ checks)       |
| `validate-links.ts`  | Markdown link portability (strict `/docs/` policy)|
| `fix-bash-blocks.ts` | Auto-fix bash blocks for zsh compatibility        |

Run scripts with:

```bash
# Marketplace plugins (strict validation)
bun run plugins/plugin-dev/scripts/validate-skill.ts <skill-path>

# Project-local skills (auto-detected, relaxed link rules)
bun run plugins/plugin-dev/scripts/validate-skill.ts .claude/skills/<skill>/

# Skip bash checks for documentation-only skills
bun run plugins/plugin-dev/scripts/validate-skill.ts <path> --skip-bash

# Other validators
bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
bun run plugins/plugin-dev/scripts/fix-bash-blocks.ts <path> [--dry]
```
