# gh-tools Plugin

> GitHub workflow automation: GFM link validation, WebFetch enforcement, issue title optimization.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Overview

This plugin provides GitHub CLI enforcement through hooks and skills for PR creation, issue management, and gh CLI best practices.

## Hooks

### PreToolUse Hooks

| Hook                           | Matcher  | Purpose                                      |
| ------------------------------ | -------- | -------------------------------------------- |
| `webfetch-github-guard.sh`     | WebFetch | Soft-blocks WebFetch for github.com URLs     |
| `gh-issue-body-file-guard.mjs` | Bash     | Requires `--body-file` for `gh issue create` |

### PostToolUse Hooks

| Hook                          | Matcher | Purpose                                       |
| ----------------------------- | ------- | --------------------------------------------- |
| `gh-issue-title-reminder.mjs` | Bash    | Reminds to optimize issue title after comment |

## GitHub Issue Title Optimization (2026-02-05)

The `gh-issue-title-reminder.mjs` hook enforces the **Title Evolution** pattern:

### Principle

GitHub allows **256 characters** for issue titles. Maximize this limit to create informative, searchable titles that reflect the full context of the issue.

### When It Triggers

| Command Pattern                  | Triggers?              |
| -------------------------------- | ---------------------- |
| `gh issue comment <n>`           | Yes                    |
| `gh api .../issues/<n>/comments` | Yes                    |
| `gh issue create`                | Yes (generic reminder) |

### Ownership Check

The hook only shows reminders for issues you own:

1. **Primary**: `GH_ACCOUNT` environment variable (set by mise per-directory)
2. **Fallback**: Token filename pattern from `~/.claude/.secrets/gh-token-<username>`

### Threshold

Reminder appears if title < 200 characters (room for improvement).

### Example Reminder

```
[gh-tools] Issue Title Optimization Reminder

Issue: #21 in terrylica/cc-skills
Current title (77/256 chars):
  "Findings: Parameter-Free Feature Selection"

Consider updating the title to:
   - Reflect new findings from this comment
   - Maximize the 256-character limit
   - Capture the full journey/context of the issue

Commands:
  gh issue view 21 --json title --jq '.title | length'
  gh issue edit 21 --title "..."
```

## WebFetch Enforcement

The `webfetch-github-guard.sh` hook soft-blocks WebFetch for github.com URLs:

- Suggests `gh issue view`, `gh pr view` alternatives
- Shows specific gh commands for the URL pattern
- User can override if needed

**ADR**: [/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md](/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md)

## Issue Body File Guard

The `gh-issue-body-file-guard.mjs` hook blocks `gh issue create --body "..."`:

- Inline heredocs silently fail for long content
- Requires `--body-file` pattern for reliability

**ADR**: [/docs/adr/2026-01-11-gh-issue-body-file-guard.md](/docs/adr/2026-01-11-gh-issue-body-file-guard.md)

## Skills

| Skill              | Purpose                                          |
| ------------------ | ------------------------------------------------ |
| `pr-gfm-validator` | Validate and auto-fix GFM links in PR bodies     |
| `issue-create`     | Create issues with AI labeling (256-char titles) |
| `issues-workflow`  | Issues-first workflow with sub-issues hierarchy  |

## Multi-Account Authentication

This plugin respects the multi-account setup via mise:

```toml
# ~/eon/.mise.toml
[env]
GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"
GH_ACCOUNT = "terrylica"
```

**ADR**: [/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md](/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md)

## Process Safety

The hooks avoid credential helper recursion by:

1. Using `GH_TOKEN` environment variable (not credential helpers)
2. Using `gh issue view` (read-only operations)
3. Including 10-second timeout on all gh CLI calls

## References

- [README.md](./README.md) - Full plugin documentation
- [hooks.json](./hooks/hooks.json) - Hook configuration
- [Issue Create Skill](./skills/issue-create/SKILL.md)
- [Issues Workflow Skill](./skills/issues-workflow/SKILL.md)
