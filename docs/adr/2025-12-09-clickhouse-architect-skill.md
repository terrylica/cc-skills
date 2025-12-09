---
status: implemented
date: 2025-12-09
decision-maker: Terry Li
consulted:
  [
    Compression-Validation-Agent,
    Anti-Patterns-Agent,
    Schema-Design-Agent,
    Idiomatic-Patterns-Agent,
  ]
research-method: single-agent
clarification-iterations: 5
perspectives: [EcosystemArtifact, ProviderToOtherComponents]
---

# ADR: ClickHouse Architect Skill for Schema Design and Performance Optimization

**Design Spec**: [Implementation Spec](/docs/design/2025-12-09-clickhouse-architect-skill/spec.md)

## Context and Problem Statement

The cc-skills marketplace has `devops-tools:clickhouse-cloud-management` for operational tasks (user creation, permissions, credentials), but lacks guidance for ClickHouse schema design, compression codec selection, and performance optimization.

Engineers need prescriptive guidance on:

- ORDER BY key selection (cardinality ordering, column count)
- Compression codec selection (DoubleDelta, Gorilla, T64) with safety warnings
- Anti-patterns ("13 Deadly Sins") updated for v24.4+ improvements
- Comprehensive audit queries for schema health validation
- Idiomatic ClickHouse patterns (parameterized views, dictionaries, ReplacingMergeTree)

### Before/After

**Before**: Only operational tooling exists

```
                         ⏮️ Before: Operations Only

                      ┌−−−−−−−−−−−−−−−−−−−−−−−−−−┐
                      ╎ devops-tools:            ╎
                      ╎                          ╎
╭───────────────╮     ╎ ┌──────────────────────┐ ╎     ┌⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┐
│  User Need:   │     ╎ │  clickhouse-cloud-   │ ╎     ⋮        Gap:        ⋮
│ Schema Design │     ╎ │      management      │ ╎     ⋮ No Design Guidance ⋮
│               │ ──> ╎ │ (users, credentials) │ ╎ ··> ⋮                    ⋮
╰───────────────╯     ╎ └──────────────────────┘ ╎     └⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┘
                      ╎                          ╎
                      └−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Operations Only"; flow: east; }
( devops-tools:
  [clickhouse-cloud-management] { label: "clickhouse-cloud-\nmanagement\n(users, credentials)"; }
)
[User Need:\nSchema Design] { shape: rounded; } -> [clickhouse-cloud-management]
[clickhouse-cloud-management] ..> [Gap:\nNo Design Guidance] { border: dotted; }
```

</details>

**After**: Design + Operations with cross-reference

```
                               ⏭️ After: Design + Operations

                      ┌−−−−−−−−−−−−−−−−−−−−−−−−−−┐              ┌−−−−−−−−−−−−−−−−−−−−−−−−−−┐
                      ╎ quality-tools:           ╎              ╎ devops-tools:            ╎
                      ╎                          ╎              ╎                          ╎
╭───────────────╮     ╎ ┏━━━━━━━━━━━━━━━━━━━━━━┓ ╎              ╎ ┌──────────────────────┐ ╎
│  User Need:   │     ╎ ┃ clickhouse-architect ┃ ╎              ╎ │  clickhouse-cloud-   │ ╎
│ Schema Design │     ╎ ┃   (schema, codecs,   ┃ ╎  cross-ref   ╎ │      management      │ ╎
│               │ ──> ╎ ┃     performance)     ┃ ╎ ───────────> ╎ │ (users, credentials) │ ╎
╰───────────────╯     ╎ ┗━━━━━━━━━━━━━━━━━━━━━━┛ ╎              ╎ └──────────────────────┘ ╎
                      ╎                          ╎              ╎                          ╎
                      └−−−−−−−−−−−−−−−−−−−−−−−−−−┘              └−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Design + Operations"; flow: east; }
( quality-tools:
  [clickhouse-architect] { label: "clickhouse-architect\n(schema, codecs,\nperformance)"; border: bold; }
)
( devops-tools:
  [clickhouse-cloud-management] { label: "clickhouse-cloud-\nmanagement\n(users, credentials)"; }
)
[User Need:\nSchema Design] { shape: rounded; } -> [clickhouse-architect]
[clickhouse-architect] -- cross-ref --> [clickhouse-cloud-management]
```

