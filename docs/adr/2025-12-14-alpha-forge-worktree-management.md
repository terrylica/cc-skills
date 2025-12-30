---
status: accepted
date: 2025-12-14
decision-maker: Terry Li
consulted:
  [
    Explore Agent (alpha-forge),
    Explore Agent (cc-skills),
    Explore Agent (default-layout),
  ]
research-method: multi-agent-parallel
clarification-iterations: 3
perspectives: [Developer Experience, Automation, Consistency]
---

# Alpha-Forge Git Worktree Management System

**Design Spec**: [Implementation Spec](/docs/design/2025-12-14-alpha-forge-worktree-management/spec.md)

## Context and Problem Statement

Managing multiple concurrent feature branches in alpha-forge requires frequent context switching. Currently, developers must manually:

1. Create git worktrees with inconsistent naming
2. Manually add tabs to iTerm2's `default-layout.py`
3. Remember which worktree corresponds to which branch
4. Clean up stale worktrees after branches are merged

This creates friction in the development workflow and leads to:

- Inconsistent worktree folder naming
- Orphaned worktrees consuming disk space
- Manual iTerm2 configuration that quickly becomes stale
- Cognitive overhead remembering worktree-to-branch mappings

```
                          Before: Manual Worktree Management

┌──────────────────┐     ┌───────────────────────┐     ┌────────────────────────┐     ┌──────────────────┐
│  Manual Process  │ ──> │    Create worktree    │ ──> │ Edit default-layout.py │ ──> │ Remember mapping │
└──────────────────┘     │    (ad-hoc naming)    │     └────────────────────────┘     └──────────────────┘
  │                      └───────────────────────┘
  │
  ∨
┌──────────────────┐     ┌────────────┐
│  Forget cleanup  │ ──> │ Disk bloat │
└──────────────────┘     └────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Before: Manual Worktree Management"; flow: east; }

[Manual Process] -> [Create worktree\n(ad-hoc naming)] -> [Edit default-layout.py] -> [Remember mapping]
[Manual Process] -> [Forget cleanup] -> [Disk bloat]
```

</details>

## Decision Drivers

- **Consistency**: Worktree naming should follow established ADR slug conventions
- **Automation**: Minimize manual steps in worktree lifecycle
- **Discoverability**: iTerm2 tabs should auto-detect worktrees without config changes
- **Cleanup**: Stale worktrees should be detected and cleanup prompted
- **Specificity**: Focus on alpha-forge workflow (can extend later)

## Considered Options

1. **Manual worktree management** (status quo)
2. **Shell aliases for worktree creation**
3. **Claude Code plugin with slash command + dynamic iTerm2 detection**

## Decision Outcome

**Chosen option**: "Claude Code plugin with slash command + dynamic iTerm2 detection"

### Consequences

**Good**:

- ADR-style naming enforced automatically (`alpha-forge.worktree-YYYY-MM-DD-slug`)
- Tab naming via acronym extraction (`AF-ssv` from `sharpe-statistical-validation`)
- Stale worktree detection with cleanup prompts
- Zero manual iTerm2 config changes needed

**Neutral**:

- Requires plugin installation in cc-skills marketplace
- Alpha-forge specific (by design, can extend later)

**Bad**:

- Additional dependency on Claude Code plugin system
- Detection requires iTerm2 restart to see new tabs

## Architecture

The system consists of three components:

1. **Plugin** (`alpha-forge-worktree`): Slash command + skill for worktree creation
2. **Dynamic Detection** (`default-layout.py`): Auto-discovers worktrees at iTerm2 startup
3. **Lifecycle Management**: Stale detection + cleanup prompts

```
                          Worktree Management Architecture

┌──────────────────┐     ┌─────────────────────────┐
│  /af:wt command  │ ──> │  worktree-manager skill │
└──────────────────┘     └─────────────────────────┘
                           │
                           │
                           ∨
                         ┌─────────────────────────┐     ┌───────────────────┐     ┌──────────────────┐
                         │     Pre-diagnosis:      │ ──> │ Name suggestion:  │ ──> │ git worktree add │
                         │    Branch analysis      │     │    ADR-style      │     └──────────────────┘
                         └─────────────────────────┘     └───────────────────┘
                           │
                           │
                           ∨
                         ┌─────────────────────────┐     ┌──────────────────┐
                         │    Stale detection      │ ──> │  Cleanup prompt  │
                         └─────────────────────────┘     └──────────────────┘

┌───────────────────┐     ┌────────────────────────────────────┐     ┌───────────────────────────────┐     ┌──────────────────────────┐
│ default-layout.py │ ──> │ glob ~/eon/alpha-forge.worktree-*  │ ──> │ Validate with git worktree list │ ──> │ Generate AF-{acronym} tabs │
└───────────────────┘     └────────────────────────────────────┘     └───────────────────────────────┘     └──────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Worktree Management Architecture"; flow: south; }

[/af:wt command] -> [worktree-manager skill]

[worktree-manager skill] -> [Pre-diagnosis:\nBranch analysis] -> [Name suggestion:\nADR-style] -> [git worktree add]
[worktree-manager skill] -> [Stale detection] -> [Cleanup prompt]

[default-layout.py] -> [glob ~/eon/alpha-forge.worktree-*] -> [Validate with git worktree list] -> [Generate AF-{acronym} tabs]
```

</details>

### Worktree Naming Convention

**Format**: `alpha-forge.worktree-YYYY-MM-DD-slug`

**Examples**:

| Branch                                          | Worktree Folder                                                 |
| ----------------------------------------------- | --------------------------------------------------------------- |
| `feat/2025-12-14-sharpe-statistical-validation` | `alpha-forge.worktree-2025-12-14-sharpe-statistical-validation` |
| `feat/2025-12-13-feature-genesis-skills`        | `alpha-forge.worktree-2025-12-13-feature-genesis-skills`        |

### Tab Naming Convention

**Format**: `AF-{acronym}` where acronym = first character of each word in slug

**Examples**:

| Worktree Slug                   | Tab Name   |
| ------------------------------- | ---------- |
| `sharpe-statistical-validation` | `AF-ssv`   |
| `feature-genesis-skills`        | `AF-fgs`   |
| `eth-block-metrics-data-plugin` | `AF-ebmdp` |

### Detection Flow

```
1. Glob: ~/eon/alpha-forge.worktree-*
2. Filter: Validate each with `git worktree list` in alpha-forge
3. Sort: By creation date (extracted from folder name)
4. Name: Extract slug → generate acronym → prefix with AF-
5. Insert: After AF tab, before other tabs
```

## Validation

- [ ] Plugin creates worktrees with correct naming
- [ ] Slug extraction from branch name works correctly
- [ ] Acronym generation produces unique, readable names
- [ ] Dynamic detection finds all valid worktrees
- [ ] Stale detection identifies merged branches
- [ ] Cleanup prompt works without data loss

## More Information

- **Plugin location**: `~/eon/cc-skills/plugins/alpha-forge-worktree/`
- **Primary repo**: `~/eon/alpha-forge` (EonLabs-Spartan/alpha-forge)
- **Related**: Git worktree documentation, ADR naming conventions
