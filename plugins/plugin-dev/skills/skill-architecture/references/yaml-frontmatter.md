**Skill**: [Skill Architecture](../SKILL.md)

# YAML Frontmatter Reference

## Required Format

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

## Field Reference

| Field                       | Required | Rules                                                                                                             |
| --------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| `name`                      | No\*     | Lowercase, hyphens, numbers. Max 64 chars. Unique. Falls back to directory name if omitted.                       |
| `description`               | Yes      | WHAT it does + WHEN to use. Max 1024 chars. Single line. Include trigger keywords!                                |
| `allowed-tools`             | No       | **Grants** tools without per-use approval (comma-separated). Does NOT restrict -- unlisted tools still available. |
| `disable-model-invocation`  | No       | `true` = only manual `/name` invocation, never auto-triggered by Claude. Default: `false`.                        |
| `user-invocable`            | No       | `false` = background-only (no `/name` slash command). Claude auto-triggers based on description. Default: `true`. |
| `context`                   | No       | `fork` runs skill in forked context (isolated from main conversation). Default: inline.                           |
| `agent`                     | No       | `true` enables agentic loop (skill can call tools autonomously). Default: `false`.                                |
| `argument-hint`             | No       | Shown in autocomplete for `/name` (e.g., `<file> [--format json]`). Only relevant if user-invocable.              |
| `allowed-permission-prompt` | No       | Comma-separated Bash permission prompts granted without user approval.                                            |
| `name-aliases`              | No       | Comma-separated alternative names for `/name` invocation.                                                         |

\* Agent Skills spec (`agentskills.io`) requires `name`. Claude Code falls back to directory name. Include it for portability.

> **Note**: `allowed-tools` delimiter is **commas** in Claude Code (e.g., `Read, Grep, Bash`). The Agent Skills spec uses **spaces**. Use commas for Claude Code skills.

## Invocation Control

| Setting                          | `/name` available? | Auto-triggered? | Use case                        |
| -------------------------------- | ------------------ | --------------- | ------------------------------- |
| Default (both omitted)           | Yes                | Yes             | Most skills                     |
| `disable-model-invocation: true` | Yes                | No              | Dangerous ops (deploy, release) |
| `user-invocable: false`          | No                 | Yes             | Domain knowledge, context-only  |

See [Invocation Control (detailed)](./invocation-control.md) for full guidance on when to use each mode, permission rules, and migration from legacy `commands/`.

## Skill Permission Rules

- `Skill(skill-name)` -- exact match, allows one specific skill
- `Skill(skill-name *)` -- prefix match, allows skill and all sub-invocations

## Good vs Bad Descriptions

Good: "Extract text and tables from PDFs, fill forms, merge documents. Use when working with PDF files or when user mentions forms, contracts, document processing."

Bad: "Helps with documents" (too vague, no triggers)

## YAML Description Pitfalls

| Pitfall          | Problem                          | Fix                                                                                  |
| ---------------- | -------------------------------- | ------------------------------------------------------------------------------------ |
| Multiline syntax | `>` or `\|` not supported        | Single line only                                                                     |
| Colons in text   | `CRITICAL: requires` breaks YAML | Use `CRITICAL - requires`                                                            |
| Quoted strings   | Valid but not idiomatic          | Unquoted preferred (match [anthropics/skills](https://github.com/anthropics/skills)) |

```yaml
# BREAKS - colon parsed as YAML key:value
description: ...CRITICAL: requires flag

# WORKS - dash instead of colon
description: ...CRITICAL - requires flag
```

**Validation**: GitHub renders frontmatter - invalid YAML shows red error banner.