</details>

## Research Summary

| Agent Perspective      | Key Finding                                                      | Confidence |
| ---------------------- | ---------------------------------------------------------------- | ---------- |
| Compression-Validation | DoubleDelta, Gorilla, T64 validated; Delta+Gorilla = corruption  | High       |
| Anti-Patterns          | JOINs 180x faster, mutations 1700x faster in v24.4+              | High       |
| Schema-Design          | ORDER BY 3-5 cols, lowest cardinality first; 10x penalty if not  | High       |
| Idiomatic-Patterns     | Parameterized views (23.1+), dictionaries 6.6x faster than JOINs | High       |

### Empirical Validation Status (Updated v2.22.0)

| Pattern                    | Status                 | Evidence                                                      |
| -------------------------- | ---------------------- | ------------------------------------------------------------- |
| DoubleDelta for timestamps | ✅ Validated           | Official docs + testing                                       |
| DoubleDelta + ZSTD default | 🔄 **Nuanced**         | LZ4 better for read-heavy monotonic (1.76x faster decompress) |
| Gorilla for floats         | ✅ Validated           | Official docs                                                 |
| Delta+Gorilla corruption   | 🔄 **Outdated**        | Bug fixed PR #45615 (Jan 2023); now just blocked as redundant |
| T64 for integers           | ✅ Validated           | Best with ZSTD                                                |
| ORDER BY 3-5 cols          | ✅ Validated           | 10x penalty measured                                          |
| LowCardinality < 10k       | ✅ Validated           | 4x query improvement                                          |
| Dictionary 6.6x            | 🔄 **Contextual**      | Only for 1.4B+ rows star schema; <500 rows use JOINs          |
| JOINs anti-pattern         | 🔄 **Improved 8-180x** | v24.4+ predicate pushdown (180x upper bound)                  |
| Mutations anti-pattern     | 🔄 **Improved 1700x**  | v24.4+ lightweight updates                                    |
| ALP codec                  | ❌ NOT in ClickHouse   | Issue #60533 open, no merge                                   |

## Decision Log

