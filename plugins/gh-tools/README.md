# gh-tools Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-1-blue.svg)]()
[![Hooks](https://img.shields.io/badge/Hooks-1-orange.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

GitHub workflow automation for Claude Code with intelligent link validation, PR management, and gh CLI enforcement.

> [!NOTE]
> **Start Minimal, Expand Later**: This plugin began with PR link validation and now includes WebFetch enforcement to ensure consistent use of gh CLI for all GitHub operations.

## Features

### Skills

- **PR Link Validation**: Detect and auto-fix broken GFM links in PR descriptions
- **Smart Branch Detection**: Only activates when on a feature branch creating PRs
- **Auto-Convert Links**: Transform repo-relative paths to full blob URLs with correct branch
- **Pre-flight Checks**: Validate links before `gh pr create` to prevent 404s

### Hooks

- **WebFetch Enforcement**: Soft-blocks WebFetch for github.com URLs, suggests gh CLI alternatives
- **Smart Suggestions**: Detects issue/PR/repo URLs and provides specific gh commands
- **User Override**: Soft block allows user to proceed if needed

## The Problem This Solves

When creating pull requests from feature branches, repository-relative links in PR descriptions break:

```markdown
# In PR description (BROKEN)

[ADR](/docs/adr/2025-12-01-file.md) → Resolves to main branch → 404!

# What it should be (WORKING)

[ADR](https://github.com/Org/Repo/blob/feat/branch/docs/adr/2025-12-01-file.md)
```

**Why?** PR descriptions resolve `/path/file.md` to the **base branch** (main), not the feature branch. Files that only exist on the feature branch return 404.

## Bundled Skills

| Skill                | Purpose                                      | Trigger Keywords                                                   |
| -------------------- | -------------------------------------------- | ------------------------------------------------------------------ |
| **pr-gfm-validator** | Validate and auto-fix GFM links in PR bodies | `pr create`, `pull request`, `gfm link`, `pr links`, `validate pr` |

## How It Works

### Automatic Activation

The skill auto-activates when:

1. You're on a feature branch (not main/master)
2. You're creating a PR or discussing PR content
3. You mention GFM links, PR validation, or link fixing

### Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    PR Creation Workflow                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│   1. Detect Context                                               │
│      ├── Current branch (feature branch?)                         │
│      ├── Repository URL (GitHub?)                                 │
│      └── Base branch (main/master)                                │
│                                                                   │
│   2. Analyze PR Body                                              │
│      ├── Find all GFM links: [text](url)                          │
│      ├── Identify repo-relative links: /path/to/file.md          │
│      └── Check if files exist on feature branch                   │
│                                                                   │
│   3. Convert Links                                                │
│      ├── /path/file.md                                            │
│      │   ↓                                                        │
│      │   https://github.com/{owner}/{repo}/blob/{branch}/path/... │
│      └── Preserve external URLs unchanged                         │
│                                                                   │
│   4. Validate Result                                              │
│      ├── All links now point to correct branch                    │
│      └── Ready for gh pr create                                   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Link Conversion Rules

| Original                   | Converted To                                                                   |
| -------------------------- | ------------------------------------------------------------------------------ |
| `/docs/file.md`            | `https://github.com/Owner/Repo/blob/branch-name/docs/file.md`                  |
| `./relative/file.md`       | `https://github.com/Owner/Repo/blob/branch-name/current/path/relative/file.md` |
| `https://external.com/...` | (unchanged)                                                                    |
| `#anchor-link`             | (unchanged)                                                                    |

## Installation

```bash
# Via Claude Code plugin manager
/plugin install cc-skills@gh-tools
```

### Installing Hooks

After plugin installation, enable the WebFetch enforcement hook:

```bash
# Check hook status
/gh-tools:hooks status

# Install hooks
/gh-tools:hooks install

# IMPORTANT: Restart Claude Code for hooks to take effect
```

The hook soft-blocks WebFetch requests to github.com and suggests gh CLI alternatives:

```
[gh-tools] WebFetch to github.com detected

URL: https://github.com/owner/repo/issues/123

Use gh CLI instead for better data access:
  gh issue view 123 --repo owner/repo

Why gh CLI is preferred:
- Authenticated requests (no rate limits)
- Full JSON metadata (not HTML scraping)
- Pagination handled automatically
- Comments, labels, assignees included
```

## Usage Examples

### Creating a PR with Link Validation

```bash
# Claude Code will auto-activate when you say:
"Create a PR for this feature branch with links to the ADRs"

# Or explicitly:
"Validate the GFM links before creating the PR"
```

### Manual Validation

```bash
# Claude Code will:
1. Detect you're on feat/my-feature branch
2. Find all /path/file.md links in PR body
3. Convert them to https://github.com/Org/Repo/blob/feat/my-feature/path/file.md
4. Create PR with valid links
```

## Technical Details

### Context Detection

```bash
# Get repository info
gh repo view --json nameWithOwner,url

# Get current branch
git rev-parse --abbrev-ref HEAD

# Construct blob URL
https://github.com/{owner}/{repo}/blob/{branch}/{path}
```

### Link Patterns Detected

1. **Repo-root relative**: `/docs/adr/file.md`
2. **Directory relative**: `./sibling.md`, `../parent/file.md`
3. **Already absolute**: `https://github.com/...` (skipped)
4. **Anchors**: `#section-header` (skipped)
5. **External**: `https://example.com/...` (skipped)

## Roadmap

Future skills to be added to gh-tools:

- [ ] **issue-manager**: GitHub Issues search, create, and bulk operations
- [ ] **release-notes**: Auto-generate release notes from commits
- [ ] **pr-template**: Smart PR description templates per project
- [ ] **check-status**: Monitor CI/CD status and report failures

## References

- [ADR: gh-tools WebFetch Enforcement](/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md)
- [GitHub Relative Links](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#relative-links)
- [GFM Specification](https://github.github.com/gfm/)
- [GitHub CLI Documentation](https://cli.github.com/manual/)

---

**Built for Claude Code CLI** | Designed for minimal friction, maximum reliability
