# Skill Writing Guide

Principles for writing effective skill instructions, aligned with Anthropic's official guidance from the [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md).

## Core Philosophy

LLMs are smart. They have good theory of mind and, when given a good harness, can go beyond rote instructions. The goal is to help the model _understand_ what you need, not to constrain it with rigid command structures.

## Reasoning Over Rigidity

The single most important principle: explain _why_ behind every instruction.

**Rigid (less effective):**

```markdown
**MANDATORY**: Run `impl-standards` before writing code. DO NOT SKIP.
```

**Reasoning-based (more effective):**

```markdown
Invoke `impl-standards` before writing code -- it defines error handling and constant
patterns that prevent the most common code review rejections. Skipping it typically
means rework later.
```

When you find yourself writing MUST, NEVER, ALWAYS, FORBIDDEN, or NON-NEGOTIABLE in all caps, pause and ask: "Can I explain _why_ instead?" The model treats explained principles as things to internalize. It treats shouted commands as arbitrary constraints to satisfy minimally.

**When rigid directives are justified**: Safety-critical operations (data deletion, production deployments) where the cost of deviation is catastrophic. Even then, pair the directive with a one-line "why".

## Description Writing

The description field is the primary mechanism Claude uses to decide whether to invoke a skill. Getting it right determines whether your skill is useful or invisible.

### Claude Undertriggers

Claude tends to _not_ use skills when they'd be useful. Combat this by making descriptions "pushy" -- actively claiming territory:

**Weak (undertriggers):**

```yaml
description: Dashboard creation tool.
```

**Strong (triggers reliably):**

```yaml
description:
  Build fast dashboards to display data. Use this skill whenever the user
  mentions dashboards, data visualization, metrics, charts, or wants to display any
  kind of data visually, even if they don't explicitly ask for a "dashboard".
```

### Description Formula

A good description has three parts:

1. **What it does** (one sentence)
2. **When to use it** (enumerate trigger contexts, be inclusive)
3. **When NOT to use it** (prevent false triggers on adjacent skills)

### Natural Language Over Keywords

Write descriptions as sentences a human could understand:

**Before (keyword metadata):**

```yaml
description: "WORKFLOW COMMAND - Execute TodoWrite FIRST... TRIGGERS - itp go,
  start workflow, implement feature."
```

**After (natural language):**

```yaml
description: "Execute the ADR-driven 4-phase development workflow (preflight,
  implementation, formatting, release). Use when the user says 'itp go', 'start
  the workflow', 'implement this feature', or 'begin the task'. Do not use for
  simple one-off edits that don't need ADR tracking."
```

### Keep Execution Out of Descriptions

Descriptions tell Claude _when_ to trigger. The skill body tells Claude _how_ to execute. Mixing them pollutes the triggering signal and confuses the model about what belongs where.

## Keeping Skills Lean

Every line in a skill must earn its place. Dead weight degrades performance by consuming context budget and potentially causing the model to follow unproductive paths.

**Lean checklist:**

- Can this section be removed without losing critical behavior?
- Is this instruction repeated elsewhere in the skill?
- Would the model do the right thing here without being told?
- Is this a rare edge case that could live in `references/` instead?

Read execution transcripts from test runs. If the model wastes time on steps that don't contribute to the output, cut the instructions that caused those steps.

## Generalizing from Feedback

Skills should work across many different prompts, not just your test cases. When improving a skill based on feedback:

- **Don't overfit**: Avoid narrow fixes for specific test case failures. Ask whether the fix helps the general case.
- **Try different approaches**: If a pattern stubbornly fails, try different metaphors or workflow structures rather than adding more constraints.
- **Extract patterns**: When all test runs independently take the same approach, that's a signal to bundle it (as a script, reference, or inline instruction).

## Tone

Write skills as if explaining to a thoughtful colleague:

- **Collaborative**: "Check the output format matches the template" over "YOU MUST CHECK THE OUTPUT FORMAT"
- **Trusting**: Assume the model will make good decisions within your framework
- **Practical**: Lead with what to do, then explain why if the reason isn't obvious

For workflow skills that need enforcement (ITP, deployment pipelines), explain the cost of deviation rather than shouting prohibitions:

**Commanding (brittle):**

```markdown
**FORBIDDEN**: Skipping preflight phase.
```

**Explanatory (robust):**

```markdown
The preflight phase catches configuration errors that are expensive to fix later.
Skipping it for "simple" changes is the #1 cause of rework -- most changes that
seem simple have hidden dependencies the preflight check reveals.
```

## Examples in Skills

Include examples to show expected input/output patterns:

```markdown
## Commit message format

**Example:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

Examples ground abstract instructions in concrete behavior. They're especially valuable for output formatting, naming conventions, and domain-specific patterns.
