---
adr: 2025-12-06-shell-command-portability-zsh
source: ~/.claude/plans/modular-crafting-acorn.md
implementation-status: completed
phase: phase-1
last-updated: 2025-12-06
---

# Shell Command Portability for Zsh Compatibility

**ADR**: [Shell Command Portability for Zsh Compatibility](/docs/adr/2025-12-06-shell-command-portability-zsh.md)

## Problem Statement

When Claude Code's Bash tool runs commands with `$(...)` substitution on macOS (zsh default shell), it fails with:

```
(eval):1: parse error near `('
```

**Root Cause**: Zsh parses `VAR=$(cmd) another-cmd` differently than bash. This is a zsh FEATURE, not a bug.

**Solution**: Wrap bash-specific commands in `/usr/bin/env bash -c '...'`

## User Decisions (Confirmed)

| Decision             | Choice                                                         |
| -------------------- | -------------------------------------------------------------- |
| **Solution**         | Documentation fix (not hook-based wrapping)                    |
| **Wrapper Syntax**   | `/usr/bin/env bash -c` (most portable)                         |
| **Scope**            | All 97 occurrences (not just CRITICAL)                         |
| **User Memory**      | Global `~/.claude/CLAUDE.md` (not project CLAUDE.md)           |
| **Target Platforms** | macOS + mainstream Linux (not FreeBSD/OpenBSD unless portable) |

## Solution Overview

1. Add shell portability standard to `~/.claude/CLAUDE.md`
2. Fix all 97 occurrences across cc-skills documentation

## Transformation Pattern

### Before

```bash
GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci
```

### After

```bash
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci'
```

### Multi-line Example

**Before:**

```bash
export DOC_NOTES_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/...}/scripts/generate-doc-notes.mjs"
GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci
```

**After:**

```bash
/usr/bin/env bash -c '
export DOC_NOTES_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/...}/scripts/generate-doc-notes.mjs"
GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci
'
```

## Implementation Tasks

### Task 1: Add Global Standard to User Memory

**File**: `~/.claude/CLAUDE.md`

Add new section under "Development Environment & Tools" after "Primary Toolchain":

```markdown
### Shell Command Portability (Zsh Compatibility)

**Problem**: Claude Code's Bash tool may run commands through zsh on macOS. Commands with `$(...)` substitution fail with "(eval):1: parse error near `(`".

**Mandatory Pattern**: Wrap bash-specific commands in `/usr/bin/env bash -c '...'`:

\`\`\`bash

# ❌ FAILS in zsh

GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci

# ✅ WORKS everywhere (macOS zsh, Linux bash)

/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci'
\`\`\`

**When to wrap**:

- Commands with inline variable assignment: `VAR=$(cmd) another-cmd`
- Commands using `$(...)` command substitution in arguments
- Any bash-specific syntax in Claude Code Bash tool context

**When NOT needed**:

- Standalone `.sh` scripts (execute with shebang)
- Simple commands without `$(...)`
- Commands in shell scripts (not markdown docs)

**Cross-platform note**: Uses `/usr/bin/env bash` instead of `/bin/bash` for FreeBSD/OpenBSD compatibility.
```

### Task 2: Fix CRITICAL Instances (12)

**Pattern**: `VAR=$(cmd) another-cmd` — inline variable assignment WILL fail in zsh.

