---
name: release
description: Run semantic-release with preflight checks. TRIGGERS - npm run release, version bump, changelog, release automation.
allowed-tools: Read, Bash, Glob, Grep, Edit, AskUserQuestion, TodoWrite
argument-hint: "[--dry] [--skip-preflight]"
---

# /itp:release

Standalone semantic-release command with automatic preflight validation.

## Arguments

| Flag              | Short | Description                                      |
| ----------------- | ----- | ------------------------------------------------ |
| `--dry`           | `-d`  | Dry-run mode (preview changes, no modifications) |
| `--skip-preflight`| `-s`  | Skip preflight checks (use with caution)         |

## Examples

```bash
/itp:release          # Full release with preflight
/itp:release --dry    # Preview what would be released
/itp:release -d       # Same as --dry
```

---

## Execution Flow

```
                    /itp:release Workflow

 -----------      +-----------+      +---------+      ------------
| PREFLIGHT | --> | DRY-RUN?  | --> | RELEASE | --> | POSTFLIGHT |
 -----------      +-----------+      +---------+      ------------
```

### Phase 1: Preflight (unless --skip-preflight)

Execute these checks in order. STOP on first failure:

```bash
# 1. Clear git cache
git update-index --refresh -q || true

# 2. Check working directory
if [ -n "$(git status --porcelain)" ]; then
  echo "PREFLIGHT FAILED: Working directory not clean"
  git status --short
  # STOP - ask user to commit or stash
fi

# 3. Verify on main branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "PREFLIGHT FAILED: Not on main branch (on: $BRANCH)"
  # STOP - ask user to checkout main
fi

# 4. Verify GitHub account
ACCOUNT=$(gh api user --jq '.login' 2>/dev/null)
echo "GitHub account: $ACCOUNT"
# If wrong account, suggest: gh auth switch --user <correct>

# 5. Check for releasable commits
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
RELEASABLE=$(git log "${LAST_TAG}..HEAD" --oneline | grep -E "^[a-f0-9]+ (feat|fix|BREAKING)" || true)
if [ -z "$RELEASABLE" ]; then
  echo "PREFLIGHT FAILED: No releasable commits since $LAST_TAG"
  echo "Use feat: or fix: prefix for version-bumping changes"
  # STOP - nothing to release
fi
```

### Phase 2: Release

**If --dry flag provided:**
```bash
npm run release:dry
```

**Otherwise (production release):**
```bash
npm run release
```

### Phase 3: Postflight

After successful release:

1. Verify new tag created: `git describe --tags --abbrev=0`
2. Verify GitHub release: `gh release list --limit 1`
3. Report success with new version number

---

## Quick Reference

| Scenario                  | Command               | Result                              |
| ------------------------- | --------------------- | ----------------------------------- |
| Standard release          | `/itp:release`        | Preflight → Release → Postflight    |
| Preview changes           | `/itp:release --dry`  | Preflight → Dry-run (no changes)    |
| Force release (dangerous) | `/itp:release -s`     | Skip preflight → Release            |

---

## Error Recovery

| Error                        | Resolution                                    |
| ---------------------------- | --------------------------------------------- |
| Working directory not clean  | `git stash` or `git commit`                   |
| Not on main branch           | `git checkout main`                           |
| Wrong GitHub account         | `gh auth switch --user <correct-account>`     |
| No releasable commits        | Create a `feat:` or `fix:` commit first       |
| Release failed               | Check logs, fix issue, retry                  |

---

## Reference

- [Local Release Workflow](../skills/semantic-release/references/local-release-workflow.md) - Detailed 4-phase process
- [semantic-release SKILL](../skills/semantic-release/SKILL.md) - Full documentation
- [Troubleshooting](../skills/semantic-release/references/troubleshooting.md) - Common issues
