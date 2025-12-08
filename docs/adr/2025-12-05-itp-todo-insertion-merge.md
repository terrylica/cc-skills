---
status: accepted
date: 2025-12-05
decision-maker: Terry Li
consulted: [Claude-Code-Agent]
research-method: single-agent
clarification-iterations: 3
perspectives: [WorkflowDesign, UserExperience, DataIntegrity]
---

# ADR: ITP Workflow Todo Insertion (Not Overwrite)

**Design Spec**: [Implementation Spec](/docs/design/2025-12-05-itp-todo-insertion-merge/spec.md)

## Context and Problem Statement

The ITP workflow command (`/itp:go`) currently instructs Claude to "Copy this TodoWrite template EXACTLY" as a mandatory first action. This **overwrites** any existing todos from:

- Plan files in `~/.claude/plans/*.md`
- Previous work sessions
- User's manually created todos

Users expect the ITP workflow to integrate with their existing work, not destroy it. When a plan file exists with carefully crafted tasks, the ITP workflow should merge those tasks into the appropriate phases rather than replacing them entirely.

### Before/After

**Before: TodoWrite Overwrites**

```
Before: TodoWrite Overwrites

╭──────────────────────────╮
│        Plan File         │
╰──────────────────────────╯
  │
  │
  ∨
┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       itp Command        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
  │
  │
  ∨
╔══════════════════════════╗
║  TodoWrite COPY EXACTLY  ║
╚══════════════════════════╝
  │
  │ overwrites
  ∨
┌⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┐
⋮ Existing Todos DESTROYED ⋮
└⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Before: TodoWrite Overwrites"; flow: south; }
[ Plan File ] { shape: rounded; }
[ /itp:go Command ] { border: bold; }
[ TodoWrite COPY EXACTLY ] { border: double; }
[ Existing Todos DESTROYED ] { border: dotted; }
[ Plan File ] -> [ /itp:go Command ]
[ /itp:go Command ] -> [ TodoWrite COPY EXACTLY ]
[ TodoWrite COPY EXACTLY ] -- overwrites --> [ Existing Todos DESTROYED ]
```

</details>

**After: TodoWrite Merges**

```
After: TodoWrite Merges

╭──────────────────────────╮
│        Plan File         │ <┐
╰──────────────────────────╯  │
  │                           │
  │                           │
  ∨                           │
┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │
┃       itp Command        ┃  │ reads
┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │
  │                           │
  │                           │
  ∨                           │
╔══════════════════════════╗  │
║ Step 0 Plan Integration  ║ ─┘
╚══════════════════════════╝
  │
  │ interleaves
  ∨
┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃     Merged TodoWrite     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
  │
  │
  ∨
╭──────────────────────────╮
│ Existing Todos PRESERVED │
╰──────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "After: TodoWrite Merges"; flow: south; }
[ Plan File ] { shape: rounded; }
[ /itp:go Command ] { border: bold; }
[ Step 0 Plan Integration ] { border: double; }
[ Merged TodoWrite ] { border: bold; }
[ Existing Todos PRESERVED ] { shape: rounded; }
[ Plan File ] -> [ /itp:go Command ]
[ /itp:go Command ] -> [ Step 0 Plan Integration ]
[ Step 0 Plan Integration ] -- reads --> [ Plan File ]
[ Step 0 Plan Integration ] -- interleaves --> [ Merged TodoWrite ]
[ Merged TodoWrite ] -> [ Existing Todos PRESERVED ]
```

</details>

## Research Summary

| Agent Perspective | Key Finding                                                            | Confidence |
| ----------------- | ---------------------------------------------------------------------- | ---------- |
| WorkflowDesign    | Current "EXACTLY" instruction forces destructive overwrite             | High       |
| UserExperience    | Plan file tasks should map intelligently into ITP phases               | High       |
| DataIntegrity     | Existing todos represent valuable context that should not be discarded | High       |

## Decision Log

| Decision Area     | Options Evaluated                          | Chosen       | Rationale                                    |
| ----------------- | ------------------------------------------ | ------------ | -------------------------------------------- |
| Merge Position    | Prepend, Append, Interleave                | Interleave   | Tasks map naturally to ITP phases            |
| Conflict Handling | Auto-resolve, Always Ask, Skip             | Always Ask   | User retains control over priority conflicts |
| Plan Awareness    | Check on demand, Always check, Never check | Always check | Plan files contain valuable session context  |

### Trade-offs Accepted

| Trade-off             | Choice  | Accepted Cost                                      |
| --------------------- | ------- | -------------------------------------------------- |
| Simplicity vs Control | Control | More complex TodoWrite logic, but preserves intent |
| Speed vs Safety       | Safety  | Extra AskUserQuestion round for conflicts          |

## Decision Drivers

- Users create plan files (`~/.claude/plans/*.md`) to preserve session state
- ITP workflow should enhance existing work, not replace it
- Clear prefix convention (`[Plan]` vs `[ITP]`) enables visual distinction
- AskUserQuestion provides escape hatch for ambiguous mappings

## Considered Options

