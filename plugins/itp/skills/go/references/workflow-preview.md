**Skill**: [ITP Go Workflow](../SKILL.md)

# Workflow Preview

**Detect branch and show expected workflow before starting.**

```bash
/usr/bin/env bash << 'GIT_EOF'
CURRENT_BRANCH=$(git branch --show-current)
WILL_BE_ON_MAIN=true

# If -b flag used, will end up on feature branch
if [ -n "$BRANCH_FLAG" ]; then
  WILL_BE_ON_MAIN=false
fi

# If already not on main/master
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  WILL_BE_ON_MAIN=false
fi
GIT_EOF
```

**Show workflow preview based on branch and flags:**

| Condition                      | Workflow                            | Message                                               |
| ------------------------------ | ----------------------------------- | ----------------------------------------------------- |
| main/master, no flags          | `Preflight -> 1 -> 2 -> END`        | "Phase 3 skipped. Use -r for release, -p for publish" |
| main/master, `-r`              | `Preflight -> 1 -> 2 -> 3.2`        | "Running semantic-release..."                         |
| main/master, `-p`              | `Preflight -> 1 -> 2 -> 3.3`        | "Running PyPI publish..."                             |
| main/master, `-r -p`           | `Preflight -> 1 -> 2 -> 3.2 -> 3.3` | "Running full release..."                             |
| feature (`-b`), no `-r`/`-p`   | `Preflight -> 1 -> 2 -> END`        | Standard feature branch message                       |
| feature (`-b`), with `-r`/`-p` | `Preflight -> 1 -> 2 -> END`        | Verbose reminder (see Phase 3)                        |

**Phase 3 now requires explicit flags on main/master.** This is a breaking change from previous behavior where Phase 3 ran automatically.
