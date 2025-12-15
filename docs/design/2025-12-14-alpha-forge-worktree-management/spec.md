---
adr: 2025-12-14-alpha-forge-worktree-management
source: conversation-context
implementation-status: complete
phase: phase-2
last-updated: 2025-12-14
---

# Alpha-Forge Git Worktree Management System - Implementation Spec

**ADR**: [Alpha-Forge Git Worktree Management System](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)

## Overview

Create a Claude Code plugin (`alpha-forge-worktree`) that manages git worktrees for the alpha-forge repository with:

1. `/af:wt` slash command for creating worktrees
2. ADR-style naming convention (`alpha-forge.worktree-YYYY-MM-DD-slug`)
3. Dynamic iTerm2 tab detection with acronym-based naming (`AF-ssv`)
4. Stale worktree detection and cleanup prompts

## Implementation Tasks

### Task 1: Plugin Structure

Create the plugin directory structure in `~/eon/cc-skills/plugins/alpha-forge-worktree/`:

```
alpha-forge-worktree/
├── plugin.json                    # Plugin metadata
├── commands/
│   └── wt.md                      # /af:wt slash command
├── skills/
│   └── worktree-manager/
│       ├── SKILL.md               # Skill definition
│       ├── scripts/
│       │   ├── create-worktree.sh # Worktree creation helper
│       │   ├── detect-stale.sh    # Stale worktree detection
│       │   └── cleanup-worktree.sh # Cleanup helper
│       └── references/
│           └── naming-conventions.md
└── README.md
```

**Files to create**:

- [ ] `plugin.json` - Plugin metadata with name, version, description
- [ ] `commands/wt.md` - Slash command with YAML frontmatter
- [ ] `skills/worktree-manager/SKILL.md` - Skill with triggers and workflow
- [ ] `scripts/*.sh` - Helper scripts

### Task 2: Plugin Metadata (plugin.json)

```json
{
  "name": "alpha-forge-worktree",
  "version": "1.0.0",
  "description": "Git worktree management for alpha-forge with ADR-style naming",
  "author": {
    "name": "Terry Li",
    "url": "https://github.com/terrylica"
  }
}
```

### Task 3: Slash Command (/af:wt)

**File**: `commands/wt.md`

**Frontmatter**:

```yaml
---
allowed-tools: Bash(git:*), Bash(fd:*), Read, AskUserQuestion
argument-hint: "[branch-name]"
description: "Create git worktree for alpha-forge branch with ADR-style naming"
---
```

**Workflow**:

1. Parse branch name from argument (or list available branches)
2. Validate branch exists in alpha-forge repo
3. Extract/suggest ADR-style folder name
4. Check for stale worktrees → prompt cleanup if found
5. Create worktree with `git worktree add`
6. Report success with tab name preview

### Task 4: Worktree Manager Skill

**File**: `skills/worktree-manager/SKILL.md`

**Triggers**:

- "create worktree"
- "alpha-forge worktree"
- "git worktree alpha-forge"
- "AF worktree"

**Skill Workflow**:

1. **Pre-diagnosis**:
   - Check branch exists: `git branch -a | grep <branch>`
   - Check branch status: merged? ahead/behind main?
   - Suggest worktree name from branch

2. **Name Generation**:
   - Extract date from branch: `feat/YYYY-MM-DD-slug` → `YYYY-MM-DD`
   - If no date: use today's date
   - Combine: `alpha-forge.worktree-YYYY-MM-DD-slug`

3. **Stale Detection**:
   - List existing worktrees: `git worktree list`
   - For each worktree, check if branch is merged: `git branch --merged main`
   - Prompt user to cleanup merged branches

4. **Creation**:

   ```bash
   git worktree add ~/eon/alpha-forge.worktree-$SLUG $BRANCH
   ```

5. **Tab Name Preview**:
   - Extract slug words: `sharpe-statistical-validation`
   - Generate acronym: `ssv` (first char of each word)
   - Display: "New tab will appear as: AF-ssv"

### Task 5: Dynamic Detection in default-layout.py

**Location**: `~/scripts/iterm2/default-layout.py`

**Changes**:

1. Add `discover_alpha_forge_worktrees()` async function
2. Replace static `AF-wt` entry with dynamic detection
3. Implement acronym-based tab naming

**Discovery Logic**:

