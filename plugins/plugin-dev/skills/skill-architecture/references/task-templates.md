**Skill**: [Skill Architecture](../SKILL.md)

# Task Templates

**MANDATORY**: Select and load the appropriate template before any skill work.

> For detailed context on each step, see [Skill Creation Process (Detailed Tutorial)](./creation-tutorial.md) or [Creation Workflow](./creation-workflow.md).

## Template A: Create New Skill

```
1. Gather requirements (ask user for functionality, examples, triggers)
2. Identify reusable resources (scripts, references, assets needed)
3. Run init script to create skill directory structure
4. Create bundled resources first (scripts/, references/, assets/)
5. Write SKILL.md with YAML frontmatter (name, description with triggers)
6. Add task templates section to SKILL.md
7. Add Post-Change Checklist section to SKILL.md
8. Add Post-Execution Reflection section to SKILL.md (compulsory — see reference)
9. Validate with quick_validate.py
10. Validate links (relative paths only): bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
11. Test skill on real example
12. Register skill in project CLAUDE.md
13. Verify against Skill Quality Checklist below
```

## Template B: Update Existing Skill

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

## Template C: Add Resources to Skill

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

## Template D: Convert to Self-Evolving Skill

```
1. Read current SKILL.md structure
2. Add Task Templates section (scenario-specific)
3. Add Post-Change Checklist section
4. Add Post-Execution Reflection section (compulsory — see post-execution-reflection.md)
5. Create references/evolution-log.md (reverse chronological - newest on top)
6. Create references/config-reference.md (if skill manages external config)
7. Update description with self-evolution triggers
8. Validate with quick_validate.py
9. Validate links (relative paths only): bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
10. Test self-documentation on sample change
11. Verify against Skill Quality Checklist below
```

## Template E: Troubleshoot Skill Not Triggering

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

## Template F: Create Lifecycle Suite

```
1. Identify lifecycle phases needed (bootstrap, operate, diagnose, configure, upgrade, teardown)
2. Create one skill per lifecycle phase (see Suite Pattern in Structural Patterns)
3. Create shared library in scripts/lib/ for common functions (logging, locking, config)
4. Create commands for most-used operations (setup, health, hooks)
5. Add hooks for event-driven automation if cross-session behavior needed
6. Ensure skills cross-reference each other (health check failure -> suggest diagnostic skill)
7. Write CLAUDE.md for the plugin (conventions, key paths, shared library API)
8. Validate each skill: bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
9. Test full lifecycle: bootstrap -> operate -> diagnose -> configure -> upgrade -> teardown
10. Verify against Skill Quality Checklist below
```

## Skill Quality Checklist

After ANY skill work, verify:

- [ ] YAML frontmatter valid (name lowercase-hyphen, description has triggers)
- [ ] `name` matches parent directory name exactly, no consecutive hyphens (`--`)
- [ ] Description includes WHEN to use (trigger keywords)
- [ ] Description not too broad (doesn't false-trigger on unrelated conversations)
- [ ] SKILL.md body under 500 lines (move detail to `references/`)
- [ ] Classify skill as **reference** (inline knowledge) or **task** (side-effect action):
  - `disable-model-invocation: true` ONLY for hook-installation skills — all others keep `false` (default)
  - Reference-only skills users shouldn't invoke: set `user-invocable: false`
- [ ] If using `context: fork`, skill has explicit actionable instructions (not guidelines-only)
- [ ] If skill requires external tools (git, docker, jq), add `compatibility` field
- [ ] Task templates cover all common scenarios
- [ ] Post-Change Checklist included for self-maintenance
- [ ] Post-Execution Reflection section included (compulsory for stepwise skills)
- [ ] Final template step references this checklist
- [ ] Project CLAUDE.md updated if new/renamed skill
- [ ] Validated with quick_validate.py
- [ ] All markdown links use relative paths (plugin-portable)
- [ ] No broken internal links (validate-links.ts passes)
- [ ] Tested activation **both ways**: manual `/name` AND organic trigger keywords
- [ ] Run `/context` to verify skill is loaded (not excluded by description budget)
- [ ] Phased execution: task templates use `[Preflight]`/`[Execute]`/`[Verify]`/`[Reflect]`/`[Rectify]` labels where applicable
- [ ] Interactive: AskUserQuestion used for destructive actions and multi-option workflows
- [ ] No unsafe path patterns (see [Path Patterns](./path-patterns.md)):
  - No hardcoded `/Users/<user>` or `/home/<user>` (use `$HOME`)
  - No hardcoded `/tmp` in Python (use `tempfile.TemporaryDirectory`)
  - No hardcoded binary paths (use `command -v` or PATH)
- [ ] Bash compatibility verified (see [Bash Compatibility](./bash-compatibility.md)):
  - All bash code blocks wrapped with `/usr/bin/env bash << 'NAME_EOF'`
  - No `declare -A` (associative arrays) - use parallel indexed arrays
  - No `grep -P` (Perl regex) - use `grep -E` with awk
  - No `\!=` in conditionals - use `!=` directly
  - Heredoc EOF marker is descriptive (e.g., `PREFLIGHT_EOF`)
