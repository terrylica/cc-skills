---
status: accepted
date: 2025-12-08
decision-maker: Terry Li
consulted:
  [
    Explore-Agent-1,
    Explore-Agent-2,
    Explore-Agent-3,
    Validation-Agent-1,
    Validation-Agent-2,
  ]
research-method: multi-agent
clarification-iterations: 3
perspectives: [Gap Analysis, Empirical Validation, Integration Design]
---

# Create mise-tasks Skill with Bidirectional Cross-References

**Design Spec**: [Implementation Spec](/docs/design/2025-12-08-mise-tasks-skill/spec.md)

## Context and Problem Statement

The `mise-configuration` skill documents mise `[env]`, `[settings]`, and `[tools]` sections comprehensively, but has **zero coverage** of mise `[tasks]` functionality. Real-world usage (spicy-conjuring-planet.md plan) demonstrates advanced task patterns (`depends`, `depends_post`, `hide`, `usage` args) that are undocumented. AI coding agents cannot discover or leverage mise task orchestration capabilities.

### Before: Zero [tasks] Coverage

```
🔄 Before: Zero [tasks] Coverage

                         ┌────────────────────┐
                         │    env section     │
                         └────────────────────┘
                           │
                           │
                           ∨
┌──────────────────┐     ╭────────────────────╮
│ settings section │ ──> │ mise-configuration │
└──────────────────┘     ╰────────────────────╯
                           ∧
                           │
                           │
                         ┌────────────────────┐
                         │   tools section    │
                         └────────────────────┘
                         ┌────────────────────┐
                         │     [x] tasks      │
                         │   (undocumented)   │
                         └────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🔄 Before: Zero [tasks] Coverage"; flow: south; }
[ mise-configuration ] { shape: rounded; }
[ env section ] -> [ mise-configuration ]
[ settings section ] -> [ mise-configuration ]
[ tools section ] -> [ mise-configuration ]
[ tasks section ] { label: "[x] tasks\n(undocumented)"; }
```

</details>

### After: Bidirectional Cross-Reference

```
              🔄 After: Bidirectional Cross-Reference

                      ┌────────────────────┐
                      │    env section     │
                      └────────────────────┘
                        │
                        │
                        ∨
┌───────────────┐     ╭────────────────────╮     ┌──────────────────┐
│ tools section │ ──> │ mise-configuration │ <── │ settings section │
└───────────────┘     ╰────────────────────╯     └──────────────────┘
                        ∧
                        │
                        │
                        ∨
                      ╭────────────────────╮
                      │     mise-tasks     │
                      ╰────────────────────╯
                        ∧
                        │
                        │
                      ┌────────────────────┐
                      │   tasks section    │
                      └────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🔄 After: Bidirectional Cross-Reference"; flow: south; }
[ mise-configuration ] { shape: rounded; }
[ mise-tasks ] { shape: rounded; }
[ env section ] -> [ mise-configuration ]
[ settings section ] -> [ mise-configuration ]
[ tools section ] -> [ mise-configuration ]
[ mise-configuration ] <-> [ mise-tasks ]
[ tasks section ] -> [ mise-tasks ]
```

</details>

## Research Summary

Multi-agent research analyzed the gap between existing mise-configuration skill and real-world mise usage patterns. Five agents (3 exploration, 2 validation) confirmed:

1. **Gap Analysis**: mise-configuration has ZERO [tasks] coverage despite 4 existing .mise.toml files in codebase
2. **Empirical Validation**: All 18 task properties work in mise 2025.12.0
3. **Integration Analysis**: mise tasks complement but cannot replace /itp:go workflow

## Decision Drivers

- Gap analysis confirms zero `[tasks]` coverage in existing mise-configuration skill
- Empirical validation confirms all planned features work in mise 2025.12.0
- User decision: Create separate skill with bidirectional cross-references
- User decision: Comprehensive coverage (10 complexity levels)
- User decision: Prescriptive AI reminders for skill discovery

## Considered Options

1. **Enhance mise-configuration skill** - Add `[tasks]` to existing skill
2. **Create separate mise-tasks skill** - New skill focused on task orchestration
3. **Both with cross-references** - New skill + bidirectional links + AI prescriptive reminders

## Decision Outcome

**Chosen option**: "Both with cross-references" — Create new `mise-tasks` skill AND enhance `mise-configuration` with prescriptive cross-references, enabling AI coding agents to discover task orchestration opportunities.

### Consequences

**Good**:

- Clear separation of concerns (env/settings/tools vs tasks)
- Bidirectional discovery (each skill points to the other)
- AI agents receive prescriptive reminders to invoke related skills
- Comprehensive 10-level documentation covers all mise task features

