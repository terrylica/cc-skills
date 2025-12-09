---
adr: 2025-12-09-clickhouse-architect-skill
source: ~/.claude/plans/adaptive-leaping-sloth.md
implementation-status: completed
phase: released
last-updated: 2025-12-09
---

# Design Spec: clickhouse-architect Skill

**ADR**: [ClickHouse Architect Skill ADR](/docs/adr/2025-12-09-clickhouse-architect-skill.md)

## Objective

Create comprehensive `clickhouse-architect` skill for ClickHouse schema design, compression codecs, performance patterns, and architecture audits.

## User Decisions

| Question          | Answer                                          |
| ----------------- | ----------------------------------------------- |
| Plugin placement  | quality-tools (validated by agent analysis)     |
| Deployment target | Both Cloud + self-hosted equally                |
| Version handling  | Modern only (24.4+), note legacy briefly        |
| Future features   | Production-only (ALP codec NOT yet implemented) |
| Audit depth       | Comprehensive & idiomatic (20+ queries)         |

## Research Summary

### Plugin Placement Decision

| Plugin            | Focus                                            | Fit            |
| ----------------- | ------------------------------------------------ | -------------- |
| **devops-tools**  | Operations (user mgmt, credentials, monitoring)  | Wrong audience |
| **quality-tools** | Design validation, performance profiling, audits | **Best fit**   |

**Justification**: `clickhouse-architect` answers "Is this design correct and performant?" — a validation question, not an operations question. Complements existing `schema-e2e-validation` and `multi-agent-performance-profiling` skills.

### Empirical Validation Status

| Pattern                    | Status             | Evidence                                 |
| -------------------------- | ------------------ | ---------------------------------------- |
| DoubleDelta for timestamps | Validated          | Official docs + 2025 testing             |
| Gorilla for floats         | Validated          | **CRITICAL**: Delta+Gorilla = corruption |
| T64 for integers           | Validated          | Best with ZSTD, not LZ4                  |
| ORDER BY 3-5 cols          | Validated          | 10x penalty measured                     |
| LowCardinality < 10k       | Validated          | 4x query improvement                     |
| JOINs anti-pattern         | **Improved 180x**  | v24.4+ predicate pushdown                |
| Mutations anti-pattern     | **Improved 1700x** | v24.4+ lightweight updates               |
| ALP codec                  | NOT in ClickHouse  | Issue #60533 open, no merge              |

## Implementation Tasks

### Part 1: Create Skill Structure

**Location**: `plugins/quality-tools/skills/clickhouse-architect/`

- [ ] **Task 1.1**: Create `SKILL.md` (~1400-1600 words, prescriptive methodology + examples)
- [ ] **Task 1.2**: Create `scripts/schema-audit.sql` (reusable audit queries)
- [ ] **Task 1.3**: Create `references/schema-design-workflow.md` (new → validate → optimize workflow)
- [ ] **Task 1.4**: Create `references/compression-codec-selection.md` (decision tree + tradeoffs)
- [ ] **Task 1.5**: Create `references/anti-patterns-and-fixes.md` (13 deadly sins + v24.4+ fixes)
- [ ] **Task 1.6**: Create `references/audit-and-diagnostics.md` (query interpretation guide)
- [ ] **Task 1.7**: Create `references/idiomatic-architecture.md` (parameterized views, dictionaries, deduplication)

### Part 2: Update Plugin README

- [ ] **Task 2.1**: Update `plugins/quality-tools/README.md` with new skill

### Part 3: Cross-References

- [ ] **Task 3.1**: Add cross-reference from `devops-tools:clickhouse-cloud-management`

## Critical Files

| Priority | Path                                                                                          | Action             |
| -------- | --------------------------------------------------------------------------------------------- | ------------------ |
| 1        | `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`                                  | CREATE             |
| 2        | `plugins/quality-tools/skills/clickhouse-architect/scripts/schema-audit.sql`                  | CREATE             |
| 3        | `plugins/quality-tools/skills/clickhouse-architect/references/schema-design-workflow.md`      | CREATE             |
| 4        | `plugins/quality-tools/skills/clickhouse-architect/references/compression-codec-selection.md` | CREATE             |
| 5        | `plugins/quality-tools/skills/clickhouse-architect/references/anti-patterns-and-fixes.md`     | CREATE             |
| 6        | `plugins/quality-tools/skills/clickhouse-architect/references/audit-and-diagnostics.md`       | CREATE             |
| 7        | `plugins/quality-tools/skills/clickhouse-architect/references/idiomatic-architecture.md`      | CREATE             |
| 8        | `plugins/quality-tools/README.md`                                                             | MODIFY             |
| 9        | `plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md`                            | MODIFY (cross-ref) |

## Scope Coverage (9 Categories)

