---
status: accepted
date: 2026-01-03
---

# ADR: gh-tools WebFetch Enforcement Hook

**Status**: Accepted
**Date**: 2026-01-03
**Deciders**: Terry Li
**Affects**: gh-tools plugin, ~/.claude/CLAUDE.md

## Context and Problem Statement

When Claude Code needs to access GitHub resources (issues, PRs, repository data), it defaults to using `WebFetch` for github.com URLs. This produces inferior results compared to the `gh` CLI:

| Method   | Raw API Access | Authentication | Rich Data | Pagination |
| -------- | -------------- | -------------- | --------- | ---------- |
| WebFetch | HTML scraping  | None           | Limited   | No         |
| gh CLI   | Native API     | gh auth token  | Full JSON | Automatic  |

Users lose context and functionality when WebFetch is used for GitHub operations instead of gh CLI.

## Decision Drivers

- **Data Quality**: gh CLI provides structured JSON with full metadata
- **Authentication**: gh CLI uses authenticated requests, avoiding rate limits
- **Consistency**: All GitHub operations should use the same tooling
- **User Experience**: Prevent silent degradation of GitHub data access

## Considered Options

### Option 1: CLAUDE.md Guidance Only

- Add policy section to ~/.claude/CLAUDE.md instructing gh CLI preference
- Pros: Zero configuration, immediate effect
- Cons: Soft guidance, may be ignored under context pressure

### Option 2: Separate gh-workflow-enforcer Plugin

- Create new plugin dedicated to GitHub workflow enforcement
- Pros: Clean separation
- Cons: Unnecessary fragmentation, gh-tools already exists for GitHub workflows

### Option 3: Add Hook to gh-tools Plugin ✓

- Extend gh-tools with PreToolUse hook for WebFetch detection
- Pros: Semantic cohesion, single install for GitHub workflow automation
- Cons: Changes skill-only plugin to skills+hooks hybrid

## Decision Outcome

**Chosen option**: Option 3 - Add hook to gh-tools plugin

### Rationale

1. **Semantic cohesion**: gh-tools is already "GitHub workflow automation" - this extends it naturally
2. **Established pattern**: `link-tools`, `dotfiles-tools`, `statusline-tools` all combine skills + hooks
3. **User convenience**: Single `/plugin install cc-skills@gh-tools` gets skill + enforcement
4. **Explicit roadmap**: gh-tools README says "Start Minimal, Expand Later"

## Implementation

### Hook Architecture

```
                               PreToolUse WebFetch Guard

+---------------+     ###################     +------------------------+  No    -------
| WebFetchInput | --> # Parse URLDomain # --> |  github.comdetected?   | ----> | Allow |
+---------------+     ###################     +------------------------+        -------
                                                |
                                                |
                                                v
                                              +------------------------+
                                              | Soft Block+ Suggest gh |
                                              +------------------------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "PreToolUse WebFetch Guard"; flow: east; }
[ WebFetchInput ] -> [ Parse URLDomain ] { border: bold; } -> [ github.comdetected? ] -> [ Soft Block+ Suggest gh ]
[ github.comdetected? ] -- No --> [ Allow ] { shape: rounded; }
```

</details>

### Files Created

| File                                              | Purpose                     |
| ------------------------------------------------- | --------------------------- |
| `plugins/gh-tools/hooks/hooks.json`               | Hook configuration          |
| `plugins/gh-tools/hooks/webfetch-github-guard.sh` | Detection script            |
| `plugins/gh-tools/skills/hooks/SKILL.md`          | `/gh-tools:hooks` installer |

### Hook Behavior

- **Trigger**: PreToolUse when tool = WebFetch
- **Detection**: URL contains `github.com` domain
- **Response**: `permissionDecision: deny` with gh CLI suggestion
- **Bypass**: None (soft block - user can override)

### CLAUDE.md Policy Section

Added to `~/.claude/CLAUDE.md`:

```markdown
## GitHub Operations Policy

**Use gh CLI for all GitHub operations** - WebFetch for github.com URLs is blocked.

| Operation   | Command                           |
| ----------- | --------------------------------- |
| View issue  | `gh issue view <num>`             |
| List issues | `gh issue list --state open`      |
| View PR     | `gh pr view <num>`                |
| API access  | `gh api repos/{owner}/{repo}/...` |
```

## Consequences

### Positive

- Consistent GitHub data quality across all Claude Code sessions
- Prevents silent fallback to inferior WebFetch scraping
- Single installation path via gh-tools
- Follows established skills+hooks pattern in cc-skills

### Negative

- Changes gh-tools from skill-only to hybrid plugin
- Requires hook installation step (`/gh-tools:hooks install`)

### Neutral

- Users can still override with explicit confirmation
- CLAUDE.md policy provides redundant soft guidance

## Related ADRs

- [PreToolUse/PostToolUse Hooks Architecture](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
- [ITP Hooks Settings Installer](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)