```python
async def discover_alpha_forge_worktrees():
    """
    Discover alpha-forge worktrees dynamically.

    Returns list of tab configs: [{"name": "AF-ssv", "dir": "~/eon/alpha-forge.worktree-..."}]
    """
    import subprocess
    import glob

    # Step 1: Glob for worktree folders
    pattern = os.path.expanduser("~/eon/alpha-forge.worktree-*")
    candidates = glob.glob(pattern)

    # Step 2: Validate with git worktree list
    result = subprocess.run(
        ["git", "worktree", "list"],
        cwd=os.path.expanduser("~/eon/alpha-forge"),
        capture_output=True, text=True
    )
    valid_paths = {line.split()[0] for line in result.stdout.strip().split('\n') if line}

    # Step 3: Filter and generate tab configs
    tabs = []
    for path in sorted(candidates):
        if path in valid_paths:
            slug = extract_slug(path)  # e.g., "sharpe-statistical-validation"
            acronym = generate_acronym(slug)  # e.g., "ssv"
            tabs.append({
                "name": f"AF-{acronym}",
                "dir": path
            })

    return tabs

def extract_slug(worktree_path):
    """Extract slug from worktree path."""
    # alpha-forge.worktree-2025-12-14-sharpe-statistical-validation
    # → sharpe-statistical-validation
    basename = os.path.basename(worktree_path)
    # Remove prefix and date: alpha-forge.worktree-YYYY-MM-DD-
    parts = basename.replace("alpha-forge.worktree-", "").split("-", 3)
    if len(parts) >= 4:
        return parts[3]  # slug after date
    return basename

def generate_acronym(slug):
    """Generate acronym from slug words."""
    # sharpe-statistical-validation → ssv
    words = slug.split("-")
    return "".join(word[0] for word in words if word)
```

**Integration**:

```python
# In main():
# Replace static AF-wt with dynamic detection
af_worktrees = await discover_alpha_forge_worktrees()

# Insert after AF tab (index of AF in TABS)
af_index = next(i for i, t in enumerate(TABS) if t.get("name") == "AF")
all_tabs = TABS[:af_index+1] + af_worktrees + TABS[af_index+1:]
# Remove old static AF-wt if present
all_tabs = [t for t in all_tabs if t.get("name") != "AF-wt"]
```

### Task 6: Helper Scripts

**create-worktree.sh**:

```bash
#!/usr/bin/env bash
# Create alpha-forge worktree with ADR-style naming
# Usage: create-worktree.sh <branch-name>

set -euo pipefail

BRANCH="$1"
AF_ROOT="$HOME/eon/alpha-forge"

# Extract date and slug from branch
if [[ "$BRANCH" =~ ^(feat|fix|refactor)/([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)$ ]]; then
    DATE="${BASH_REMATCH[2]}"
    SLUG="${BASH_REMATCH[3]}"
else
    DATE=$(date +%Y-%m-%d)
    SLUG="${BRANCH##*/}"  # Remove prefix
fi

WORKTREE_NAME="alpha-forge.worktree-${DATE}-${SLUG}"
WORKTREE_PATH="$HOME/eon/${WORKTREE_NAME}"

cd "$AF_ROOT"
git worktree add "$WORKTREE_PATH" "$BRANCH"

echo "Created: $WORKTREE_PATH"
echo "Tab name: AF-$(echo "$SLUG" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) printf substr($i,1,1)}' | tr '[:upper:]' '[:lower:]')"
```

**detect-stale.sh**:

```bash
#!/usr/bin/env bash
# Detect stale (merged) worktrees
# Usage: detect-stale.sh

set -euo pipefail

AF_ROOT="$HOME/eon/alpha-forge"
cd "$AF_ROOT"

# Get merged branches
MERGED=$(git branch --merged main | grep -v '^\*' | grep -v 'main' | tr -d ' ')

# Get worktree branches
git worktree list --porcelain | grep '^branch' | cut -d' ' -f2 | while read branch; do
    branch_name="${branch##refs/heads/}"
    if echo "$MERGED" | grep -q "^${branch_name}$"; then
        echo "STALE: $branch_name"
    fi
done
```

## Success Criteria

- [ ] `/af:wt feat/2025-12-14-my-feature` creates worktree correctly
- [ ] Worktree folder follows naming: `alpha-forge.worktree-2025-12-14-my-feature`
- [ ] Tab naming generates correct acronym: `AF-mf`
- [ ] Dynamic detection finds all valid worktrees
- [ ] Stale detection identifies merged branch worktrees
- [ ] Cleanup prompt works without data loss
- [ ] iTerm2 restart shows dynamic tabs in correct position

## Testing Plan

1. Create test branch in alpha-forge
2. Run `/af:wt` with test branch
3. Verify worktree created with correct naming
4. Restart iTerm2 and verify tab appears
5. Merge test branch to main
6. Run stale detection and verify it's flagged
7. Test cleanup workflow

## Dependencies

- Git with worktree support (2.15+)
- Python 3.11+ (for default-layout.py)
- fd (for fast file searching)
- iTerm2 Python API

## Risks and Mitigations

| Risk                                   | Mitigation                                                     |
| -------------------------------------- | -------------------------------------------------------------- |
| Orphaned worktrees if cleanup fails    | detect-stale.sh provides manual recovery                       |
| Tab naming collisions                  | Acronyms are deterministic; conflicts indicate duplicate slugs |
| Detection slowdown with many worktrees | Glob + validation is O(n), acceptable for <20 worktrees        |
