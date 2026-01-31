# Alpha-Forge Worktree Plugin

Git worktree management for alpha-forge with ADR-style naming and dynamic iTerm2 tab detection.

## Installation

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install alpha-forge-worktree@cc-skills
```

## Features

- Natural language worktree creation ("create worktree for sharpe validation")
- Automatic slug derivation from descriptions (word economy rules)
- Three operational modes: new branch, remote tracking, existing branch
- Dynamic iTerm2 tab detection with acronym-based naming (AF-ssv)
- Stale worktree detection and cleanup prompts

## Operational Modes

| Mode             | Trigger Example                             | Action                                |
| ---------------- | ------------------------------------------- | ------------------------------------- |
| **New Branch**   | "create worktree for sharpe validation"     | Derive slug, create branch + worktree |
| **Remote Track** | "create worktree from origin/feat/existing" | Track remote branch in new worktree   |
| **Local Branch** | "create worktree for feat/2025-12-15-my-wt" | Use existing branch in new worktree   |

## Naming Conventions

### Worktree Folders

**Format**: `alpha-forge.worktree-YYYY-MM-DD-slug`

| Branch                                          | Worktree Folder                                                 |
| ----------------------------------------------- | --------------------------------------------------------------- |
| `feat/2025-12-14-sharpe-statistical-validation` | `alpha-forge.worktree-2025-12-14-sharpe-statistical-validation` |
| `feat/new-feature`                              | `alpha-forge.worktree-{TODAY}-new-feature`                      |

### iTerm2 Tab Names

**Format**: `AF-{acronym}` (first char of each word in slug)

| Slug                            | Tab Name |
| ------------------------------- | -------- |
| `sharpe-statistical-validation` | `AF-ssv` |
| `feature-genesis-skills`        | `AF-fgs` |

## Usage

### Create Worktree (Natural Language)

```
# New branch from description
"create worktree for sharpe statistical validation"
→ Claude derives slug: sharpe-statistical-validation
→ Prompts for branch type (feat/fix/refactor/chore)
→ Prompts for base branch (main/develop/other)
→ Creates: feat/2025-12-15-sharpe-statistical-validation

# Track remote branch
"create worktree from origin/feat/2025-12-10-existing-feature"

# Use existing local branch
"create worktree for feat/2025-12-15-my-feature"
```

### Detect Stale Worktrees

```bash
~/eon/cc-skills/plugins/alpha-forge-worktree/skills/worktree-manager/scripts/detect-stale.sh
```

### Cleanup Worktree

```bash
# Remove worktree (keeps branch)
~/eon/cc-skills/plugins/alpha-forge-worktree/skills/worktree-manager/scripts/cleanup-worktree.sh ~/eon/alpha-forge.worktree-2025-12-14-slug

# Remove worktree and delete merged branch
~/eon/cc-skills/plugins/alpha-forge-worktree/skills/worktree-manager/scripts/cleanup-worktree.sh ~/eon/alpha-forge.worktree-2025-12-14-slug --delete-branch
```

## iTerm2 Integration

The plugin integrates with `~/scripts/iterm2/default-layout.py`:

1. On iTerm2 startup, `discover_alpha_forge_worktrees()` globs `~/eon/alpha-forge.worktree-*`
2. Validates each against `git worktree list`
3. Generates `AF-{acronym}` tab names
4. Inserts tabs after the main AF tab

**Note**: Restart iTerm2 to see new worktree tabs.

## Files

```
alpha-forge-worktree/
├── plugin.json                           # Plugin metadata
├── README.md                             # This file
└── skills/
    └── worktree-manager/
        ├── SKILL.md                      # Skill definition (primary entry point)
        ├── references/
        │   └── naming-conventions.md     # Naming reference + slug derivation rules
        └── scripts/
            ├── create-worktree.sh        # Create worktree (3 modes)
            ├── detect-stale.sh           # Detect merged branches
            └── cleanup-worktree.sh       # Remove worktree
```

## Related

- [ADR: Alpha-Forge Git Worktree Management](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)
- [Design Spec](/docs/design/2025-12-14-alpha-forge-worktree-management/spec.md)
