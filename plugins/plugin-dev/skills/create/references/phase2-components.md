# Phase 2: Component Creation (Detailed)

**Execute ONLY the skills for components the user selected.**

## 2.1 Skills (if has-skills)

**MANDATORY Skill tool call: `plugin-dev:skill-architecture`** -- activate if skills selected.

This skill (NOT plugin-dev:skill-development) provides:

- 5 TodoWrite templates (A-E)
- SKILL.md structure
- References folder patterns
- Security practices

After skill creation, spawn reviewer agent:

**Spawn Agent: `plugin-dev:skill-reviewer`** -- validate skill quality.

```
Task with subagent_type="plugin-dev:skill-reviewer"
prompt: "Review the skills created in plugins/$PLUGIN_NAME/skills/ for quality, security, and best practices."
```

## 2.2 Hooks (if has-hooks)

**MANDATORY Skill tool call: `plugin-dev:hook-development`** -- activate if hooks selected.

This skill includes:

- hooks.json structure
- Event types (PreToolUse, PostToolUse, Stop, etc.)
- Settings patterns (plugin-settings merged in)

## 2.3 Commands (if has-commands)

**MANDATORY Skill tool call: `plugin-dev:command-development`** -- activate if commands selected.

This skill provides:

- YAML frontmatter fields
- Argument patterns
- Dynamic arguments

## 2.4 Agents (if has-agents)

**MANDATORY Skill tool call: `plugin-dev:agent-development`** -- activate if agents selected.

This skill provides:

- Agent frontmatter
- Triggering conditions
- Tool restrictions

## Phase 2 Gate

**STOP. Verify before proceeding to Phase 3:**

- [ ] All selected components created
- [ ] If skills: skill-reviewer agent completed review
- [ ] Files follow plugin-dev patterns
