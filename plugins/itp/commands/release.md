---
name: release
description: Run semantic-release with preflight checks. TRIGGERS - npm run release, version bump, changelog, release automation.
allowed-tools: Read, Bash, Glob, Grep, Edit, AskUserQuestion, TodoWrite
argument-hint: "[--dry] [--skip-preflight]"
---

<!-- ⛔⛔⛔ MANDATORY: LOAD THE SEMANTIC-RELEASE SKILL FIRST ⛔⛔⛔ -->

# /itp:release

**FIRST ACTION**: Read the semantic-release skill to load the complete workflow knowledge:

```
Read: ${CLAUDE_PLUGIN_ROOT}/skills/semantic-release/SKILL.md
Read: ${CLAUDE_PLUGIN_ROOT}/skills/semantic-release/references/local-release-workflow.md
```

This command wraps the [semantic-release skill](../skills/semantic-release/SKILL.md) with automatic preflight validation.

## Arguments

| Flag               | Short | Description                                      |
| ------------------ | ----- | ------------------------------------------------ |
| `--dry`            | `-d`  | Dry-run mode (preview changes, no modifications) |
| `--skip-preflight` | `-s`  | Skip preflight checks (use with caution)         |

## Examples

```bash
/itp:release          # Full release with preflight
/itp:release --dry    # Preview what would be released
/itp:release -d       # Same as --dry
```

---

## ⛔ MANDATORY: Load Skill Knowledge First

Before executing ANY release steps, you MUST read these files to load the semantic-release skill:

1. **SKILL.md** — Core workflow, conventional commits, MAJOR confirmation
2. **local-release-workflow.md** — 4-phase release process (PREFLIGHT → SYNC → RELEASE → POSTFLIGHT)

```bash
# Environment-agnostic paths
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/cc-skills/itp/*/skills/semantic-release}"
```

**After reading the skill files, follow the Local Release Workflow (4 phases).**

---

## Execution Flow (from skill)

```
                 Release Workflow Pipeline

 -----------      +------+     +---------+      ------------
| PREFLIGHT | --> | SYNC | --> | RELEASE | --> | POSTFLIGHT |
 -----------      +------+     +---------+      ------------
```

### Phase 1: Preflight

**From skill: Section 1.1-1.5**

1. **Git Cache Refresh** (MANDATORY first step)

   ```bash
   git update-index --refresh -q || true
   ```

2. **Tooling Check** — gh CLI, semantic-release, git repo, main branch, clean directory

3. **Authentication Check** — Verify correct GitHub account via `gh api user --jq '.login'`

4. **Releasable Commits Validation** — Must have `feat:`, `fix:`, or `BREAKING CHANGE:` since last tag

5. **MAJOR Version Confirmation** — If breaking changes detected, spawn 3 Task subagents + AskUserQuestion

### Phase 2: Sync

```bash
git pull --rebase origin main
git push origin main
```

### Phase 3: Release

**If --dry flag:**

```bash
npm run release:dry
```

**Production:**

```bash
npm run release
```

### Phase 4: Postflight

1. Verify pristine state: `git status --porcelain`
2. Verify release: `gh release list --limit 1`
3. Update tracking refs: `git fetch origin main:refs/remotes/origin/main --no-tags`
4. Plugin cache sync (cc-skills only): Automatic via successCmd

---

## Quick Reference

| Scenario                  | Command              | Result                        |
| ------------------------- | -------------------- | ----------------------------- |
| Standard release          | `/itp:release`       | Load skill → 4-phase workflow |
| Preview changes           | `/itp:release --dry` | Load skill → Dry-run only     |
| Force release (dangerous) | `/itp:release -s`    | Skip preflight → Release      |

---

## Error Recovery (from skill)

| Error                       | Resolution                                                                        |
| --------------------------- | --------------------------------------------------------------------------------- |
| Working directory not clean | `git stash` or `git commit`                                                       |
| Not on main branch          | `git checkout main`                                                               |
| Wrong GitHub account        | `gh auth switch --user <correct-account>`                                         |
| No releasable commits       | Create a `feat:` or `fix:` commit first                                           |
| MAJOR version detected      | Follow skill's multi-perspective analysis                                         |
| Release failed              | Check [Troubleshooting](../skills/semantic-release/references/troubleshooting.md) |

---

## Skill Reference (MUST READ)

- **[semantic-release SKILL](../skills/semantic-release/SKILL.md)** — Full documentation, MAJOR confirmation workflow
- **[Local Release Workflow](../skills/semantic-release/references/local-release-workflow.md)** — Canonical 4-phase process
- [Troubleshooting](../skills/semantic-release/references/troubleshooting.md) — Common issues and solutions
- [Authentication](../skills/semantic-release/references/authentication.md) — Multi-account GitHub setup

## Troubleshooting

| Issue                     | Cause                     | Solution                                                                          |
| ------------------------- | ------------------------- | --------------------------------------------------------------------------------- |
| Working dir not clean     | Uncommitted changes       | Run `git stash` or commit changes                                                 |
| Not on main branch        | Wrong branch checked out  | Run `git checkout main`                                                           |
| No releasable commits     | Only chore/docs commits   | Add a feat: or fix: commit                                                        |
| Release failed            | Auth or network issue     | Check [Troubleshooting](../skills/semantic-release/references/troubleshooting.md) |
| npm run release not found | Missing script in package | Check package.json has release script                                             |
| Wrong GitHub account      | Multi-account confusion   | Check token with `echo $GITHUB_TOKEN`                                             |
