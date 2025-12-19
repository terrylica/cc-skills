---
status: implemented
date: 2025-12-07
decision-maker: Terry Li
consulted: [Hook-Idempotency-Agent, Script-Idempotency-Agent, State-Data-Agent]
research-method: 9-agent-parallel-dctl
clarification-iterations: 4
perspectives: [StandaloneComponent, EcosystemArtifact]
---

# ADR: Idempotency Fixes with Format-Aware Backup Traceability

**Design Spec**: [Implementation Spec](/docs/design/2025-12-07-idempotency-backup-traceability/spec.md)

## Context and Problem Statement

The cc-skills codebase contains 8 shell scripts across 5 plugins that exhibit idempotency issues. When these scripts are re-run (intentionally or accidentally), they produce inconsistent results: failing on re-run, creating duplicate entries, losing user customizations, or corrupting state files.

The core problem is that operations that should be safe to repeat are not designed with idempotency in mind, leading to:

- Directory creation that fails if directory exists
- File appends that duplicate content on re-run
- Config overwrites that lose user customizations without backup
- Temporary files without proper cleanup
- Unbounded log growth without rotation

### Before/After

**Before** (non-idempotent):

```
   ⏮️ Before: Non-Idempotent Operations

┌──────────────┐     ┌────────────────────┐
│ Script Run 1 │ ──> │   Creates State    │
└──────────────┘     └────────────────────┘
┌──────────────┐     ┌────────────────────┐
│ Script Run 2 │ ──> │ Fails / Duplicates │
└──────────────┘     └────────────────────┘
  │
  ∨
┌──────────────┐
│  Overwrites  │
└──────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Non-Idempotent Operations"; flow: east; }
[ Script Run 1 ] -> [ Creates State ]
[ Script Run 2 ] -> [ Fails / Duplicates ]
[ Script Run 2 ] -> [ Overwrites ]
```

</details>

**After** (idempotent):

```
⏭️ After: Idempotent Operations

┌──────────────┐     ┌───────────────┐
│ Script Run 1 │ ──> │ Creates State │
└──────────────┘     └───────────────┘
┌──────────────┐     ┌───────────────┐     ┌──────────────┐
│ Script Run 2 │     │  Same State   │     │ Script Run N │
│              │ ──> │ (skip/backup) │ <── │              │
└──────────────┘     └───────────────┘     └──────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Idempotent Operations"; flow: east; }
[ Script Run 1 ] -> [ Creates State ]
[ Script Run 2 ] -> [ Same State\n(skip/backup) ]
[ Script Run N ] -> [ Same State\n(skip/backup) ]
```

</details>

## Research Summary

| Agent Perspective        | Key Finding                                                                                    | Confidence |
| ------------------------ | ---------------------------------------------------------------------------------------------- | ---------- |
| Hook-Idempotency-Agent   | Both hooks (pretooluse-guard.sh, posttooluse-reminder.sh) are perfectly idempotent - no issues | High       |
| Script-Idempotency-Agent | 10 scripts have idempotency issues across mkdir, git ops, file appends, temp files             | High       |
| State-Data-Agent         | 8 non-atomic operations found: race conditions, partial writes, PID-based temp files           | High       |

## Decision Log

| Decision Area           | Options Evaluated                                             | Chosen            | Rationale                                                                  |
| ----------------------- | ------------------------------------------------------------- | ----------------- | -------------------------------------------------------------------------- |
| Re-run behavior         | Skip-if-exists, Backup+overwrite, Merge                       | Skip-if-exists    | Preserves user customizations, acceptable tradeoff for no template updates |
| .releaserc.yml handling | Skip, Backup+trace, Keep current                              | Backup+trace      | Enables recovery while allowing updates                                    |
| Backup location         | Centralized ~/.claude/backups/, Sibling, Project tmp/         | Sibling           | Easier to find per-project, no cross-project pollution                     |
| Traceability format     | Header comment, Single-line, YAML frontmatter, Match existing | Format-aware      | Composable approach: use appropriate method per file type                  |
| Log handling            | No rotation, Rotation with keep-N                             | Rotation (keep 5) | Prevents unbounded growth                                                  |

