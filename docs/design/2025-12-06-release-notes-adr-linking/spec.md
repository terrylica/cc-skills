---
adr: 2025-12-06-release-notes-adr-linking
source: ~/.claude/plans/memoized-cooking-nygaard.md
implementation-status: completed
phase: phase-3
last-updated: 2025-12-06
---

# ADR/Design Spec Links in Release Notes

**ADR**: [ADR/Design Spec Links in Release Notes](/docs/adr/2025-12-06-release-notes-adr-linking.md)

## Problem Statement

When semantic-release creates a GitHub release, the release notes only contain the commit-based changelog. Users want to see which Architecture Decision Records (ADRs) and Design Specs were involved since the last release, with clickable links.

## User Decisions (Confirmed)

| Decision             | Choice                                              |
| -------------------- | --------------------------------------------------- |
| **Detection Method** | Both: git diff + commit message parsing (union)     |
| **Link Format**      | Full HTTPS URLs (required for GitHub release pages) |
| **Placement**        | Bottom of release notes (after changelog)           |
| **Artifacts**        | Both ADRs AND Design Specs                          |

## Solution Overview

Extend the existing `semantic-release` skill with ADR/Design Spec linking capability:

1. Add `generate-adr-notes.mjs` to existing `scripts/` directory
2. Create `references/adr-release-linking.md` following skill's reference pattern
3. Update `SKILL.md` with new section and reference link
4. Update `resources.md` to document the new script
5. Use `@semantic-release/exec` with `generateNotesCmd` in `.releaserc.yml`

## Expected Output Format

```markdown
[existing release notes from @semantic-release/release-notes-generator]

---

## Architecture Decisions

### ADRs

- [Centralized Version Management](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-05-centralized-version-management.md) (accepted)

### Design Specs

- [Centralized Version Management Spec](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-05-centralized-version-management/spec.md)
```

## Files to Modify (Holistic Integration)

| File                                                                    | Action     | Description                                             |
| ----------------------------------------------------------------------- | ---------- | ------------------------------------------------------- |
| `plugins/itp/skills/semantic-release/scripts/generate-adr-notes.mjs`    | **Create** | Shareable script for ADR/spec detection                 |
| `plugins/itp/skills/semantic-release/references/adr-release-linking.md` | **Create** | Reference doc following skill's backlink pattern        |
| `plugins/itp/skills/semantic-release/SKILL.md`                          | **Modify** | Add section + reference link after Conventional Commits |
| `plugins/itp/skills/semantic-release/references/resources.md`           | **Modify** | Document new script in hub document                     |
| `.releaserc.yml` (cc-skills)                                            | **Modify** | Add `generateNotesCmd` as example usage                 |

## Implementation Tasks

### Task 1: Create generate-adr-notes.mjs Script

**Location**: `plugins/itp/skills/semantic-release/scripts/generate-adr-notes.mjs`

**Key Features**:

- Dynamic repo URL detection via `git remote get-url origin`
- Union of git diff and commit message parsing
- Full HTTPS URLs for GitHub release pages
- Handles first release (no prior tag) gracefully
- Silent exit if no ADRs found

**Key Functions**:

- `getChangedFiles(lastTag)` - Git diff for ADR/design files
- `parseCommitMessages(lastTag)` - Extract ADR slugs from commits
- `extractTitle(filePath)` - Get H1 from markdown
- `extractStatus(filePath)` - Get status from YAML frontmatter
- `findDesignSpec(adrSlug)` - Check for corresponding spec

### Task 2: Create Reference Documentation

**Location**: `plugins/itp/skills/semantic-release/references/adr-release-linking.md`

**Follow skill's backlink pattern**:

- Start with `**Skill**: [semantic-release](../SKILL.md)`
- Document configuration, usage, and output format
- Include related links to other skills

### Task 3: Update SKILL.md

**Add new section** after Conventional Commits examples:

- Quick Setup with YAML configuration
- How It Works explanation
- Reference link to detailed documentation

**Add reference link** in Reference Documentation section.

### Task 4: Update resources.md

**Add script documentation** in resources hub document.

### Task 5: Modify .releaserc.yml

**Consolidate exec entries** - Combine `generateNotesCmd` with existing `prepareCmd`:

```yaml
# ADR/Design Spec links + version sync via @semantic-release/exec
# ADR: 2025-12-06-release-notes-adr-linking
- - "@semantic-release/exec"
  - generateNotesCmd: 'node "$ADR_NOTES_SCRIPT" ${lastRelease.gitTag}'
    prepareCmd: "node scripts/sync-versions.mjs ${nextRelease.version}"
```

**Note**: Uses `$ADR_NOTES_SCRIPT` (no braces) because `@semantic-release/exec` processes commands through lodash templates which interpret `${...}` as JavaScript. Set the environment variable before running semantic-release:

```bash
export ADR_NOTES_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}/skills/semantic-release/scripts/generate-adr-notes.mjs"
```

## Validation Strategy

### Script Validation

```bash
# Syntax check
node --check plugins/itp/skills/semantic-release/scripts/generate-adr-notes.mjs

# Execution with tag
node plugins/itp/skills/semantic-release/scripts/generate-adr-notes.mjs v2.8.0

# First release simulation
node plugins/itp/skills/semantic-release/scripts/generate-adr-notes.mjs
```

### YAML Validation

```bash
node -e "require('js-yaml').load(require('fs').readFileSync('.releaserc.yml'))"
```

### Dry-Run Release Test

```bash
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run'
```

## Success Criteria

| Gate          | Validation Command                      | Expected                 |
| ------------- | --------------------------------------- | ------------------------ |
| Script syntax | `node --check generate-adr-notes.mjs`   | Exit 0                   |
| First release | `node generate-adr-notes.mjs` (no args) | Exit 0                   |
| With tag      | `node generate-adr-notes.mjs v2.8.0`    | Markdown output or empty |
| YAML valid    | YAML lint check                         | Exit 0                   |
| Dry run       | `npx semantic-release --dry-run`        | No errors                |
| Output format | Contains expected markdown headers      | All markers found        |
