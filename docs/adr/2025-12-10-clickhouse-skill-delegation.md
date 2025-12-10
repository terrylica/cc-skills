---
status: accepted
date: 2025-12-10
decision-maker: Terry Li
consulted:
  [
    Explore-SkillContent,
    Explore-PluginArchitecture,
    Explore-CrossReferences,
    Plan-DelegationDesign,
  ]
research-method: 9-agent-parallel-dctl
clarification-iterations: 2
perspectives: [Usability, Maintainability, Architecture]
---

# ADR: ClickHouse Skill Delegation Enhancement

**Design Spec**: [Implementation Spec](/docs/design/2025-12-10-clickhouse-skill-delegation/spec.md)

## Context and Problem Statement

When users invoke `clickhouse-architect` (the hub skill), Claude doesn't automatically delegate to related skills when the user's needs extend beyond schema design. Users miss the workflow chain: `architect` -> `cloud-management` -> `pydantic-config` -> `schema-e2e-validation`.

The current 4 ClickHouse skills are well-designed and orthogonal (per ADR 2025-12-10-clickhouse-skill-documentation-gaps), but lack prescriptive delegation guidance. Users must know all skill names and when to invoke each.

### Before/After

**Before**: User must know all 4 skill names and invoke each separately (dotted lines = user guesses).

```
                             ⏮️ Before: Skills Without Delegation

                                    ┌───────────────────────┐
                                    │ schema-e2e-validation │
                                    └───────────────────────┘
                                      ∧
                                      :
                                      :
┌─────────────────────────────┐     ╭───────────────────────╮     ┌────────────────────────────┐
│ clickhouse-cloud-management │ <·· │         User          │ ··> │ clickhouse-pydantic-config │
└─────────────────────────────┘     ╰───────────────────────╯     └────────────────────────────┘
                                      │
                                      │
                                      ∨
                                    ┏━━━━━━━━━━━━━━━━━━━━━━━┓
                                    ┃ clickhouse-architect  ┃
                                    ┗━━━━━━━━━━━━━━━━━━━━━━━┛
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Skills Without Delegation"; flow: south; }
[ User ] { shape: rounded; }
[ clickhouse-architect ] { border: bold; }
[ clickhouse-cloud-management ]
[ clickhouse-pydantic-config ]
[ schema-e2e-validation ]

[ User ] -> [ clickhouse-architect ]
[ User ] ..> [ clickhouse-cloud-management ]
[ User ] ..> [ clickhouse-pydantic-config ]
[ User ] ..> [ schema-e2e-validation ]
```

</details>

**After**: User invokes architect (hub), which delegates to related skills automatically.

```
                                         ⏭️ After: Hub-Based Delegation

                                            ╭─────────────────────────────╮
                                            │            User             │
                                            ╰─────────────────────────────╯
                                              │
                                              │
                                              ∨
┌────────────────────────────┐              ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓              ┌───────────────────────┐
│ clickhouse-pydantic-config │  delegates   ┃    clickhouse-architect     ┃  delegates   │ schema-e2e-validation │
│                            │ <─────────── ┃            (HUB)            ┃ ───────────> │                       │
└────────────────────────────┘              ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛              └───────────────────────┘
                                              │
                                              │ delegates
                                              ∨
                                            ┌─────────────────────────────┐
                                            │ clickhouse-cloud-management │
                                            └─────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Hub-Based Delegation"; flow: south; }
[ User ] { shape: rounded; }
[ clickhouse-architect\n(HUB) ] { border: bold; }
[ clickhouse-cloud-management ]
[ clickhouse-pydantic-config ]
[ schema-e2e-validation ]

[ User ] -> [ clickhouse-architect\n(HUB) ]
[ clickhouse-architect\n(HUB) ] -- delegates --> [ clickhouse-cloud-management ]
[ clickhouse-architect\n(HUB) ] -- delegates --> [ clickhouse-pydantic-config ]
[ clickhouse-architect\n(HUB) ] -- delegates --> [ schema-e2e-validation ]
```

</details>

## Research Summary

| Agent Perspective          | Key Finding                                                                                                                        | Confidence |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Explore-SkillContent       | 4 skills totaling 888 lines SKILL.md + 2,602 lines resources; Python Driver Policy already centralized                             | High       |
| Explore-PluginArchitecture | Skills auto-discover from directories; trigger descriptions drive invocation; existing prescriptive patterns in mise-configuration | High       |
| Explore-CrossReferences    | clickhouse-architect is HUB; cloud-management and pydantic-config are SPOKES; schema-e2e-validation is INDEPENDENT                 | High       |
| Plan-DelegationDesign      | Keep current names; add Delegation Guide to hub skill; add prescriptive triggers to spoke skills                                   | High       |