### Trade-offs Accepted

| Trade-off                            | Choice               | Accepted Cost                                                                   |
| ------------------------------------ | -------------------- | ------------------------------------------------------------------------------- |
| Template updates vs customizations   | Skip-if-exists       | Users must manually update templates after skill upgrades                       |
| Interactive prompts vs deterministic | Deterministic backup | No user confirmation before overwrite (AskUserQuestion not available from bash) |
| Atomic operations vs simplicity      | Atomic (mktemp+mv)   | Slightly more complex code                                                      |

## Decision Drivers

- Scripts must be safe to run multiple times without side effects
- User customizations must be recoverable (backup before overwrite)
- Operations must be atomic to prevent partial state on interruption
- Solution must work across macOS and Linux
- Format-aware traceability (shell comments, YAML frontmatter, JSON sibling files)

## Considered Options

- **Option A: Skip-if-exists everywhere**: Simply skip operations if artifacts exist. Safest but prevents updates.
- **Option B: Backup + overwrite everywhere**: Always backup and overwrite. Enables updates but more complex.
- **Option C: Format-aware idempotency**: Composable approach with atomic operations, format-specific traceability, and context-appropriate behavior. <- Selected

## Decision Outcome

Chosen option: **Option C (Format-aware idempotency)**, because it provides a holistic principle that:

1. Uses atomic operations (write-then-rename, mkdir-as-lock)
2. Applies format-specific traceability (shell comments, YAML frontmatter)
3. Allows context-appropriate behavior (skip for init, backup+trace for config updates)
4. Includes log rotation to prevent unbounded growth

## Synthesis

**Convergent findings**: All agents agreed that hooks are idempotent but scripts have issues. Atomic file operations and state checks are necessary.

**Divergent findings**: Agents differed on whether to use centralized vs sibling backups, and whether to prompt users.

**Resolution**: User chose sibling backups for discoverability and deterministic backup (no prompts) since AskUserQuestion is not invocable from bash scripts.

## Consequences

### Positive

- Scripts are safe to run multiple times
- User customizations are recoverable from sibling .bak files
- Atomic operations prevent corruption on interruption
- Log rotation prevents disk exhaustion
- Format-aware traceability maintains file validity

### Negative

- Template updates require manual re-initialization
- More complex code in scripts (mktemp pattern)
- Backup files accumulate (no automatic cleanup)

## Architecture

```
🏗️ Idempotency Pattern Flow

                             ╭──────────────╮
                             │ Script Start │
                             ╰──────────────╯
                               │
                               │
                               ∨
┌────────────────┐  exists   ┌──────────────┐
│ Skip or Backup │ <──────── │ State Check  │
└────────────────┘           └──────────────┘
  │                            │
  │                            │ missing
  │                            ∨
  │                          ┌──────────────┐
  │                          │ Atomic Write │
  │                          └──────────────┘
  │                            │
  │                            │
  │                            ∨
  │                          ┌──────────────┐
  │                          │ mktemp + mv  │
  │                          └──────────────┘
  │                            │
  │                            │
  │                            ∨
  │                          ╭──────────────╮
  └────────────────────────> │     Done     │
                             ╰──────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Idempotency Pattern Flow"; flow: south; }
[ Script Start ] { shape: rounded; } -> [ State Check ]
[ State Check ] -- exists --> [ Skip or Backup ]
[ State Check ] -- missing --> [ Atomic Write ]
[ Atomic Write ] -> [ mktemp + mv ]
[ Skip or Backup ] -> [ Done ] { shape: rounded; }
[ mktemp + mv ] -> [ Done ]
```

</details>

## References

- Global Plan: `snoopy-baking-lerdorf.md` (ephemeral, local to author's machine)
