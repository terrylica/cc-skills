# Alpha-Forge Worktree Naming Conventions

<!-- ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md -->

Reference for worktree folder naming and iTerm2 tab naming conventions.

## Worktree Folder Naming

### Format

```
alpha-forge.worktree-YYYY-MM-DD-slug
```

### Components

| Component     | Description                  | Example                         |
| ------------- | ---------------------------- | ------------------------------- |
| `alpha-forge` | Repository identifier        | Fixed prefix                    |
| `.worktree-`  | Worktree marker              | Fixed delimiter                 |
| `YYYY-MM-DD`  | Date (from branch or today)  | `2025-12-14`                    |
| `slug`        | Descriptive name from branch | `sharpe-statistical-validation` |

### Date Extraction Rules

1. **Branch has date**: Extract from branch name
   - `feat/2025-12-14-feature-name` → `2025-12-14`

2. **Branch without date**: Use today's date
   - `feat/quick-fix` → `{TODAY}`

### Slug Extraction Rules

1. **Standard branch**: Remove prefix and date
   - `feat/2025-12-14-sharpe-statistical-validation` → `sharpe-statistical-validation`

2. **Branch without date**: Remove prefix only
   - `fix/memory-leak` → `memory-leak`

3. **Preserve hyphens**: Keep slug as-is for acronym generation
   - `eth-block-metrics` stays as `eth-block-metrics`

## iTerm2 Tab Naming

### Format

```
AF-{acronym}
```

### Acronym Generation

Take first character of each hyphen-separated word in the slug:

| Slug                            | Words                             | Acronym |
| ------------------------------- | --------------------------------- | ------- |
| `sharpe-statistical-validation` | sharpe, statistical, validation   | `ssv`   |
| `feature-genesis-skills`        | feature, genesis, skills          | `fgs`   |
| `eth-block-metrics-data-plugin` | eth, block, metrics, data, plugin | `ebmdp` |
| `quick-fix`                     | quick, fix                        | `qf`    |
| `memory-leak`                   | memory, leak                      | `ml`    |

### Algorithm

```bash
slug="sharpe-statistical-validation"
acronym=$(echo "$slug" | tr '-' '\n' | cut -c1 | tr -d '\n')
# Result: ssv
```

### Uniqueness

Acronyms are deterministic - same slug always produces same acronym. Collisions indicate:

1. Duplicate branches (shouldn't happen)
2. Need for more descriptive slugs

**Recommendation**: Use 3+ word slugs for better acronym uniqueness.

## Examples

### Complete Mapping

| Branch Name                                     | Worktree Folder                                                 | Tab Name |
| ----------------------------------------------- | --------------------------------------------------------------- | -------- |
| `feat/2025-12-14-sharpe-statistical-validation` | `alpha-forge.worktree-2025-12-14-sharpe-statistical-validation` | `AF-ssv` |
| `feat/2025-12-13-feature-genesis-skills`        | `alpha-forge.worktree-2025-12-13-feature-genesis-skills`        | `AF-fgs` |
| `fix/2025-12-10-memory-leak-fix`                | `alpha-forge.worktree-2025-12-10-memory-leak-fix`               | `AF-mlf` |
| `refactor/code-cleanup`                         | `alpha-forge.worktree-{TODAY}-code-cleanup`                     | `AF-cc`  |

### Edge Cases

| Scenario          | Branch              | Worktree Folder                             | Tab         |
| ----------------- | ------------------- | ------------------------------------------- | ----------- |
| Single word slug  | `feat/hotfix`       | `alpha-forge.worktree-{TODAY}-hotfix`       | `AF-h`      |
| Numbers in slug   | `feat/v2-migration` | `alpha-forge.worktree-{TODAY}-v2-migration` | `AF-vm`     |
| Long acronym (5+) | `feat/a-b-c-d-e-f`  | `alpha-forge.worktree-{TODAY}-a-b-c-d-e-f`  | `AF-abcdef` |

## Validation

### Valid Worktree Names

- Starts with `alpha-forge.worktree-`
- Contains valid date `YYYY-MM-DD`
- Slug contains only `[a-z0-9-]`

### Valid Tab Names

- Starts with `AF-`
- Acronym is lowercase `[a-z]+`
- Minimum 1 character acronym

## Related

- [SKILL.md](../SKILL.md) - Main skill documentation
- [ADR](/docs/adr/2025-12-14-alpha-forge-worktree-management.md) - Architecture decision
