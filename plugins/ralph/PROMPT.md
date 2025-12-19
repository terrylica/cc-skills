# Task: Create the Ultimate Ralph Orchestrator Skill

## Objective

Create a comprehensive Claude Code skill (`SKILL.md`) that teaches users how to invoke Ralph Orchestrator in the most **cinematic, powerful way** - showcasing its evolutionary, long-running capabilities.

## Context

Ralph Orchestrator is installed at `~/eon/ralph-orchestrator/` and accessible globally via the `ralph` command. It implements the "Ralph Wiggum technique" - keeping an AI agent in a loop until tasks are complete. Your skill should teach users how to harness this power.

## Research Phase

First, deeply research Ralph's capabilities by reading:

- [x] `~/eon/ralph-orchestrator/README.md` - Core documentation
- [x] `~/eon/ralph-orchestrator/docs/` - Full documentation
- [x] `~/eon/ralph-orchestrator/examples/` - Usage examples
- [x] `~/eon/ralph-orchestrator/src/ralph_orchestrator/adapters/claude.py` - Claude integration

## Requirements

Create `skills/ralph-orchestrator/SKILL.md` with:

- [x] **Frontmatter**: name, description (triggers: "ralph", "orchestrator", "long-running", "autonomous agent", "loop until done")
- [x] **Overview**: Cinematic description of Ralph's evolutionary power
- [x] **When to Use**: Clear scenarios (refactoring, test generation, greenfield projects, docs)
- [x] **Invocation Patterns**: 5+ example PROMPT.md templates for different use cases
- [x] **Best Practices**: How to write prompts that maximize evolutionary effectiveness
- [x] **CLI Reference**: Key flags and options with examples
- [x] **Cost/Time Estimates**: Realistic expectations per scenario
- [x] **Real-World Examples**: Reference the Y Combinator hackathon success, $50K contract story

Additionally create `skills/ralph-orchestrator/references/`:

- [x] `prompt-templates.md` - 10+ battle-tested PROMPT.md templates (12 templates created)
- [x] `troubleshooting.md` - Common issues and solutions

## Success Criteria

The task is complete when:

- [x] `skills/ralph-orchestrator/SKILL.md` exists with all sections
- [x] `skills/ralph-orchestrator/references/prompt-templates.md` exists with 10+ templates
- [x] `skills/ralph-orchestrator/references/troubleshooting.md` exists
- [x] Content is accurate (verified against Ralph source code)
- [x] Examples are practical and immediately usable
- [x] Writing is engaging and "cinematic" - makes users excited to use Ralph

## Progress Tracking

### Current Iteration

- Status: COMPLETE
- Completed: All deliverables created
- Next: None - task complete

### Files Created

- [x] SKILL.md (created at plugins/itp/skills/ralph-orchestrator/SKILL.md)
- [x] references/prompt-templates.md (12 templates)
- [x] references/troubleshooting.md (comprehensive troubleshooting guide)

## Constraints

- Use relative links (`./references/...`) per cc-skills convention
- Follow existing skill format (see `~/eon/cc-skills/plugins/itp/skills/` for examples)
- No emojis in production content
- Focus on practical, actionable content

---

_This task demonstrates Ralph's evolutionary capability by having Ralph create documentation about itself._