## Decision Log

| Decision Area       | Options Evaluated                                            | Chosen               | Rationale                                |
| ------------------- | ------------------------------------------------------------ | -------------------- | ---------------------------------------- |
| Naming              | Keep names, Rename all, Hybrid rename                        | Keep names           | No breaking changes; focus on delegation |
| Merge strategy      | Merge all 4, Merge cloud+pydantic, Keep separate             | Keep separate        | ADR confirmed skills are orthogonal      |
| Delegation approach | Cross-refs only, Prescriptive triggers, Hub delegation guide | Hub delegation guide | Single point of coordination             |

### Trade-offs Accepted

| Trade-off                  | Choice                     | Accepted Cost                                           |
| -------------------------- | -------------------------- | ------------------------------------------------------- |
| Centralized vs Distributed | Centralized in architect   | Must update architect when adding new ClickHouse skills |
| Explicit vs Implicit       | Explicit delegation matrix | More verbose documentation                              |

## Decision Drivers

- Users invoke architect but miss related skills
- Skills are orthogonal and shouldn't be merged
- Need single coordination point for ClickHouse workflows
- Prescriptive pattern already proven in mise-configuration skill

## Considered Options

- **Option A**: Merge all 4 skills into one mega-skill
- **Option B**: Rename skills for better discoverability
- **Option C**: Add Delegation Guide to hub skill with prescriptive triggers <- Selected

## Decision Outcome

Chosen option: **Option C**, because it:

1. Preserves orthogonal skill design (no merge)
2. No breaking changes (no rename)
3. Centralizes workflow coordination in architect (hub)
4. Uses proven prescriptive pattern from mise-configuration skill

## Synthesis

**Convergent findings**: All agents agreed skills are well-designed and orthogonal; merging would create a 3,490-line mega-skill

**Divergent findings**: Plan agent suggested renaming as alternative; Explore agents found current names are acceptable

**Resolution**: User chose "Keep current names + add delegation" after reviewing trade-offs

## Consequences

### Positive

- Single coordination point for ClickHouse workflows
- Users invoking architect will be guided to related skills
- No breaking changes for existing users
- Follows established prescriptive pattern

### Negative

- architect skill becomes slightly larger (~40 lines added)
- Must manually update architect when adding new ClickHouse skills

## Architecture

```
🏗️ ClickHouse Skill Architecture

┌───────────────────────┐                    ╔═════════════════════════════╗
│ schema-e2e-validation │  YAML validation   ║    clickhouse-architect     ║
│     (INDEPENDENT)     │ <───────────────── ║            (HUB)            ║ ─┐
└───────────────────────┘                    ╚═════════════════════════════╝  │
                                               │                              │
                                               │ user mgmt                    │
                                               ∨                              │
                                             ┌─────────────────────────────┐  │
                                             │ clickhouse-cloud-management │  │
                                             │           (SPOKE)           │  │ DBeaver config
                                             └─────────────────────────────┘  │
                                               │                              │
                                               │ credentials                  │
                                               ∨                              │
                                             ┌─────────────────────────────┐  │
                                             │ clickhouse-pydantic-config  │  │
                                             │           (SPOKE)           │ <┘
                                             └─────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ ClickHouse Skill Architecture"; flow: south; }
[ clickhouse-architect\n(HUB) ] { border: double; }
[ clickhouse-cloud-management\n(SPOKE) ]
[ clickhouse-pydantic-config\n(SPOKE) ]
[ schema-e2e-validation\n(INDEPENDENT) ]

[ clickhouse-architect\n(HUB) ] -- user mgmt --> [ clickhouse-cloud-management\n(SPOKE) ]
[ clickhouse-architect\n(HUB) ] -- DBeaver config --> [ clickhouse-pydantic-config\n(SPOKE) ]
[ clickhouse-architect\n(HUB) ] -- YAML validation --> [ schema-e2e-validation\n(INDEPENDENT) ]
[ clickhouse-cloud-management\n(SPOKE) ] -- credentials --> [ clickhouse-pydantic-config\n(SPOKE) ]
```

</details>

## References

- [ADR: ClickHouse Skill Documentation Gaps](/docs/adr/2025-12-10-clickhouse-skill-documentation-gaps.md)
- [mise-configuration skill](../plugins/itp/skills/mise-configuration/SKILL.md) - Prescriptive delegation pattern reference
