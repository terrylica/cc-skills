# gh-tools Plugin

> GitHub workflow automation: GFM link validation, WebFetch enforcement, issue title optimization.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Overview

This plugin provides GitHub CLI enforcement through hooks and skills for PR creation, issue management, and gh CLI best practices.

## Hooks

### PreToolUse Hooks

| Hook                         | Matcher  | Purpose                                      |
| ---------------------------- | -------- | -------------------------------------------- |
| `webfetch-github-guard.sh`   | WebFetch | Soft-blocks WebFetch for github.com URLs     |
| `gh-repo-identity-guard.mjs` | Bash     | Blocks gh writes when user lacks push access |

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

## Discovery Provenance (Mandatory for Issue Creation)

When filing GitHub issues from a Claude Code session, **always** append a Discovery Provenance section. This links the issue back to the exact conversation and terminal recording where it was discovered.

### Format (2 rows — no redundancy)

```markdown
### Discovery Provenance

| Reference      | Value         |
| -------------- | ------------- |
| Session JSONL  | `<full path>` |
| Asciinema Cast | `<full path>` |
```

- **Session JSONL** embeds the Claude Code session UUID in the filename — no separate "Session ID" row needed
- **Asciinema Cast** embeds the iTerm2 session UUID, termid, profile, and timestamp — no separate "iTerm2 Session" row needed
- **Date** is redundant — GitHub issues have creation timestamps

### Deterministic Lookups

**Session JSONL** — from `.session-chain-cache.json`:

```bash
ENCODED="-$(pwd | sed 's|^/||' | tr '/' '-')"
SESSION_ID=$(jq -r '.currentSessionId' ~/.claude/projects/$ENCODED/.session-chain-cache.json)
echo "$HOME/.claude/projects/$ENCODED/$SESSION_ID.jsonl"
```

**Asciinema Cast** — from `$ITERM_SESSION_ID`:

```bash
TERMID="${ITERM_SESSION_ID%:*}"
UUID="${ITERM_SESSION_ID#*:}"
ls -t ~/asciinemalogs/*."$TERMID"."$UUID".*.cast 2>/dev/null | head -1
```

### Why These Two Paths Are Sufficient

| Path           | Embedded Information                                                                      |
| -------------- | ----------------------------------------------------------------------------------------- |
| Session JSONL  | Claude Code session UUID, project directory, full conversation transcript                 |
| Asciinema Cast | iTerm2 session UUID, terminal pane ID (`w0t5p2`), profile name, recording start time, PID |

No individual IDs need to be listed separately — the full paths are strictly more informative.

## Skills

- [fork-intelligence](./skills/fork-intelligence/SKILL.md)
- [hooks](./skills/hooks/SKILL.md)
- [issue-create](./skills/issue-create/SKILL.md)
- [issues-workflow](./skills/issues-workflow/SKILL.md)
- [pr-gfm-validator](./skills/pr-gfm-validator/SKILL.md)
- [research-archival](./skills/research-archival/SKILL.md)

## GitHub Operations Policy

**Use gh CLI** for all GitHub operations — WebFetch to github.com is soft-blocked by `webfetch-github-guard.sh`.

**Install gh via Homebrew ONLY**: `brew install gh` (mise causes iTerm2 tab spawning).

**GitHub Actions Policy**: NO testing or linting in GitHub Actions — local-first philosophy.

- **Forbidden**: pytest, jest, cargo test, ruff, eslint, clippy, prettier, mypy
- **Allowed**: semantic-release, CodeQL, Dependabot, deployment

## GitHub Issues as Insight Repository

**CRITICAL**: Only post to repositories owned by `terrylica` (your own repos or forks). NEVER post to upstream third-party repositories.

**Philosophy**: Treat GitHub Issues as human-readable insight repository for research and findings.

**Body Limit**: Issue bodies and comments each support **65,536 characters**. Always aim to maximize a single post — pack comprehensive analysis, multi-perspective reasoning, historical context, and all evidence into one body rather than fragmenting across multiple issues or comments. Target ~60,000 chars to leave headroom. Only split if you genuinely exceed the limit. See [issue-create SKILL.md](./skills/issue-create/SKILL.md) for the pre-post size check pattern.

### When to Post Issue Comments

| Action                  | Safe to Post?            | Example                                                    |
| ----------------------- | ------------------------ | ---------------------------------------------------------- |
| Your own repository     | Always                   | `terrylica/cc-skills`, `terrylica/data-source-manager`     |
| Your fork               | Always                   | `terrylica/claude-code` (fork of `anthropics/claude-code`) |
| Upstream third-party    | NEVER (read-only)        | `anthropics/claude-code`, `jdx/mise`                       |
| Collaborative team repo | If you have write access | Repos where you're a collaborator                          |

### Best Practices

**Post validated findings to relevant GitHub Issues**:

- Comment on open OR closed issues with new insights discovered during research
- Use Issue comments to track evolving understanding (more visible than git commits)
- Reference Issue numbers in commit messages for traceability (e.g., `fix: address issue #123`)
- Create new Issues when discovering genuinely new research directions

**Upstream repositories (read-only)**:

- Search and read existing Issues for insights
- Reference upstream Issue numbers in your own repo's Issues (e.g., "Related to anthropics/claude-code#22055")
- DO NOT comment, create, or modify Issues in upstream repos

**Example workflow**:

1. Discover insight while investigating Claude Code permissions behavior
2. Search `anthropics/claude-code` for related Issues (read-only)
3. Create Issue in `terrylica/cc-skills` documenting findings
4. Reference upstream Issue: "Investigation of anthropics/claude-code#22055 revealed..."
5. Post follow-up findings as comments in YOUR repo's Issue

**Repositories you own**: `terrylica/*` (verify with `gh repo list terrylica`)

## Multi-Account Authentication

This plugin respects the multi-account setup via mise:

```toml
# ~/eon/.mise.toml
[env]
GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"
GH_ACCOUNT = "terrylica"
```

**ADR**: [/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md](/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md)

## Environment Variables

| Variable     | Required | Description                                                                              |
| ------------ | -------- | ---------------------------------------------------------------------------------------- |
| `GH_TOKEN`   | Yes      | GitHub PAT (`ghp_...` / `github_pat_...`); read from mise per-project config             |
| `GH_ACCOUNT` | Yes      | GitHub username for the active token; used by identity guard to verify ownership         |
| `GH_ORGS`    | No       | Comma-separated list of orgs the current account may write to (identity guard allowlist) |

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