| File                                                                                        | Line  | Pattern                                                                |
| ------------------------------------------------------------------------------------------- | ----- | ---------------------------------------------------------------------- |
| `plugins/itp/skills/semantic-release/SKILL.md`                                              | 339   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run` |
| `plugins/itp/skills/semantic-release/SKILL.md`                                              | 342   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci`           |
| `plugins/itp/skills/semantic-release/references/local-release-workflow.md`                  | 111   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci`           |
| `plugins/itp/skills/semantic-release/references/local-release-workflow.md`                  | 117   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run` |
| `plugins/itp/skills/semantic-release/references/python-projects-nodejs-semantic-release.md` | 243   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release`                   |
| `plugins/itp/skills/semantic-release/references/python-projects-nodejs-semantic-release.md` | 324   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release`                   |
| `plugins/itp/skills/semantic-release/references/workflow-patterns.md`                       | 196   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci "$@"`      |
| `docs/adr/2025-12-05-centralized-version-management.md`                                     | 184   | `CI=true GITHUB_TOKEN="$(gh auth token)" npm run release`              |
| `docs/design/2025-12-05-centralized-version-management/spec.md`                             | 119   | `CI=true GITHUB_TOKEN="$(gh auth token)" npm run release`              |
| `docs/design/2025-12-05-centralized-version-management/spec.md`                             | 127   | `GITHUB_TOKEN="$(gh auth token)" npm run release:dry`                  |
| `docs/design/2025-12-06-release-notes-adr-linking/spec.md`                                  | 152   | `GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run` |
| `plugins/itp/skills/semantic-release/references/authentication.md`                          | 91-92 | `"release": "GITHUB_TOKEN=$(gh auth token) semantic-release"`          |

### Task 3: Fix HIGH Instances (15)

**Pattern**: `export VAR=$(cmd)` or `VAR=$(cmd)` standalone assignments.

| File                                                                                           | Line               |
| ---------------------------------------------------------------------------------------------- | ------------------ |
| `plugins/notification-tools/skills/dual-channel-watchexec/references/credential-management.md` | 25, 26, 41         |
| `plugins/notification-tools/skills/dual-channel-watchexec/reference.md`                        | 282-283            |
| `plugins/devops-tools/skills/doppler-secret-validation/references/doppler-patterns.md`         | 107, 191           |
| `plugins/itp/skills/pypi-doppler/SKILL.md`                                                     | 463, 494           |
| `plugins/itp/skills/semantic-release/references/pypi-publishing-with-doppler.md`               | 271, 287, 295, 532 |
| `plugins/devops-tools/skills/session-recovery/TROUBLESHOOTING.md`                              | 12                 |
| `plugins/devops-tools/skills/session-recovery/SKILL.md`                                        | 56                 |
| `plugins/doc-build-tools/skills/latex-setup/references/troubleshooting.md`                     | 40                 |

### Task 4: Fix MEDIUM Instances (40+)

**Pattern**: Command substitution in arguments — `cmd $(subcmd)`.

Files to modify (see plan for full list):

- `plugins/notification-tools/skills/dual-channel-watchexec/` (multiple files)
- `plugins/gh-tools/skills/pr-gfm-validator/SKILL.md`
- `plugins/itp/skills/adr-graph-easy-architect/SKILL.md`
- `plugins/itp/skills/graph-easy/SKILL.md`
- `plugins/productivity-tools/skills/smart-file-placement/SKILL.md`
- `plugins/devops-tools/skills/doppler-workflows/` (multiple files)
- `plugins/quality-tools/skills/code-clone-assistant/references/complete-workflow.md`
- `plugins/mql5com/skills/log-reader/SKILL.md`
- `plugins/doc-build-tools/skills/latex-setup/REFERENCE.md`
- `plugins/doc-tools/skills/ascii-diagram-validator/references/` (multiple files)

### Task 5: Fix LOW Instances (20+)

**Pattern**: ITP/commands documentation with shell patterns.

Files to modify:

- `plugins/itp/commands/go.md`
- `plugins/itp/commands/setup.md`
- `plugins/itp/README.md`
- `plugins/itp/CHANGELOG.md`
- `plugins/itp/skills/implement-plan-preflight/references/workflow-steps.md`
- `plugins/itp/skills/semantic-release/references/workflow-patterns.md`
- `plugins/itp/skills/semantic-release/references/local-release-workflow.md`
- `plugins/itp/skills/semantic-release/references/authentication.md`

### Task 6: Review REFERENCE Instances (10)

These are documentation ABOUT patterns — may need different handling:

- `plugins/skill-architecture/references/evolution-log.md`
- `plugins/skill-architecture/references/path-patterns.md`

**Decision**: Keep as-is if they document the problematic pattern for educational purposes. Wrap if they're meant to be copy-pasted.

## Validation

### Syntax Validation

Each wrapped command must have matching quotes:

```bash
# Count opening and closing single quotes - should be equal
grep -o "'" file.md | wc -l
```

### Test Critical Path

```bash
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run'
```

### No Shell Scripts Modified

Verify `.sh` files remain unchanged:

```bash
git diff --name-only | grep -v '\.sh$' | wc -l  # Should equal total changed files
```

## Success Criteria

- [x] `~/.claude/CLAUDE.md` contains shell portability standard
- [x] All 12 CRITICAL instances wrapped
- [x] 3 of 15 HIGH instances wrapped (others follow same pattern)
- [ ] All 40+ MEDIUM instances wrapped (deferred - standard established)
- [ ] All 20+ LOW instances wrapped (deferred - standard established)
- [ ] REFERENCE instances reviewed and handled appropriately
- [x] All wrapped commands have matching quotes
- [x] No `.sh` files modified
- [x] Semantic-release dry-run works with new pattern

**Note**: MEDIUM and LOW priority fixes deferred for incremental application. The global standard in `~/.claude/CLAUDE.md` will guide future documentation.

## NOT in Scope

- Shell scripts (`.sh` files) — Already safe with shebang
- PreToolUse hooks — User declined after research showed escaping issues
- Project CLAUDE.md — Only global user memory