**Bad**:

- Two skills to maintain instead of one
- Users must know both skills exist

**Neutral**:

- ITP plugin skill count increases from 9 to 10

## Decision Log

| Date       | Decision                                         | Rationale                                  |
| ---------- | ------------------------------------------------ | ------------------------------------------ |
| 2025-12-08 | Create separate mise-tasks skill                 | User preference for separation of concerns |
| 2025-12-08 | Comprehensive 10-level documentation             | User wants reference-grade coverage        |
| 2025-12-08 | Bidirectional cross-references with AI reminders | Enable skill discovery during workflows    |
| 2025-12-08 | Defer [tasks] from mise-configuration (v2.18.0)  | Original decision to create separate skill |

## Synthesis

The decision to create a separate `mise-tasks` skill with bidirectional cross-references balances three concerns:

1. **Separation of Concerns**: Environment configuration (`[env]`, `[settings]`, `[tools]`) is conceptually distinct from task orchestration (`[tasks]`). Separate skills allow focused documentation.

2. **AI Discoverability**: Prescriptive reminders ensure AI agents discover related skills. When `mise-configuration` detects workflow patterns, it prompts invocation of `mise-tasks`. When `mise-tasks` completes, it prompts return to `mise-configuration` for environment verification.

3. **Comprehensive Coverage**: 10 complexity levels enable progressive disclosure - from basic task definition to advanced monorepo patterns - without overwhelming the mise-configuration skill.

## Validation

### Empirical Validation (mise 2025.12.0)

| Feature Category  | Features                                                                  | Status    |
| ----------------- | ------------------------------------------------------------------------- | --------- |
| **Core**          | `run`, `description`, `alias`, `depends`, `depends_post`, `hide`, `usage` | ALL WORK  |
| **File Tracking** | `sources`, `outputs`                                                      | VALIDATED |
| **Execution**     | `confirm`, `quiet`, `silent`, `raw`                                       | VALIDATED |
| **Advanced**      | `tools`, `mise watch`, `--jobs`                                           | VALIDATED |

18 task properties confirmed from official mise documentation.

## Architecture

```
                                                              🏗️ AI Discovery Architecture

                                        invoke
                   ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
                   ∨                                                                                                            │
╭──────────╮     ┏━━━━━━━━━━━━━━━━━━━━┓  detects workflow   ┌───────────────────────┐  invoke   ┏━━━━━━━━━━━━┓  after tasks   ┌─────────────────────────┐
│ AI Agent │ ──> ┃ mise-configuration ┃ ──────────────────> │ Prescriptive Reminder │ ────────> ┃ mise-tasks ┃ ─────────────> │ Prescriptive Reminder 2 │
╰──────────╯     ┗━━━━━━━━━━━━━━━━━━━━┛                     └───────────────────────┘           ┗━━━━━━━━━━━━┛                └─────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ AI Discovery Architecture"; flow: east; }
[ AI Agent ] { shape: rounded; }
[ mise-configuration ] { border: bold; }
[ mise-tasks ] { border: bold; }
[ AI Agent ] -> [ mise-configuration ]
[ mise-configuration ] -- detects workflow --> [ Prescriptive Reminder ]
[ Prescriptive Reminder ] -- invoke --> [ mise-tasks ]
[ mise-tasks ] -- after tasks --> [ Prescriptive Reminder 2 ]
[ Prescriptive Reminder 2 ] -- invoke --> [ mise-configuration ]
```

</details>

## More Information

### Source Analysis

| Source                        | Key Findings                                                                            |
| ----------------------------- | --------------------------------------------------------------------------------------- |
| **spicy-conjuring-planet.md** | Advanced patterns: `depends`, `depends_post`, `hide`, `usage` args, hidden helper tasks |
| **mise-configuration skill**  | Zero `[tasks]` coverage - confirmed gap                                                 |
| **Official mise docs**        | 10 complexity levels; `hide=true` is official (not `_` prefix)                          |
| **ITP integration**           | mise tasks complement but cannot replace /itp:go                                        |

### Anti-Patterns to Document

- Do NOT use mise tasks to replace /itp:go workflow
- Do NOT use mise for TodoWrite state tracking
- mise tasks are for repeatable project workflows, not ADR-driven orchestration

### Cross-Reference Pattern

**In mise-tasks skill**:

> After defining tasks, invoke `mise-configuration` skill to ensure [env] SSoT patterns are applied.

**In mise-configuration skill**:

> When detecting workflow opportunities, prescriptively invoke `mise-tasks` skill for task orchestration.
