# Alpha-Forge Worktree Plugin

Git worktree management for alpha-forge with ADR-style naming and dynamic iTerm2 tab detection.

## Features

- `/af:wt [branch-name]` - Create worktree with ADR-style naming
- Dynamic iTerm2 tab detection with acronym-based naming (AF-ssv)
- Stale worktree detection and cleanup prompts
- Helper scripts for worktree lifecycle management

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

### Create Worktree

```bash
# With Claude Code
/af:wt feat/2025-12-14-my-feature

# Or use the skill
"create alpha-forge worktree for feat/2025-12-14-my-feature"
```

### Detect Stale Worktrees

```bash
# Run detection script
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
├── commands/
│   └── wt.md                             # /af:wt slash command
└── skills/
    └── worktree-manager/
        ├── SKILL.md                      # Skill definition
        ├── references/
        │   └── naming-conventions.md     # Naming reference
        └── scripts/
            ├── create-worktree.sh        # Create worktree
            ├── detect-stale.sh           # Detect merged branches
            └── cleanup-worktree.sh       # Remove worktree
```

## Related

- [ADR: Alpha-Forge Git Worktree Management](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)
- [Design Spec](/docs/design/2025-12-14-alpha-forge-worktree-management/spec.md)