| Decision Area     | Options Evaluated             | Chosen              | Rationale                                                     |
| ----------------- | ----------------------------- | ------------------- | ------------------------------------------------------------- |
| Plugin placement  | devops-tools, quality-tools   | quality-tools       | Design validation focus, complements schema-e2e-validation    |
| Deployment target | Cloud-only, Self-hosted, Both | Both equally        | SharedMergeTree (Cloud) and ReplicatedMergeTree (self-hosted) |
| Version handling  | All versions, Modern only     | Modern only (24.4+) | Focus on current best practices, note legacy briefly          |
| Future features   | Include ALP, Production-only  | Production-only     | ALP codec not yet implemented (Issue #60533)                  |
| Audit depth       | Basic, Comprehensive          | Comprehensive (20+) | Full system.\* coverage for production use                    |

### Trade-offs Accepted

| Trade-off         | Choice         | Accepted Cost                            |
| ----------------- | -------------- | ---------------------------------------- |
| Version coverage  | Modern (24.4+) | Legacy users need separate research      |
| Plugin separation | quality-tools  | Requires cross-reference to devops-tools |
| Skill size        | Comprehensive  | ~1500 words SKILL.md + 5 reference files |

## Decision Drivers

- Need for prescriptive schema design guidance (not just documentation)
- Critical safety warnings (Delta+Gorilla corruption PR #45652)
- v24.4+ improvements invalidate some traditional anti-pattern advice
- Comprehensive audit queries for production validation
- Both Cloud and self-hosted deployment patterns

## Considered Options

- **Option A**: Extend `devops-tools:clickhouse-cloud-management` with design sections
- **Option B**: Create new `clickhouse-architect` skill in quality-tools <- Selected
- **Option C**: Create standalone plugin for all ClickHouse concerns

## Decision Outcome

Chosen option: **Option B**, because:

1. **Separation of concerns**: Operations (credentials, users) vs Design (schema, performance) are distinct audiences
2. **Plugin cohesion**: quality-tools focuses on "Is this design correct and performant?" — validation questions
3. **Complementary skills**: Works alongside `schema-e2e-validation` and `multi-agent-performance-profiling`
4. **Cross-reference**: Easy link from devops-tools for users who need both

## Synthesis

**Convergent findings**: All agents agreed on:

- DoubleDelta, Gorilla, T64 as validated codec choices
- ORDER BY cardinality ordering importance
- v24.4+ improvements for JOINs and mutations

**Divergent findings**: Plugin placement required additional analysis:

- Initial thought: devops-tools (ClickHouse-related)
- After analysis: quality-tools (design validation focus)

**Resolution**: User confirmed quality-tools after reviewing plugin focus areas.

## Consequences

### Positive

- Prescriptive schema design guidance for ClickHouse users
- Critical safety warnings prominently documented
- v24.4+ improvements properly contextualized
- Comprehensive audit queries for production validation
- Idiomatic patterns promote ClickHouse-native approaches

### Negative

- Requires maintaining cross-reference to devops-tools
- Modern-only focus may frustrate legacy users
- Comprehensive scope means longer skill content

## Post-Release Validation (v2.22.0)

### Empirical Research Validation

Following v2.21.0 release, independent research validation identified three claims requiring correction:

#### 1. Codec Chaining: DoubleDelta + ZSTD vs LZ4

| Original Claim  | Research Finding  | Correction            |
| --------------- | ----------------- | --------------------- |
| Always use ZSTD | Context-dependent | Added LZ4 alternative |

**Verified facts**:

- DoubleDelta + LZ4: 1.76x faster decompression, best for monotonic sequences
- DoubleDelta + ZSTD: Better compression ratio, best for slowly changing time series
- ZSTD is safer default when data patterns unknown

**Sources**: ClickHouse Official Blog, Altinity KB, GitHub Issue #38134

#### 2. Delta+Gorilla Warning

| Original Claim    | Research Finding   | Correction         |
| ----------------- | ------------------ | ------------------ |
| "DATA CORRUPTION" | Bug fixed Jan 2023 | Downgraded to note |

**Verified facts**:

- PR #45615 (Jan 26, 2023): Fixed the actual corruption bug
- PR #45652 (Jan 31, 2023): Added `allow_suspicious_codecs` guardrail
- Post-fix: Combination is **redundant** (Gorilla does implicit delta), not dangerous
- Still blocked by default as best practice

**Sources**: GitHub PRs #45615, #45652; ClickHouse docs

#### 3. Dictionary 6.6x Performance

| Original Claim            | Research Finding  | Correction              |
| ------------------------- | ----------------- | ----------------------- |
| "6.6x faster" unqualified | Context-dependent | Added benchmark context |

**Verified facts**:

- 6.6x benchmark: Star Schema, 1.4B rows fact table, ClickHouse Cloud
- v24.4+ JOINs: 8-180x improvement (predicate pushdown)
- Dictionaries overkill for <500 row dimension tables
- Decision framework added for when to use each approach

**Sources**: ClickHouse Blog "Using Dictionaries to Accelerate Queries", Tinybird v24.4 improvements

### Research Methodology

- 3 parallel research agents with web search + GitHub verification
- Cross-referenced ClickHouse official docs, Altinity KB, GitHub PRs/Issues
- Iterative clarification with user on warning tone preference

## Architecture

```
                               🏗️ clickhouse-architect Skill Structure

                                                     ┌−−−−−−−−−−−−−−−−−−−−┐
                                                     ╎                    ╎
  ┌────────────────────┐         ┏━━━━━━━━━━━━━━━━━━┓╎ ┌────────────────┐ ╎
  │      scripts/      │         ┃     SKILL.md     ┃╎ │ schema-design- │ ╎
  │  schema-audit.sql  │         ┃  (~1500 words)   ┃╎ │  workflow.md   │ ╎
  │                    │   <──   ┃ Core methodology ┃╎ │                │ ╎
  └────────────────────┘         ┗━━━━━━━━━━━━━━━━━━┛╎ └────────────────┘ ╎
                                                     ╎                    ╎
                                                     └−−−−−−−−−−−−−−−−−−−−┘
                                   │                     ∧
                                   │                     │
                                   │                     │
┌−−−−−−−−−−−−−−−−−−−−−−−−┐         │                                            ┌−−−−−−−−−−−−−−−−−−−−−┐
╎ references/:           ╎         │                                            ╎                     ╎
╎                        ╎         ∨                                            ╎                     ╎
╎ ┌────────────────────┐ ╎       ┌──────────────────────────────────────┐       ╎ ┌─────────────────┐ ╎
╎ │ compression-codec- │ ╎       │             references/              │       ╎ │   idiomatic-    │ ╎
╎ │    selection.md    │ ╎ <──   │          5 detailed guides           │   ──> ╎ │ architecture.md │ ╎
╎ └────────────────────┘ ╎       └──────────────────────────────────────┘       ╎ └─────────────────┘ ╎
╎                        ╎                                                      ╎                     ╎
└−−−−−−−−−−−−−−−−−−−−−−−−┘                                                      └−−−−−−−−−−−−−−−−−−−−−┘
                                   │                     │
                                   │                     │
                                   ∨                     ∨
                               ┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
                               ╎                                          ╎
                               ╎ ┌──────────────────┐  ┌────────────────┐ ╎
                               ╎ │  anti-patterns-  │  │   audit-and-   │ ╎
                               ╎ │   and-fixes.md   │  │ diagnostics.md │ ╎
                               ╎ └──────────────────┘  └────────────────┘ ╎
                               ╎                                          ╎
                               └−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ clickhouse-architect Skill Structure"; flow: south; }
[SKILL.md] { label: "SKILL.md\n(~1500 words)\nCore methodology"; border: bold; }
[scripts/] { label: "scripts/\nschema-audit.sql"; }
[references/] { label: "references/\n5 detailed guides"; }
[SKILL.md] -> [scripts/]
[SKILL.md] -> [references/]
( references/:
  [workflow] { label: "schema-design-\nworkflow.md"; }
  [codecs] { label: "compression-codec-\nselection.md"; }
  [antipatterns] { label: "anti-patterns-\nand-fixes.md"; }
  [audit] { label: "audit-and-\ndiagnostics.md"; }
  [idiomatic] { label: "idiomatic-\narchitecture.md"; }
)
[references/] -> [workflow]
[references/] -> [codecs]
[references/] -> [antipatterns]
[references/] -> [audit]
[references/] -> [idiomatic]
```

</details>

## References

### Compression Codecs

- [Optimizing ClickHouse with Schemas and Codecs](https://clickhouse.com/blog/optimize-clickhouse-codecs-compression-schema)
- [Codecs | Altinity Knowledge Base](https://kb.altinity.com/altinity-kb-schema-design/codecs/)

### Schema Design

- [How to pick ORDER BY / PRIMARY KEY / PARTITION BY](https://kb.altinity.com/engines/mergetree-table-engine-family/pick-keys/)
- [Choosing a Partitioning Key | ClickHouse Docs](https://clickhouse.com/docs/best-practices/choosing-a-partitioning-key)

### Anti-Patterns

- [13 "Deadly Sins" | ClickHouse Blog](https://clickhouse.com/blog/common-getting-started-issues-with-clickhouse)
- [Why Denormalization Slows You Down](https://www.glassflow.dev/blog/denormalization-clickhouse)

### Idiomatic Patterns

- [Parameterized Views | Altinity KB](https://kb.altinity.com/altinity-kb-queries-and-syntax/altinity-kb-parameterized-views/)
- [Using Dictionaries to Accelerate Queries | ClickHouse Blog](https://clickhouse.com/blog/faster-queries-dictionaries-clickhouse)
- [ReplacingMergeTree Explained | Altinity Blog](https://altinity.com/blog/clickhouse-replacingmergetree-explained-the-good-the-bad-and-the-ugly)
