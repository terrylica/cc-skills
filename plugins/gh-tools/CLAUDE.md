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
| `gh-repo-identity-guard.mjs`   | Bash     | Blocks gh writes when user lacks push access |

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

## Repo Identity Guard (2026-02-09)

The `gh-repo-identity-guard.mjs` hook blocks gh CLI write operations when the authenticated user lacks push access to the target repository.

### Incident

On 2026-02-09, Issue #6 was posted to `459ecs/dental-career-opportunities` by `terrylica` (wrong account). Root cause: `GH_TOKEN` set to `terrylica` from global mise config; project-specific config had a parse error preventing override.

### Guard Behavior

1. **Detect write commands**: `gh issue/pr/label create|comment|edit|close|delete`, `gh api -X POST/PUT/PATCH/DELETE`
2. **Extract target repo**: from `--repo`/`-R` flag, `gh api repos/owner/repo/...` path, or git remote
3. **Resolve authenticated user**: `GH_ACCOUNT` env var → cache → `curl /user` API
4. **Check permission**: owner match → allow; push permission → allow; otherwise → **DENY**

### Process Safety

- **No `gh` CLI calls** — uses `curl` with `Authorization: token` header (prevents credential helper recursion / process storms)
- **Fail-open** — if API fails or token missing, allows through (gh CLI will fail itself)
- **Cache-backed** — `/tmp/.gh-identity-cache-{uid}.json` with 5-min TTL prevents repeated API calls

### Deny Message

```
[gh-identity-guard] BLOCKED: Wrong GitHub account for owner/repo

Authenticated as: username (via source)
Target repository: owner/repo
Push permission: DENIED

Fix:
  1. Check mise config: mise env | grep GH_TOKEN
  2. Verify GH_ACCOUNT: echo $GH_ACCOUNT
  3. If mise parse error: mise doctor
  4. Set correct token: export GH_TOKEN=$(cat ~/.claude/.secrets/gh-token-owner)
```

## Skills

| Skill               | Purpose                                                    |
| ------------------- | ---------------------------------------------------------- |
| `pr-gfm-validator`  | Validate and auto-fix GFM links in PR bodies               |
| `issue-create`      | Create issues with AI labeling (256-char titles)           |
| `issues-workflow`   | Issues-first workflow with sub-issues hierarchy            |
| `research-archival` | Scrape AI research URLs, archive with frontmatter + Issues |
| `fork-intelligence` | Discover valuable fork divergence beyond stars             |

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
2. Using `gh issue view` (read-only operations) or `curl` with `Authorization: token` header
3. Including 10-second timeout on all hook operations

## References

- [README.md](./README.md) - Full plugin documentation
- [hooks.json](./hooks/hooks.json) - Hook configuration
- [Issue Create Skill](./skills/issue-create/SKILL.md)
- [Issues Workflow Skill](./skills/issues-workflow/SKILL.md)
- [Research Archival Skill](./skills/research-archival/SKILL.md)
