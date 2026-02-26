---
name: skill-architecture
description: Meta-skill for creating Claude Code skills. TRIGGERS - create skill, YAML frontmatter, validate skill, skill architecture, lifecycle pattern, suite pattern, phased execution, command vs skill.
---

# Skill Architecture

Comprehensive guide for creating effective Claude Code skills following Anthropic's official standards with emphasis on security, CLI-specific features, and progressive disclosure architecture.

> ⚠️ **Scope**: Claude Code CLI Agent Skills (`~/.claude/skills/`), not Claude.ai API skills

## When to Use This Skill

Use this skill when:

- Creating new Claude Code skills from scratch
- Learning skill YAML frontmatter and structure requirements
- Validating skill file format and portability
- Understanding progressive disclosure patterns for skills

---

## FIRST: Task Templates

**MANDATORY**: Select and load the appropriate template into TaskCreate before any skill work.

> For detailed context on each step, see [Skill Creation Process (Detailed Tutorial)](#skill-creation-process-detailed-tutorial) below.

### Template A: Create New Skill

```
1. Gather requirements (ask user for functionality, examples, triggers)
2. Identify reusable resources (scripts, references, assets needed)
3. Run init script to create skill directory structure
4. Create bundled resources first (scripts/, references/, assets/)
5. Write SKILL.md with YAML frontmatter (name, description with triggers)
6. Add task templates section to SKILL.md
7. Add Post-Change Checklist section to SKILL.md
8. Validate with quick_validate.py
9. Validate links (relative paths only): bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
10. Test skill on real example
11. Register skill in project CLAUDE.md
12. Verify against Skill Quality Checklist below
```

### Template B: Update Existing Skill

```
1. Read current SKILL.md and understand structure
2. Identify what needs changing (triggers, workflow, resources)
3. Make targeted changes to SKILL.md
4. Update any affected references/ or scripts/
5. Validate with quick_validate.py
6. Validate links (relative paths only): bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
7. Test updated behavior
8. Update project CLAUDE.md if description changed
9. Verify against Skill Quality Checklist below
```

### Template C: Add Resources to Skill

```
1. Read current SKILL.md to understand skill purpose
2. Determine resource type (script, reference, or asset)
3. Create resource in appropriate directory
4. Update SKILL.md to document new resource
5. Validate with quick_validate.py
6. Validate links (relative paths only): bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
7. Test resource integration
8. Verify against Skill Quality Checklist below
```

### Template D: Convert to Self-Evolving Skill

```
1. Read current SKILL.md structure
2. Add Task Templates section (scenario-specific)
3. Add Post-Change Checklist section
4. Create references/evolution-log.md (reverse chronological - newest on top)
5. Create references/config-reference.md (if skill manages external config)
6. Update description with self-evolution triggers
7. Validate with quick_validate.py
8. Validate links (relative paths only): bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
9. Test self-documentation on sample change
10. Verify against Skill Quality Checklist below
```

### Template E: Troubleshoot Skill Not Triggering

```
1. Check YAML frontmatter syntax (no colons in description)
2. Verify trigger keywords in description match user queries
3. Check skill location (~/.claude/skills/ or project .claude/skills/)
4. Validate with quick_validate.py for errors
5. Validate links: bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
6. Test with explicit trigger phrase
7. Document findings in skill if new issue discovered
8. Verify against Skill Quality Checklist below
```

### Template F: Create Lifecycle Suite

```
1. Identify lifecycle phases needed (bootstrap, operate, diagnose, configure, upgrade, teardown)
2. Create one skill per lifecycle phase (see Suite Pattern in Structural Patterns)
3. Create shared library in scripts/lib/ for common functions (logging, locking, config)
4. Create commands for most-used operations (setup, health, hooks)
5. Add hooks for event-driven automation if cross-session behavior needed
6. Ensure skills cross-reference each other (health check failure → suggest diagnostic skill)
7. Write CLAUDE.md for the plugin (conventions, key paths, shared library API)
8. Validate each skill: bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
9. Test full lifecycle: bootstrap → operate → diagnose → configure → upgrade → teardown
10. Verify against Skill Quality Checklist below
```

### Skill Quality Checklist

After ANY skill work, verify:

- [ ] YAML frontmatter valid (name lowercase-hyphen, description has triggers)
- [ ] `name` matches parent directory name exactly, no consecutive hyphens (`--`)
- [ ] Description includes WHEN to use (trigger keywords)
- [ ] Description not too broad (doesn't false-trigger on unrelated conversations)
- [ ] SKILL.md body under 500 lines (move detail to `references/`)
- [ ] Classify skill as **reference** (inline knowledge) or **task** (side-effect action):
  - Task skills with side effects: set `disable-model-invocation: true`
  - Reference-only skills users shouldn't invoke: set `user-invocable: false`
- [ ] If using `context: fork`, skill has explicit actionable instructions (not guidelines-only)
- [ ] If skill requires external tools (git, docker, jq), add `compatibility` field
- [ ] Task templates cover all common scenarios
- [ ] Post-Change Checklist included for self-maintenance
- [ ] Final template step references this checklist
- [ ] Project CLAUDE.md updated if new/renamed skill
- [ ] Validated with quick_validate.py
- [ ] All markdown links use relative paths (plugin-portable)
- [ ] No broken internal links (validate-links.ts passes)
- [ ] Tested activation **both ways**: manual `/name` AND organic trigger keywords
- [ ] Run `/context` to verify skill is loaded (not excluded by description budget)
- [ ] Phased execution: task templates use `[Preflight]`/`[Execute]`/`[Verify]` labels where applicable
- [ ] Interactive: AskUserQuestion used for destructive actions and multi-option workflows
- [ ] No unsafe path patterns (see [Path Patterns](./references/path-patterns.md)):
  - No hardcoded `/Users/<user>` or `/home/<user>` (use `$HOME`)
  - No hardcoded `/tmp` in Python (use `tempfile.TemporaryDirectory`)
  - No hardcoded binary paths (use `command -v` or PATH)
- [ ] Bash compatibility verified (see [Bash Compatibility](./references/bash-compatibility.md)):
  - All bash code blocks wrapped with `/usr/bin/env bash << 'NAME_EOF'`
  - No `declare -A` (associative arrays) - use parallel indexed arrays
  - No `grep -P` (Perl regex) - use `grep -E` with awk
  - No `\!=` in conditionals - use `!=` directly
  - Heredoc EOF marker is descriptive (e.g., `PREFLIGHT_EOF`)

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

Skills must actively evolve. When you notice friction, missing edge cases, better patterns, or repeated manual steps — **update immediately**: pause → fix SKILL.md or resources → log in evolution-log.md → resume.

**Do NOT update immediately**: major structural changes (discuss first), speculative improvements without evidence.

After completing any skill-assisted task, ask: _"Did anything feel suboptimal? What would help next time?"_ If yes → update now.

---

## About Skills

Skills are modular, self-contained packages that extend Claude's capabilities with specialized knowledge, workflows, and tools. Think of them as "onboarding guides" for specific domains—transforming Claude from general-purpose to specialized agent with procedural knowledge no model fully possesses.

### What Skills Provide

1. **Specialized workflows** - Multi-step procedures for specific domains
2. **Tool integrations** - Instructions for working with specific file formats or APIs
3. **Domain expertise** - Company-specific knowledge, schemas, business logic
4. **Bundled resources** - Scripts, references, assets for complex/repetitive tasks

### Skill Discovery and Precedence

Skills are discovered from multiple locations. When names collide, higher-precedence wins:

1. **Enterprise** (managed settings) — highest
2. **Personal** (`~/.claude/skills/`)
3. **Project** (`.claude/skills/` in repo)
4. **Plugin** (namespaced: `plugin:skill-name`)
5. **Nested** (monorepo `.claude/skills/` in subdirectories — auto-discovered)
6. **`--add-dir`** (CLI flag, live change detection) — lowest

**Management commands**:

- `claude plugin enable <name>` / `claude plugin disable <name>` — toggle plugins
- `claude skill list` — show all discovered skills with source location

**Monorepo support**: Claude Code automatically discovers `.claude/skills/` directories in nested project roots within a monorepo. No configuration needed.

---

## cc-skills Plugin Architecture

> This section applies specifically to the **cc-skills marketplace** plugin structure. Generic standalone skills are unaffected.

### Canonical Structure

```
plugins/<plugin>/
└── skills/
    └── <skill-name>/
        └── SKILL.md   ← single canonical file (context AND user-invocable)
```

`skills/<name>/SKILL.md` is the **single source of truth**. The separate `commands/` layer was eliminated — it required maintaining two identical files per skill and caused `Skill()` invocations to return "Unknown skill". See [migration issue](https://github.com/terrylica/cc-skills/issues/26) for full context.

### How Skills Become Slash Commands

Two install paths, both supported:

| Path                    | Mechanism                                                                                                                           | Notes                                                                                                                                                                                          |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Automated (primary)** | `mise run release:full` → `sync-commands-to-settings.sh` reads `skills/*/SKILL.md` → writes `~/.claude/commands/<plugin>:<name>.md` | Fully automated post-release. Bypasses Anthropic cache bugs [#17361](https://github.com/anthropics/claude-code/issues/17361), [#14061](https://github.com/anthropics/claude-code/issues/14061) |
| **Official CLI**        | `claude plugin install itp@cc-skills` → reads from `skills/` in plugin cache                                                        | Cache may not refresh on update — use `claude plugin update` after new releases                                                                                                                |

### Hooks

`sync-hooks-to-settings.sh` reads `hooks/hooks.json` directly → merges into `~/.claude/settings.json`. Bypasses path re-expansion bug [#18517](https://github.com/anthropics/claude-code/issues/18517).

### Creating a New Skill in cc-skills

Place the SKILL.md under `plugins/<plugin>/skills/<name>/SKILL.md`. No `commands/` copy needed. The validator (`bun scripts/validate-plugins.mjs`) checks frontmatter completeness.

---

## Skill Creation Process (Detailed Tutorial)

> **Note**: Use task templates above for execution. This section provides detailed context for each phase.

### Step 1: Understanding the Skill with Concrete Examples

Clearly understand concrete examples of how the skill will be used. Ask users:

- "What functionality should this skill support?"
- "Can you give examples of how it would be used?"
- "What would trigger this skill?"

Skip only when usage patterns are already clearly understood.

### Step 2: Planning Reusable Contents

Analyze each example to identify what resources would be helpful:

**Example 1 - PDF Editor**:

- Rotating PDFs requires rewriting code each time
- → Create `scripts/rotate_pdf.py`

**Example 2 - Frontend Builder**:

- Webapps need same HTML/React boilerplate
- → Create `assets/hello-world/` template

**Example 3 - BigQuery**:

- Queries require rediscovering table schemas
- → Create `references/schema.md`

### Step 3: Initialize the Skill

Run the init script from plugin-dev:

```bash
uv run plugins/plugin-dev/scripts/skill-creator/init_skill.py <skill-name> --path <target-path>
```

Creates: skill directory + SKILL.md template + example resource directories

### Step 4: Edit the Skill

**Writing Style**: Imperative/infinitive form (verb-first), not second person

- ✅ "To accomplish X, do Y"
- ❌ "You should do X"

**SKILL.md must include**:

1. What is the purpose? (few sentences)
2. When should it be used? (trigger keywords in description)
3. How should Claude use bundled resources?
4. **Task Templates** - Pre-defined tasks for common scenarios
5. **Post-Change Checklist** - Self-maintenance verification

**Start with resources** (`scripts/`, `references/`, `assets/`), then update SKILL.md

### Step 5: Validate the Skill

**For local development** (validation only, no zip creation):

```bash
uv run plugins/plugin-dev/scripts/skill-creator/quick_validate.py <path/to/skill-folder>
```

**For distribution** (validates AND creates zip):

```bash
uv run plugins/plugin-dev/scripts/skill-creator/package_skill.py <path/to/skill-folder>
```

Validates: YAML frontmatter, naming, description, file organization

**Note**: Use `quick_validate.py` for most workflows. Only use `package_skill.py` when actually distributing the skill to others.

### Step 6: Register and Iterate

1. Register skill in project CLAUDE.md (Workspace Skills section)
2. Use skill on real tasks
3. Notice struggles/inefficiencies
4. Update SKILL.md or resources
5. Test again
6. Verify against Skill Quality Checklist above

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

```yaml
---
name: skill-name-here
description: What this does and when to use it (max 1024 chars)
allowed-tools: Read, Grep, Bash
disable-model-invocation: false
context: fork
agent: true
argument-hint: <file-path> [--verbose]
---
```

**Field Reference:**

| Field                       | Required | Rules                                                                                                             |
| --------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| `name`                      | No\*     | Lowercase, hyphens, numbers. Max 64 chars. Unique. Falls back to directory name if omitted.                       |
| `description`               | Yes      | WHAT it does + WHEN to use. Max 1024 chars. Single line. Include trigger keywords!                                |
| `allowed-tools`             | No       | **Grants** tools without per-use approval (comma-separated). Does NOT restrict — unlisted tools still available.  |
| `disable-model-invocation`  | No       | `true` = only manual `/name` invocation, never auto-triggered by Claude. Default: `false`.                        |
| `user-invocable`            | No       | `false` = background-only (no `/name` slash command). Claude auto-triggers based on description. Default: `true`. |
| `context`                   | No       | `fork` runs skill in forked context (isolated from main conversation). Default: inline.                           |
| `agent`                     | No       | `true` enables agentic loop (skill can call tools autonomously). Default: `false`.                                |
| `argument-hint`             | No       | Shown in autocomplete for `/name` (e.g., `<file> [--format json]`). Only relevant if user-invocable.              |
| `allowed-permission-prompt` | No       | Comma-separated Bash permission prompts granted without user approval.                                            |
| `name-aliases`              | No       | Comma-separated alternative names for `/name` invocation.                                                         |

\* Agent Skills spec (`agentskills.io`) requires `name`. Claude Code falls back to directory name. Include it for portability.

> **Note**: `allowed-tools` delimiter is **commas** in Claude Code (e.g., `Read, Grep, Bash`). The Agent Skills spec uses **spaces**. Use commas for Claude Code skills.

**Invocation Control:**

| Setting                          | `/name` available? | Auto-triggered? | Use case                        |
| -------------------------------- | ------------------ | --------------- | ------------------------------- |
| Default (both omitted)           | Yes                | Yes             | Most skills                     |
| `disable-model-invocation: true` | Yes                | No              | Dangerous ops (deploy, release) |
| `user-invocable: false`          | No                 | Yes             | Domain knowledge, context-only  |

**Skill Permission Rules** (for `allowed-tools` in `settings.json`):

- `Skill(skill-name)` — exact match, allows one specific skill
- `Skill(skill-name *)` — prefix match, allows skill and all sub-invocations

**Good vs Bad Descriptions:**

✅ **Good**: "Extract text and tables from PDFs, fill forms, merge documents. Use when working with PDF files or when user mentions forms, contracts, document processing."

❌ **Bad**: "Helps with documents" (too vague, no triggers)

**YAML Description Pitfalls:**

| Pitfall          | Problem                          | Fix                                                                                  |
| ---------------- | -------------------------------- | ------------------------------------------------------------------------------------ |
| Multiline syntax | `>` or `\|` not supported        | Single line only                                                                     |
| Colons in text   | `CRITICAL: requires` breaks YAML | Use `CRITICAL - requires`                                                            |
| Quoted strings   | Valid but not idiomatic          | Unquoted preferred (match [anthropics/skills](https://github.com/anthropics/skills)) |

```yaml
# ❌ BREAKS - colon parsed as YAML key:value
description: ...CRITICAL: requires flag

# ✅ WORKS - dash instead of colon
description: ...CRITICAL - requires flag
```

**Validation**: GitHub renders frontmatter - invalid YAML shows red error banner.

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

Use `` !`command` `` in skill body to inject command output at load time:

```markdown
Current branch: !`git branch --show-current`
Last commit: !`git log -1 --oneline`
```

The command runs when the skill loads — output replaces the `` !`...` `` block inline.

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

- [Structural Patterns](./references/structural-patterns.md) - 5 skill architecture patterns (including Suite Pattern)
- [Workflow Patterns](./references/workflow-patterns.md) - Workflow skill implementation patterns
- [Progressive Disclosure](./references/progressive-disclosure.md) - Context management patterns
- [Creation Workflow](./references/creation-workflow.md) - Step-by-step process
- [Scripts Reference](./references/scripts-reference.md) - Marketplace script usage
- [Security Practices](./references/security-practices.md) - Threats and defenses (CVE references)
- [Phased Execution](./references/phased-execution.md) - Preflight/Execute/Verify patterns and variants
- [Invocation Control](./references/invocation-control.md) - Skill invocation modes, permission rules, legacy commands migration
- [Interactive Patterns](./references/interactive-patterns.md) - AskUserQuestion integration patterns
- [Token Efficiency](./references/token-efficiency.md) - Context optimization
- [Advanced Topics](./references/advanced-topics.md) - CLI vs API, composition, bugs
- [Path Patterns](./references/path-patterns.md) - Safe/unsafe path references (known bugs documented)
- [Validation Reference](./references/validation-reference.md) - Quality checklist
- [SYNC-TRACKING](./references/SYNC-TRACKING.md) - Marketplace version tracking
- [Evolution Log](./references/evolution-log.md) - This skill's change history

---

## Troubleshooting

| Issue                  | Cause                          | Solution                                                                                                                |
| ---------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Skill not triggering   | Missing trigger keywords       | Add trigger phrases to description field                                                                                |
| YAML parse error       | Colon in description           | Replace colons with dashes in description                                                                               |
| Skill not found        | Wrong location or not synced   | Standalone: place in `~/.claude/skills/` or project `.claude/skills/`. Marketplace: run `mise run release:full` to sync |
| validate script fails  | Invalid frontmatter            | Check name format (lowercase-hyphen only)                                                                               |
| Resources not loading  | Wrong path in SKILL.md         | Use relative paths from skill directory                                                                                 |
| Script execution fails | Missing shebang or permissions | Add `#!/usr/bin/env python3` and `chmod +x`                                                                             |
| allowed-tools ignored  | API skill (not CLI)            | allowed-tools only works in CLI skills                                                                                  |
| Description too long   | Over 1024 chars                | Shorten description, move details to SKILL.md body                                                                      |
