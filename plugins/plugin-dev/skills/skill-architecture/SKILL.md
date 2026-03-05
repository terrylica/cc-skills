---
name: skill-architecture
description: Meta-skill for creating Claude Code skills. TRIGGERS - create skill, YAML frontmatter, validate skill, skill architecture, lifecycle pattern, suite pattern, phased execution, command vs skill.
---

# Skill Architecture

Comprehensive guide for creating effective Claude Code skills following Anthropic's official standards with emphasis on security, CLI-specific features, and progressive disclosure architecture.

> **Scope**: Claude Code CLI Agent Skills (`~/.claude/skills/`), not Claude.ai API skills

## When to Use This Skill

Use this skill when:

- Creating new Claude Code skills from scratch
- Learning skill YAML frontmatter and structure requirements
- Validating skill file format and portability
- Understanding progressive disclosure patterns for skills

---

## Task Templates

**MANDATORY**: Select and load the appropriate template before any skill work.

See [Task Templates](./references/task-templates.md) for all templates (A-F) and the quality checklist.

| Template | Purpose                           |
| -------- | --------------------------------- |
| A        | Create New Skill                  |
| B        | Update Existing Skill             |
| C        | Add Resources to Skill            |
| D        | Convert to Self-Evolving Skill    |
| E        | Troubleshoot Skill Not Triggering |
| F        | Create Lifecycle Suite            |

---

## Post-Change Checklist (Self-Maintenance)

After modifying THIS skill (skill-architecture):

1. [ ] Templates and 6 Steps tutorial remain aligned
2. [ ] Skill Quality Checklist reflects current best practices
3. [ ] All referenced files in references/ exist
4. [ ] Append changes to [evolution-log.md](./references/evolution-log.md)
5. [ ] Update user's CLAUDE.md if triggers changed

---

## Continuous Improvement

Skills must actively evolve. When you notice friction, missing edge cases, better patterns, or repeated manual steps -- **update immediately**: pause, fix SKILL.md or resources, log in evolution-log.md, resume.

**Do NOT update immediately**: major structural changes (discuss first), speculative improvements without evidence.

After completing any skill-assisted task, ask: _"Did anything feel suboptimal? What would help next time?"_ If yes, update now.

---

## About Skills

Skills are modular, self-contained packages that extend Claude's capabilities with specialized knowledge, workflows, and tools. Think of them as "onboarding guides" for specific domains -- transforming Claude from general-purpose to specialized agent with procedural knowledge no model fully possesses.

### What Skills Provide

1. **Specialized workflows** - Multi-step procedures for specific domains
2. **Tool integrations** - Instructions for working with specific file formats or APIs
3. **Domain expertise** - Company-specific knowledge, schemas, business logic
4. **Bundled resources** - Scripts, references, assets for complex/repetitive tasks

### Skill Discovery and Precedence

Skills are discovered from multiple locations. When names collide, higher-precedence wins:

1. **Enterprise** (managed settings) -- highest
2. **Personal** (`~/.claude/skills/`)
3. **Project** (`.claude/skills/` in repo)
4. **Plugin** (namespaced: `plugin:skill-name`)
5. **Nested** (monorepo `.claude/skills/` in subdirectories -- auto-discovered)
6. **`--add-dir`** (CLI flag, live change detection) -- lowest

**Management commands**:

- `claude plugin enable <name>` / `claude plugin disable <name>` -- toggle plugins
- `claude skill list` -- show all discovered skills with source location

**Monorepo support**: Claude Code automatically discovers `.claude/skills/` directories in nested project roots within a monorepo. No configuration needed.

---

## cc-skills Plugin Architecture

> This section applies specifically to the **cc-skills marketplace** plugin structure. Generic standalone skills are unaffected.

### Canonical Structure

```
plugins/<plugin>/
└── skills/
    └── <skill-name>/
        └── SKILL.md   <- single canonical file (context AND user-invocable)
```