### 1. Schema Design

- ORDER BY key (3-5 columns, lowest cardinality first)
- PRIMARY KEY (prefix of ORDER BY, sparse index implications)
- PARTITION BY (data management, NOT query optimization)
- Data types (LowCardinality, DateTime64 precision)
- Table engines (MergeTree family, SharedMergeTree for Cloud)

### 2. Compression Codecs (Empirically Validated)

| Codec       | Best For                        | Example                               | Notes                         |
| ----------- | ------------------------------- | ------------------------------------- | ----------------------------- |
| DoubleDelta | Timestamps, monotonic sequences | `DateTime64 CODEC(DoubleDelta, ZSTD)` | Always chain with ZSTD or LZ4 |
| Gorilla     | Float prices, gauges            | `price Float64 CODEC(Gorilla, ZSTD)`  | Float only, see restrictions  |
| T64         | General integers                | `count UInt64 CODEC(T64, ZSTD)`       | Works best with ZSTD, not LZ4 |
| Delta       | Slowly changing values          | `version UInt32 CODEC(Delta, ZSTD)`   | Good for small deltas         |

**CRITICAL SAFETY**: Delta/DoubleDelta + Gorilla = **DATA CORRUPTION** (PR #45652). Never combine these codecs.

### 3. Performance Acceleration

- Materialized views (pre-aggregations, real-time ETL)
- Projections (alternative sorting, automatic selection)
- Data-skipping indexes (bloom_filter, minmax, set)
- Dictionaries for dimension lookups
- Lazy materialization (Top N queries)

### 4. Anti-Patterns ("13 Deadly Sins") - Modern Assessment

**Still Critical (v24.4+)**:

- Too many parts (partition cardinality too high) — 300 part threshold
- Small batch inserts (<1000 rows) — aim for 10k-100k
- High-cardinality first ORDER BY — 10x slowdown measured
- Denormalization pitfalls — use dictionaries + materialized views instead
- No memory limits configured — 78% of deployments affected

**Significantly Improved (v24.4+)**:

- Large JOINs — **180x faster** with predicate pushdown (still avoid for ultra-low-latency)
- Mutations — **1700x faster** with lightweight updates; traditional mutations still slow

### 5. Data Lifecycle (TTL)

- Row TTL for automatic deletion
- Column TTL for selective pruning
- Movement TTL (tiered storage)
- `merge_with_ttl_timeout` tuning
- Align TTL with partition key

### 6. Distributed Architecture

- ReplicatedMergeTree patterns
- Sharding key selection (even distribution)
- 3 replicas per shard recommended
- ZooKeeper path uniqueness (critical!)
- SharedMergeTree (ClickHouse Cloud)

### 7. Audit & Validation Queries (Comprehensive - 20+)

**Schema Health**: `system.parts`, `system.columns`, `system.tables`

**Query Performance**: `system.query_log`, `system.processes`, `EXPLAIN indexes=1`

**Replication & Cluster**: `system.replicas`, `system.distribution_queue`, `clusterAllReplicas()`

**Resource Monitoring**: `system.disks`, `system.metrics`, `system.asynchronous_metrics`, `system.merges`

**ProfileEvents**: `OSIOWaitMicroseconds`, `OSCPUWaitMicroseconds`, `SelectedParts`, `SelectedRanges`, `SelectedMarks`

### 8. Query Optimization

- Avoid FINAL with projections
- Column pruning patterns
- PREWHERE optimization
- Predicate pushdown

### 9. Idiomatic Architecture Patterns

**Parameterized Views (23.1+)**: Replace static views with table functions

**Dictionaries vs JOINs** (6.6x faster): O(1) lookup for dimension tables

**ReplacingMergeTree for Deduplication**: Eventual deduplication at merge time

## Success Criteria

### Content

- [ ] Skill covers all 9 categories
- [ ] Compression codec recommendations are actionable
- [ ] Critical safety: Delta+Gorilla corruption warning prominent
- [ ] Anti-patterns checklist includes v24.4+ improvements
- [ ] Audit queries are copy-paste ready (scripts/schema-audit.sql)
- [ ] Idiomatic patterns include parameterized views, dictionaries, ReplacingMergeTree
- [ ] Both Cloud (SharedMergeTree) and self-hosted (ReplicatedMergeTree) covered

### Skill-Development Best Practices

- [ ] SKILL.md ~1400-1600 words (prescriptive methodology)
- [ ] Description uses third-person with specific trigger phrases
- [ ] Body uses imperative/infinitive form
- [ ] `allowed-tools` frontmatter field present
- [ ] References structured around workflows/decisions (not catalogs)
- [ ] scripts/ directory with reusable SQL templates
- [ ] Cross-references to related skills work
- [ ] README updated with skill count
