---
description: "Manage alpha-forge git worktrees with ADR-style naming, acronym tab names, and stale detection"
---

# Alpha-Forge Worktree Manager

<!-- ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md -->

Create and manage git worktrees for the alpha-forge repository with consistent naming conventions and lifecycle management.

## Triggers

- "create worktree"
- "alpha-forge worktree"
- "git worktree alpha-forge"
- "AF worktree"
- "new worktree for alpha-forge"
- "manage worktrees"

## Naming Conventions

### Worktree Folder Naming (ADR-Style)

**Format**: `alpha-forge.worktree-YYYY-MM-DD-slug`

**Location**: `~/eon/`

**Examples**:

| Branch                                          | Worktree Folder                                                 |
| ----------------------------------------------- | --------------------------------------------------------------- |
| `feat/2025-12-14-sharpe-statistical-validation` | `alpha-forge.worktree-2025-12-14-sharpe-statistical-validation` |
| `feat/2025-12-13-feature-genesis-skills`        | `alpha-forge.worktree-2025-12-13-feature-genesis-skills`        |
| `fix/quick-patch`                               | `alpha-forge.worktree-{TODAY}-quick-patch`                      |

### iTerm2 Tab Naming (Acronym-Based)

**Format**: `AF-{acronym}` where acronym = first character of each word in slug

**Examples**:

| Worktree Slug                   | Tab Name   |
| ------------------------------- | ---------- |
| `sharpe-statistical-validation` | `AF-ssv`   |
| `feature-genesis-skills`        | `AF-fgs`   |
| `eth-block-metrics-data-plugin` | `AF-ebmdp` |

## Workflow

### 1. Pre-Diagnosis

Before creating a worktree, analyze the target branch:

```bash
# Check if branch exists locally or remotely
cd ~/eon/alpha-forge
git show-ref --verify refs/heads/{BRANCH} 2>/dev/null || \
git show-ref --verify refs/remotes/origin/{BRANCH} 2>/dev/null

# Check branch status relative to main
git log --oneline main..{BRANCH} | head -5   # Commits ahead
git log --oneline {BRANCH}..main | head -5   # Commits behind
```

Report to user:

- Branch exists: ✓/✗
- Commits ahead of main: N
- Commits behind main: N
- Suggested worktree name

### 2. Name Generation

Extract date and slug from branch name:

```bash
# Pattern: (feat|fix|refactor|chore)/YYYY-MM-DD-slug
# Or: (feat|fix|refactor|chore)/slug (use today's date)

BRANCH="feat/2025-12-14-sharpe-statistical-validation"

# Extract components
if [[ "$BRANCH" =~ ^(feat|fix|refactor|chore)/([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)$ ]]; then
    DATE="${BASH_REMATCH[2]}"
    SLUG="${BASH_REMATCH[3]}"
else
    DATE=$(date +%Y-%m-%d)
    SLUG="${BRANCH##*/}"
fi

WORKTREE_NAME="alpha-forge.worktree-${DATE}-${SLUG}"
```

### 3. Stale Worktree Detection

Check for worktrees whose branches are already merged to main:

```bash
cd ~/eon/alpha-forge

# Get branches merged to main
MERGED=$(git branch --merged main | grep -v '^\*' | grep -v 'main' | tr -d ' ')

# Check each worktree
git worktree list --porcelain | grep '^branch' | cut -d' ' -f2 | while read branch; do
    branch_name="${branch##refs/heads/}"
    if echo "$MERGED" | grep -q "^${branch_name}$"; then
        # Find worktree path for this branch
        path=$(git worktree list | grep "\[${branch_name}\]" | awk '{print $1}')
        echo "STALE: $branch_name at $path"
    fi
done
```

If stale worktrees found:

1. List them with branch name and path
2. Prompt user to cleanup using AskUserQuestion
3. If confirmed, execute cleanup (see Cleanup section)

### 4. Worktree Creation

```bash
cd ~/eon/alpha-forge

# For local branch
git worktree add ~/eon/${WORKTREE_NAME} ${BRANCH}

# For remote branch (creates local tracking branch)
git worktree add ~/eon/${WORKTREE_NAME} -b ${LOCAL_BRANCH} origin/${BRANCH}
```

### 5. Tab Name Generation

Generate acronym for iTerm2 tab:

```bash
# Extract acronym from slug
SLUG="sharpe-statistical-validation"
ACRONYM=$(echo "$SLUG" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) printf substr($i,1,1)}')
TAB_NAME="AF-${ACRONYM}"

echo "Tab name: $TAB_NAME"  # AF-ssv
```

### 6. Success Report

After creation, display:

```
✓ Worktree created successfully

  Path:    ~/eon/alpha-forge.worktree-2025-12-14-sharpe-statistical-validation
  Branch:  feat/2025-12-14-sharpe-statistical-validation
  Tab:     AF-ssv

  iTerm2 Integration:
  - Restart iTerm2 to see the new tab automatically
  - Tab will appear after the main AF tab
```

## Cleanup Workflow

### Remove Stale Worktree

```bash
# Remove worktree (keeps branch)
git worktree remove ~/eon/alpha-forge.worktree-{DATE}-{SLUG}

# Optionally delete merged branch
git branch -d {BRANCH}
```

### Prune Orphaned Entries

```bash
# Clean up worktree metadata for removed directories
git worktree prune
```

## Error Handling

### Branch Not Found

```
✗ Branch 'feat/nonexistent' not found

  Available branches:
  - feat/2025-12-14-sharpe-statistical-validation
  - main

  To create from remote:
  git fetch origin && /af:wt origin/branch-name
```

### Worktree Already Exists

```
✗ Worktree already exists for this branch

  Existing path: ~/eon/alpha-forge.worktree-2025-12-14-sharpe-statistical-validation

  To use existing worktree:
  cd ~/eon/alpha-forge.worktree-2025-12-14-sharpe-statistical-validation
```

### Path Conflict

```
✗ Directory already exists: ~/eon/alpha-forge.worktree-2025-12-14-slug

  This directory exists but is not registered as a worktree.

  Options:
  1. Remove directory and retry
  2. Choose different slug name
```

## Integration

### iTerm2 Dynamic Detection

The `default-layout.py` script auto-discovers worktrees:

1. Globs `~/eon/alpha-forge.worktree-*`
2. Validates each against `git worktree list`
3. Generates `AF-{acronym}` tab names
4. Inserts tabs after main AF tab

### Slash Command

Use `/af:wt [branch-name]` for quick worktree creation.

## References

- [Naming Conventions](./references/naming-conventions.md)
- [ADR: Alpha-Forge Git Worktree Management](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)
- [Design Spec](/docs/design/2025-12-14-alpha-forge-worktree-management/spec.md)