`skills/<name>/SKILL.md` is the **single source of truth**. The separate `commands/` layer was eliminated -- it required maintaining two identical files per skill and caused `Skill()` invocations to return "Unknown skill". See [migration issue](https://github.com/terrylica/cc-skills/issues/26) for full context.

### How Skills Become Slash Commands

Two install paths, both supported:

| Path                    | Mechanism                                                                                                                             | Notes                                                                                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Automated (primary)** | `mise run release:full` -> `sync-commands-to-settings.sh` reads `skills/*/SKILL.md` -> writes `~/.claude/commands/<plugin>:<name>.md` | Fully automated post-release. Bypasses Anthropic cache bugs [#17361](https://github.com/anthropics/claude-code/issues/17361), [#14061](https://github.com/anthropics/claude-code/issues/14061) |
| **Official CLI**        | `claude plugin install itp@cc-skills` -> reads from `skills/` in plugin cache                                                         | Cache may not refresh on update -- use `claude plugin update` after new releases                                                                                                               |

### Hooks

`sync-hooks-to-settings.sh` reads `hooks/hooks.json` directly -> merges into `~/.claude/settings.json`. Bypasses path re-expansion bug [#18517](https://github.com/anthropics/claude-code/issues/18517).

### Creating a New Skill in cc-skills

Place the SKILL.md under `plugins/<plugin>/skills/<name>/SKILL.md`. No `commands/` copy needed. The validator (`bun scripts/validate-plugins.mjs`) checks frontmatter completeness.

---

## Skill Creation Process

See [Creation Tutorial](./references/creation-tutorial.md) for the detailed 6-step walkthrough, or [Creation Workflow](./references/creation-workflow.md) for the comprehensive guide with examples.

**Quick summary**: Gather requirements -> Plan resources -> Initialize -> Edit SKILL.md -> Validate -> Register and iterate.

---

## Skill Anatomy

```
skill-name/
├── SKILL.md                      # Required: YAML frontmatter + instructions
├── scripts/                      # Optional: Executable code (Python/Bash)
├── references/                   # Optional: Documentation loaded as needed
│   └── evolution-log.md          # Recommended: Change history (self-evolving)
└── assets/                       # Optional: Files used in output
```

### YAML Frontmatter (Required)

See [YAML Frontmatter Reference](./references/yaml-frontmatter.md) for the complete field reference, invocation control table, permission rules, description guidelines, and YAML pitfalls.

**Minimal example**:

```yaml
---
name: my-skill
description: Does X when user mentions Y. Use for Z workflows.
---
```

**Key rules**: `name` is lowercase-hyphen, `description` is single-line max 1024 chars with trigger keywords, no colons in description text.

### Progressive Disclosure (3 Levels)

Skills use progressive loading to manage context efficiently:

1. **Metadata** (name + description) - Always in context (~100 words)
2. **SKILL.md body** - When skill triggers (<5k words)
3. **Bundled resources** - As needed by Claude (unlimited\*)

\*Scripts can execute without reading into context.

### Skill Description Budget

Skills are loaded into the context window based on description relevance. Large skills may be **excluded** if the budget is exceeded:

- **Budget**: ~2% of context window (16K character fallback)
- **Check**: Run `/context` to see which skills are loaded vs excluded
- **Override**: Set `SLASH_COMMAND_TOOL_CHAR_BUDGET` env var to increase budget
- **Mitigation**: Keep SKILL.md body lean, move detail to `references/`

---

## Bundled Resources

Skills can include `scripts/`, `references/`, and `assets/` directories. See [Progressive Disclosure](./references/progressive-disclosure.md) for detailed guidance on when to use each.

---

## CLI-Specific Features

CLI skills support `allowed-tools` for granting tool access without per-use approval. See [Security Practices](./references/security-practices.md) for details.

### String Substitutions

Skill bodies support these substitutions (resolved at load time):

| Variable               | Resolves To                                 | Example               |
| ---------------------- | ------------------------------------------- | --------------------- |
| `$ARGUMENTS`           | Full argument string from `/name arg1 arg2` | `Process: $ARGUMENTS` |
| `$ARGUMENTS[N]`        | Nth argument (0-indexed)                    | `File: $ARGUMENTS[0]` |
| `$N`                   | Shorthand for `$ARGUMENTS[N]`               | `$0` = first arg      |
| `${CLAUDE_SESSION_ID}` | Current session UUID                        | Log correlation       |

### Dynamic Context Injection

Use the pattern `!` + `` `command` `` (exclamation mark followed by a backtick-wrapped command) in skill body to inject command output at load time:

```
Current branch: <exclamation>`git branch --show-current`
Last commit: <exclamation>`git log -1 --oneline`
```

(Replace `<exclamation>` with `!` in actual usage.)

The command runs when the skill loads -- output replaces the pattern inline.

### Extended Thinking

Include the keyword `ultrathink` in a skill body to enable extended thinking mode for that skill's execution.

---

## Structural Patterns

See [Structural Patterns](./references/structural-patterns.md) for detailed guidance on:

1. **Workflow Pattern** - Sequential multi-step procedures
2. **Task Pattern** - Specific, bounded tasks
3. **Reference Pattern** - Knowledge repository
4. **Capabilities Pattern** - Tool integrations
5. **Suite Pattern** - Multi-skill lifecycle management (bootstrap, operate, diagnose, configure, upgrade, teardown)

---

## User Conventions Integration

This skill follows common user conventions:

- **Absolute paths**: Always use full paths (terminal Cmd+click compatible)
- **Unix-only**: macOS, Linux (no Windows support)
- **Python**: `uv run script.py` with PEP 723 inline dependencies
- **Planning**: OpenAPI 3.1.1 specs when appropriate

---

## Marketplace Scripts

See [Scripts Reference](./references/scripts-reference.md) for marketplace script usage.

---

## Reference Documentation

For detailed information, see:

- [Task Templates](./references/task-templates.md) - Templates A-F and quality checklist
- [Creation Tutorial](./references/creation-tutorial.md) - 6-step creation process walkthrough
- [YAML Frontmatter](./references/yaml-frontmatter.md) - Field reference, invocation control, description guidelines
- [Structural Patterns](./references/structural-patterns.md) - 5 skill architecture patterns (including Suite Pattern)
- [Workflow Patterns](./references/workflow-patterns.md) - Workflow skill implementation patterns
- [Progressive Disclosure](./references/progressive-disclosure.md) - Context management patterns
- [Creation Workflow](./references/creation-workflow.md) - Step-by-step process with examples
- [Scripts Reference](./references/scripts-reference.md) - Marketplace script usage
- [Security Practices](./references/security-practices.md) - Threats and defenses (CVE references)
- [Phased Execution](./references/phased-execution.md) - Preflight/Execute/Verify patterns and variants
- [Invocation Control](./references/invocation-control.md) - Skill invocation modes, permission rules, legacy commands migration
- [Interactive Patterns](./references/interactive-patterns.md) - AskUserQuestion integration patterns
- [Token Efficiency](./references/token-efficiency.md) - Context optimization
- [Advanced Topics](./references/advanced-topics.md) - CLI vs API, composition, bugs
- [Path Patterns](./references/path-patterns.md) - Safe/unsafe path references (known bugs documented)
- [Bash Compatibility](./references/bash-compatibility.md) - Shell portability patterns
- [Validation Reference](./references/validation-reference.md) - Quality checklist
- [Troubleshooting](./references/troubleshooting.md) - Common issues and solutions
- [SYNC-TRACKING](./references/SYNC-TRACKING.md) - Marketplace version tracking
- [Evolution Log](./references/evolution-log.md) - This skill's change history
