---
name: issue-create
description: Create GitHub issues with AI labeling. TRIGGERS - create issue, file bug, feature request, gh issue create.
allowed-tools: Read, Bash, Grep, Glob
---

# Issue Create Skill

Create well-formatted GitHub issues with intelligent automation including AI-powered label suggestions, content type detection, template formatting, and related issue linking.

## When to Use This Skill

Use this skill when:

- Creating bug reports, feature requests, questions, or documentation issues
- Need AI-powered label suggestions from repository's existing taxonomy
- Want automatic duplicate detection and related issue linking
- Need consistent issue formatting across different repositories

## Invocation

**Slash command**: `/gh-tools:issue-create`

**Natural language triggers**:

- "Create an issue about..."
- "File a bug for..."
- "Submit a feature request..."
- "Report this problem to..."
- "Post an issue on GitHub..."

## Features

### 1. Repository Detection

- Auto-detects repository from current git directory
- Supports explicit `--repo owner/repo` flag
- Checks permissions before attempting to create

### 2. Content Type Detection

- AI-powered detection (gpt-4.1 via gh-models)
- Fallback to keyword matching
- Types: Bug, Feature, Question, Documentation

### 3. Title Extraction

- Extracts informative title from content
- Adds type prefix (Bug:, Feature:, etc.)
- **Maximizes GitHub's 256-character limit** for informative titles

### 4. Template Formatting

- Auto-selects template based on content type
- Bug: Steps to reproduce, Expected/Actual behavior
- Feature: Use case, Proposed solution
- Question: Context, What was tried
- Documentation: Location, Suggested change

### 5. Label Suggestion

- Fetches repository's existing labels
- AI suggests 2-4 relevant labels
- Only suggests labels that exist (taxonomy-aware)
- 24-hour cache for performance

### 6. Related Issues

- Searches for similar issues
- Links related issues in body
- Warns about potential duplicates

### 7. Preview & Confirm

- Full preview before creation
- Dry-run mode available
- Edit option for modifications

## Usage Examples

### Basic Usage

```bash
# From within a git repository
bun ~/eon/cc-skills/plugins/gh-tools/scripts/issue-create.ts \
  --body "Login page crashes when using special characters in password"
```

### With Explicit Repository

```bash
bun ~/eon/cc-skills/plugins/gh-tools/scripts/issue-create.ts \
  --repo owner/repo \
  --body "Feature: Add dark mode support for better accessibility"
```

### Dry Run (Preview Only)

```bash
bun ~/eon/cc-skills/plugins/gh-tools/scripts/issue-create.ts \
  --repo owner/repo \
  --body "Bug: API returns 500 error" \
  --dry-run
```

### With Custom Title and Labels

```bash
bun ~/eon/cc-skills/plugins/gh-tools/scripts/issue-create.ts \
  --repo owner/repo \
  --title "Bug: Login fails with OAuth" \
  --body "Detailed description..." \
  --labels "bug,authentication"
```

### Disable AI Features

```bash
bun ~/eon/cc-skills/plugins/gh-tools/scripts/issue-create.ts \
  --body "Question: How to configure..." \
  --no-ai
```

## CLI Options

| Option      | Short | Description                     |
| ----------- | ----- | ------------------------------- |
| `--repo`    | `-r`  | Repository in owner/repo format |
| `--body`    | `-b`  | Issue body content (required)   |
| `--title`   | `-t`  | Issue title (optional)          |
| `--labels`  | `-l`  | Comma-separated labels          |
| `--dry-run` |       | Preview without creating        |
| `--no-ai`   |       | Disable AI features             |
| `--verbose` | `-v`  | Enable verbose output           |
| `--help`    | `-h`  | Show help                       |

## Dependencies

- `gh` CLI (required) - GitHub CLI tool
- `gh-models` extension (optional) - Enables AI features

### Installing gh-models

```bash
gh extension install github/gh-models
```

## Permission Handling

| Level       | Behavior                                |
| ----------- | --------------------------------------- |
| WRITE/ADMIN | Full functionality                      |
| TRIAGE      | Can apply labels                        |
| READ        | Shows formatted content for manual copy |
| NONE        | Suggests fork workflow                  |

## Logging

Logs to: `~/.claude/logs/gh-issue-create.jsonl`

Events logged:

- `preflight` - Initial checks
- `type_detected` - Content type detection
- `labels_suggested` - Label suggestions
- `related_found` - Related issues search
- `issue_created` - Successful creation
- `dry_run` - Dry run completion

## Related Documentation

- [Content Types Reference](./references/content-types.md)
- [Label Strategy Reference](./references/label-strategy.md)
- [AI Prompts Reference](./references/ai-prompts.md)

## Embedding Images in Issues

GitHub Issues have **no API for programmatic image upload**. The web UI's drag-and-drop uses an internal S3 policy flow that is intentionally not exposed to API clients ([cli/cli#1895](https://github.com/cli/cli/issues/1895)).

### Images Committed to the Repository

For images already committed to the repo, use `github.com/blob/...?raw=true` URLs — **not** `raw.githubusercontent.com`:

```bash
# BROKEN for private repos (no browser cookies on raw.githubusercontent.com)
![img](https://raw.githubusercontent.com/owner/repo/main/path/image.png)

# WORKING for all repos (browser has cookies on github.com, gets signed redirect)
![img](https://github.com/owner/repo/blob/main/path/image.png?raw=true)
```

**Scripting pattern** (11 images → issue body with inline images):

```bash
IMG_BASE="https://github.com/${OWNER}/${REPO}/blob/main/${IMG_DIR}"

gh issue create --title "Feedback with screenshots" --body "$(cat <<EOF
## Item 1
![description](${IMG_BASE}/01-screenshot.png?raw=true)

## Item 2
![description](${IMG_BASE}/02-screenshot.png?raw=true)
EOF
)"
```

See [AP-07 in GFM Anti-Patterns](../issues-workflow/references/gfm-antipatterns.md#ap-07-private-repo-image-urls-render-as-broken) for the full technical explanation.

### Images NOT in the Repository

For images only on disk (not committed), three options:

| Method                   | How                                                   | Permanent?                   |
| ------------------------ | ----------------------------------------------------- | ---------------------------- |
| **Web UI paste**         | Open issue in browser, Ctrl/Cmd+V images into comment | Yes (`user-attachments` CDN) |
| **Web UI drag-and-drop** | Drag image files into the comment box                 | Yes (`user-attachments` CDN) |
| **Commit first**         | `git add` images, push, then use `?raw=true` URLs     | Yes (repo-hosted)            |

There is no CLI-only method to upload images to GitHub's `user-attachments` CDN. Tools like [`gh-attach`](https://zenn.dev/atani/articles/gh-attach-built-with-claude-code?locale=en) work around this by automating a headless browser (Playwright).

---

## Troubleshooting

### "No repository context"

Run from a git directory or use `--repo owner/repo` flag.

### Labels not suggested

- Check if gh-models is installed: `gh extension list`
- Verify repository has labels: `gh label list --repo owner/repo`
- Check label cache: `ls ~/.cache/gh-issue-skill/labels/`

### AI features not working

Install gh-models extension:

```bash
gh extension install github/gh-models
```
