---
name: skill-architecture
description: Create new skills, modify existing skills, and understand skill architecture. Use when users want to create a skill from scratch, learn YAML frontmatter standards, validate skill structure, understand progressive disclosure patterns, or choose between structural patterns (workflow, task, reference, capabilities, suite). Also use for troubleshooting skills that don't trigger correctly, optimizing skill descriptions, or learning best practices for writing effective skill instructions.
---

# Skill Architecture

Comprehensive guide for creating effective Claude Code skills following Anthropic's official standards with emphasis on security and progressive disclosure architecture.

> **Scope**: Claude Code Agent Skills (`~/.claude/skills/`), not Claude.ai API skills

## When to Use This Skill

Use this skill when:

- Creating new Claude Code skills from scratch
- Learning skill YAML frontmatter and structure requirements
- Validating skill file format and portability
- Understanding progressive disclosure patterns for skills

---

## Task Templates

Select the appropriate template before starting skill work -- templates encode common workflows and prevent missing steps that cause silent failures.

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

## Testing and Iteration

Good skills emerge through testing and feedback, not from getting the first draft perfect. After writing or updating a skill, verify it works by running it against realistic prompts.

### Write Test Prompts

Come up with 2-3 realistic test prompts -- the kind of thing a real user would actually say. Not abstract requests, but concrete tasks with enough detail to exercise the skill. Share them with the user for confirmation before running.

### Run and Evaluate

For each test prompt, run the skill and examine the output:

- **Did the skill trigger?** If not, the description may need stronger trigger language.
- **Did it follow the workflow?** Check whether instructions were followed or ignored.
- **Was the output useful?** Compare against what you'd expect from a skilled human.

When subagents are available, run with-skill and without-skill versions in parallel to measure the skill's actual value-add. When not available, run test cases yourself as a sanity check.

### Iterate Based on Feedback

After evaluating results, improve the skill and retest. Keep iterating until the user is satisfied or feedback is consistently positive. Key principles for each iteration:

1. **Generalize from specific feedback.** Skills will be used across many different prompts. Avoid overfitting to test cases with fiddly, narrow fixes. If a pattern keeps failing, try a different approach or metaphor rather than adding more constraints.

2. **Keep the skill lean.** Every section must earn its tokens. Read the execution transcripts -- if the skill causes the model to waste time on unproductive steps, cut those instructions and see what happens.

3. **Explain the why, not just the what.** LLMs respond better to understanding _why_ a rule exists than to being commanded with rigid directives. Instead of "ALWAYS do X", explain: "Do X because skipping it causes Y, which leads to Z." This produces more robust behavior that generalizes to novel situations.

4. **Look for repeated work across test cases.** If every test run independently creates the same helper script or takes the same multi-step approach, bundle that script in `scripts/` so future invocations don't reinvent the wheel.

5. **Bundle common patterns as scripts.** When test runs reveal that the model writes similar boilerplate code every time, extract it into a bundled script. This saves tokens and improves reliability.

---

## Skill Writing Principles

These principles (aligned with Anthropic's official guidance) apply to all skill content:

- **Imperative form**: "Run the script", "Check the output" -- not passive or indirect phrasing.
- **Explain reasoning over rigid rules**: If you find yourself writing MUST/NEVER/ALWAYS in all caps, that's a signal to reframe. Explain the reasoning so the model internalizes the principle rather than treating it as an arbitrary constraint. The model is smart -- help it understand, don't just command it.
- **Pushy descriptions for triggering**: Claude tends to undertrigger skills. Descriptions should actively claim territory: "Use this skill whenever the user mentions X, Y, or Z, even if they don't explicitly ask for it." Include negative triggers too: "Do NOT use for A or B."
- **Natural language descriptions**: Write descriptions as sentences a human could read, not keyword lists. "Use this skill whenever..." is better than "TRIGGERS - keyword1, keyword2".
- **Keep execution out of descriptions**: Descriptions tell Claude _when_ to trigger. The skill body tells Claude _how_ to execute. Don't mix them.

See [Writing Guide](./references/writing-guide.md) for extended guidance with examples.

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
- [Writing Guide](./references/writing-guide.md) - Tone, reasoning-based instructions, description optimization
- [Script Design](./references/script-design.md) - Designing scripts for agentic consumption
- [Troubleshooting](./references/troubleshooting.md) - Common issues and solutions
- [SYNC-TRACKING](./references/SYNC-TRACKING.md) - Marketplace version tracking
- [Evolution Log](./references/evolution-log.md) - This skill's change history
