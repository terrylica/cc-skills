---
allowed-tools: Bash(git:*), Bash(fd:*), Read, AskUserQuestion
argument-hint: "[branch-name]"
description: "Create git worktree for alpha-forge branch with ADR-style naming"
---

# Create Alpha-Forge Git Worktree

<!-- ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md -->

Create a git worktree for the specified alpha-forge branch using ADR-style naming convention.

## Input

- **Branch name** (optional): `$ARGUMENTS` - if not provided, list available branches

## Workflow

### Step 1: Validate Environment

```bash
# Verify alpha-forge repo exists
cd ~/eon/alpha-forge && git rev-parse --git-dir
```

### Step 2: Branch Selection

If `$ARGUMENTS` is empty:

1. List available branches:

   ```bash
   cd ~/eon/alpha-forge && git branch -a --format='%(refname:short)' | grep -v '^origin/HEAD'
   ```

2. Use AskUserQuestion to let user select a branch

If `$ARGUMENTS` is provided:

1. Validate branch exists:

   ```bash
   cd ~/eon/alpha-forge && git show-ref --verify --quiet refs/heads/$ARGUMENTS || git show-ref --verify --quiet refs/remotes/origin/$ARGUMENTS
   ```

### Step 3: Extract Date and Slug

Parse the branch name to extract date and slug components:

- **Pattern**: `(feat|fix|refactor|chore)/YYYY-MM-DD-slug` or `(feat|fix|refactor|chore)/slug`
- **If date present**: Use extracted date
- **If no date**: Use today's date

**Examples**:

| Branch                                          | Date       | Slug                          |
| ----------------------------------------------- | ---------- | ----------------------------- |
| `feat/2025-12-14-sharpe-statistical-validation` | 2025-12-14 | sharpe-statistical-validation |
| `feat/new-feature`                              | (today)    | new-feature                   |
| `fix/2025-12-10-bug-fix`                        | 2025-12-10 | bug-fix                       |

### Step 4: Check for Stale Worktrees

Before creating, detect any stale worktrees (branches already merged to main):

```bash
cd ~/eon/alpha-forge
MERGED=$(git branch --merged main | grep -v '^\*' | grep -v 'main' | tr -d ' ')
git worktree list --porcelain | grep '^branch' | cut -d' ' -f2 | while read branch; do
    branch_name="${branch##refs/heads/}"
    if echo "$MERGED" | grep -q "^${branch_name}$"; then
        echo "STALE: $branch_name"
    fi
done
```

If stale worktrees found:

1. Report them to user
2. Use AskUserQuestion to offer cleanup option
3. If user confirms, run cleanup for each stale worktree

### Step 5: Generate Worktree Name

Construct the worktree path using ADR-style naming:

```
~/eon/alpha-forge.worktree-{DATE}-{SLUG}
```

**Example**: `~/eon/alpha-forge.worktree-2025-12-14-sharpe-statistical-validation`

### Step 6: Create Worktree

```bash
cd ~/eon/alpha-forge
git worktree add ~/eon/alpha-forge.worktree-{DATE}-{SLUG} {BRANCH}
```

### Step 7: Generate Tab Name Preview

Extract acronym from slug for iTerm2 tab naming:

- **Slug**: `sharpe-statistical-validation`
- **Words**: `sharpe`, `statistical`, `validation`
- **Acronym**: `ssv` (first char of each word)
- **Tab name**: `AF-ssv`

### Step 8: Report Success

Display to user:

```
✓ Worktree created successfully

  Path: ~/eon/alpha-forge.worktree-{DATE}-{SLUG}
  Branch: {BRANCH}
  Tab name: AF-{acronym}

  Note: Restart iTerm2 to see the new tab in your layout.
```

## Error Handling

- **Branch doesn't exist**: Suggest creating it or fetching from remote
- **Worktree already exists**: Report existing path and skip creation
- **Git errors**: Display full error message for troubleshooting

## Related

- **Skill**: `alpha-forge-worktree:worktree-manager`
- **ADR**: [Alpha-Forge Git Worktree Management](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)