- **Option A: Prepend plan todos before ITP todos**
  - Simple but ignores natural phase mapping
  - Plan implementation tasks would run before Preflight

- **Option B: Append plan todos after ITP todos**
  - Simple but delays user's intended work
  - Plan tasks become afterthoughts

- **Option C: Interleave plan todos into ITP phases** <- Selected
  - Maps research tasks to Preflight
  - Maps implementation tasks to Phase 1
  - Maps documentation tasks to Phase 2
  - Requires intelligent mapping but preserves intent

## Decision Outcome

Chosen option: **Option C (Interleave)**, because plan file tasks have natural mappings to ITP workflow phases. Research and exploration tasks belong in Preflight, implementation in Phase 1, documentation in Phase 2, and release in Phase 3. This preserves user intent while providing the structure of ITP workflow.

## Synthesis

**Convergent findings**: All perspectives agreed that overwriting existing todos destroys valuable context.

**Divergent findings**: Perspectives differed on automatic vs manual conflict resolution.

**Resolution**: User chose "Always Ask" via AskUserQuestion when plan tasks don't clearly map to an ITP phase.

## Consequences

### Positive

- Plan file tasks preserved across sessions
- Clear visual distinction with `[Plan]` and `[ITP]` prefixes
- User maintains control over priority conflicts
- Intelligent mapping reduces manual reorganization

### Negative

- More complex TodoWrite instruction in `/itp:go` command
- Potential AskUserQuestion overhead for ambiguous mappings
- Requires Claude to understand task categorization

## Architecture

```
                                              🏗️ ITP Todo Merge Architecture

                                                        ┌──────────────┐
                                                        │   Phase 3    │ ───────────────────────────────────────┐
                                                        └──────────────┘                                        │
                                                          ∧                                                     │
                                                          │ release                                             │
                                                          │                                                     ∨
╭────────────────╮     ╔══════════════════╗             ┏━━━━━━━━━━━━━━┓              ┌⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┐     ┏━━━━━━━━━━━┓
│ Existing Todos │     ║     Step 0:      ║             ┃              ┃  unclear     ⋮ AskUserQuestion ⋮     ┃           ▐
│                │ ──> ║ Plan Integration ║ ──────────> ┃              ┃ ───────────> ⋮  (if conflict)  ⋮ ──> ┃           ▐
╰────────────────╯     ╚══════════════════╝             ┃              ┃              └⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┘     ┃           ▐
                         ∧                              ┃ Phase Mapper ┃                                      ┃  Merged   ▐
                         │                              ┃              ┃                                      ┃ TodoWrite ▐
                         │                              ┃              ┃                                      ┃           ▐
                       ╭──────────────────╮             ┃              ┃  implement   ┌─────────────────┐     ┃           ▐
                       │    Plan File     │  ┌───────── ┃              ┃ ───────────> │     Phase 1     │ ──> ┃           ▐
                       ╰──────────────────╯  │          ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟              └─────────────────┘     ▙▄▄▄▄▄▄▄▄▄▄▄▟
                                             │            │                                                     ∧      ∧
                                             │            │ docs                                                │      │
                                             │            ∨                                                     │      │
                                             │ research ┌──────────────┐                                        │      │
                                             │          │   Phase 2    │ ───────────────────────────────────────┘      │
                                             │          └──────────────┘                                               │
                                             │          ┌──────────────┐                                               │
                                             └────────> │  Preflight   │ ──────────────────────────────────────────────┘
                                                        └──────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ ITP Todo Merge Architecture"; flow: east; }
[ Plan File ] { shape: rounded; }
[ Existing Todos ] { shape: rounded; }
[ Step 0:\nPlan Integration ] { border: double; }
[ Phase Mapper ] { border: bold; }
[ AskUserQuestion\n(if conflict) ] { border: dotted; }
[ Merged\nTodoWrite ] { border: bold; }
[ Plan File ] -> [ Step 0:\nPlan Integration ]
[ Existing Todos ] -> [ Step 0:\nPlan Integration ]
[ Step 0:\nPlan Integration ] -> [ Phase Mapper ]
[ Phase Mapper ] -- research --> [ Preflight ]
[ Phase Mapper ] -- implement --> [ Phase 1 ]
[ Phase Mapper ] -- docs --> [ Phase 2 ]
[ Phase Mapper ] -- release --> [ Phase 3 ]
[ Phase Mapper ] -- unclear --> [ AskUserQuestion\n(if conflict) ]
[ AskUserQuestion\n(if conflict) ] -> [ Merged\nTodoWrite ]
[ Preflight ] -> [ Merged\nTodoWrite ]
[ Phase 1 ] -> [ Merged\nTodoWrite ]
[ Phase 2 ] -> [ Merged\nTodoWrite ]
[ Phase 3 ] -> [ Merged\nTodoWrite ]
```

</details>

## References

- [ITP Setup TodoWrite Workflow ADR](/docs/adr/2025-12-05-itp-setup-todowrite-workflow.md)
- Global plan file: `~/.claude/plans/memoized-cooking-nygaard.md`
