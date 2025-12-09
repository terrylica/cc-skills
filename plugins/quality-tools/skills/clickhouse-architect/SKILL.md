---
name: clickhouse-architect
description: >
  This skill should be used when the user asks to "design ClickHouse schema",
  "select compression codecs", "audit table structure", "optimize query performance",
  "migrate to ClickHouse", "tune ORDER BY", "fix partition key", "review schema",
  or mentions "ClickHouse performance", "compression benchmark", "schema validation",
  "MergeTree optimization", "SharedMergeTree", "ReplicatedMergeTree".
allowed-tools: Read, Bash, Grep, Skill
---

# ClickHouse Architect

<!-- ADR: 2025-12-09-clickhouse-architect-skill -->

Prescriptive schema design, compression selection, and performance optimization for ClickHouse (v24.4+). Covers both ClickHouse Cloud (SharedMergeTree) and self-hosted (ReplicatedMergeTree) deployments.

## Core Methodology

### Schema Design Workflow

Follow this sequence when designing or reviewing ClickHouse schemas:

1. **Define ORDER BY key** (3-5 columns, lowest cardinality first)
2. **Select compression codecs** per column type
3. **Configure PARTITION BY** for data lifecycle management
4. **Add performance accelerators** (projections, indexes)
5. **Validate with audit queries** (see scripts/)

### ORDER BY Key Selection

The ORDER BY clause is the most critical decision in ClickHouse schema design.

**Rules**:

- Limit to 3-5 columns maximum (each additional column has diminishing returns)
- Place lowest cardinality columns first (e.g., `tenant_id` before `timestamp`)
- Include all columns used in WHERE clauses for range queries
- PRIMARY KEY must be a prefix of ORDER BY (or omit to use full ORDER BY)

**Example**:

```sql
-- Correct: Low cardinality first, 4 columns
CREATE TABLE trades (
    exchange LowCardinality(String),
    symbol LowCardinality(String),
    timestamp DateTime64(3),
    trade_id UInt64,
    price Float64,
    quantity Float64
) ENGINE = MergeTree()
ORDER BY (exchange, symbol, timestamp, trade_id);

-- Wrong: High cardinality first (10x slower queries)
ORDER BY (trade_id, timestamp, symbol, exchange);
```

### Compression Codec Quick Reference

| Column Type              | Recommended Codec          | Example                                            |
| ------------------------ | -------------------------- | -------------------------------------------------- |
| DateTime/DateTime64      | `CODEC(DoubleDelta, ZSTD)` | `timestamp DateTime64(3) CODEC(DoubleDelta, ZSTD)` |
| Float prices/gauges      | `CODEC(Gorilla, ZSTD)`     | `price Float64 CODEC(Gorilla, ZSTD)`               |
| Integer counters         | `CODEC(T64, ZSTD)`         | `count UInt64 CODEC(T64, ZSTD)`                    |
| Slowly changing integers | `CODEC(Delta, ZSTD)`       | `version UInt32 CODEC(Delta, ZSTD)`                |
| String (low cardinality) | `LowCardinality(String)`   | `status LowCardinality(String)`                    |
| General data             | `CODEC(ZSTD(3))`           | Default compression level 3                        |

**CRITICAL SAFETY WARNING**:

Never combine Delta/DoubleDelta with Gorilla codecs on the same column. This causes **DATA CORRUPTION** (see PR #45652). Each codec must be used independently.

```sql
-- DANGEROUS - DO NOT USE
price Float64 CODEC(Delta, Gorilla, ZSTD)  -- DATA CORRUPTION RISK

-- Safe alternatives
price Float64 CODEC(Gorilla, ZSTD)         -- Correct for floats
timestamp DateTime64 CODEC(DoubleDelta, ZSTD)  -- Correct for timestamps
```

### PARTITION BY Guidelines

PARTITION BY is for **data lifecycle management**, NOT query optimization.

**Rules**:

- Partition by time units (month, week) for TTL and data management
- Keep partition count under 1000 total across all tables
- Each partition should contain 1-300 parts maximum
- Never partition by high-cardinality columns

**Example**:

```sql
-- Correct: Monthly partitions for TTL management
PARTITION BY toYYYYMM(timestamp)

-- Wrong: Daily partitions (too many parts)
PARTITION BY toYYYYMMDD(timestamp)

-- Wrong: High-cardinality partition key
PARTITION BY user_id
```

### Anti-Patterns Checklist (v24.4+)

| Pattern                         | Severity | Modern Status      | Fix                                   |
| ------------------------------- | -------- | ------------------ | ------------------------------------- |
| Too many parts (>300/partition) | Critical | Still critical     | Reduce partition granularity          |
| Small batch inserts (<1000)     | Critical | Still critical     | Batch to 10k-100k rows                |
| High-cardinality first ORDER BY | Critical | Still critical     | Reorder: lowest cardinality first     |
| No memory limits                | High     | Still critical     | Set `max_memory_usage`                |
| Denormalization overuse         | High     | Still critical     | Use dictionaries + materialized views |
| Large JOINs                     | Medium   | **180x improved**  | Still avoid for ultra-low-latency     |
| Mutations (UPDATE/DELETE)       | Medium   | **1700x improved** | Use lightweight updates (v24.4+)      |

### Table Engine Selection

| Deployment          | Engine                | Use Case                        |
| ------------------- | --------------------- | ------------------------------- |
| ClickHouse Cloud    | `SharedMergeTree`     | Default for cloud deployments   |
| Self-hosted cluster | `ReplicatedMergeTree` | Multi-node with replication     |
| Self-hosted single  | `MergeTree`           | Single-node development/testing |

**Cloud (SharedMergeTree)**:

```sql
CREATE TABLE trades (...)
ENGINE = SharedMergeTree('/clickhouse/tables/{shard}/trades', '{replica}')
ORDER BY (exchange, symbol, timestamp);
```

**Self-hosted (ReplicatedMergeTree)**:

```sql
CREATE TABLE trades (...)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/trades', '{replica}')
ORDER BY (exchange, symbol, timestamp);
```

## Performance Accelerators

### Projections

Create alternative sort orders that ClickHouse automatically selects:

```sql
ALTER TABLE trades ADD PROJECTION trades_by_symbol (
    SELECT * ORDER BY symbol, timestamp
);
ALTER TABLE trades MATERIALIZE PROJECTION trades_by_symbol;
```

### Materialized Views

Pre-compute aggregations for dashboard queries:

```sql
CREATE MATERIALIZED VIEW trades_hourly_mv
ENGINE = SummingMergeTree()
ORDER BY (exchange, symbol, hour)
AS SELECT
    exchange,
    symbol,
    toStartOfHour(timestamp) AS hour,
    sum(quantity) AS total_volume,
    count() AS trade_count
FROM trades
GROUP BY exchange, symbol, hour;
```

### Dictionaries

Replace JOINs with O(1) dictionary lookups (6.6x faster):

```sql
CREATE DICTIONARY symbol_info (
    symbol String,
    name String,
    sector String
)
PRIMARY KEY symbol
SOURCE(CLICKHOUSE(TABLE 'symbols'))
LAYOUT(FLAT())
LIFETIME(3600);

-- Use in queries
SELECT
    symbol,
    dictGet('symbol_info', 'name', symbol) AS symbol_name
FROM trades;
```

## Scripts

Execute comprehensive schema audit:

```bash
clickhouse-client --multiquery < scripts/schema-audit.sql
```

The audit script checks:

- Part count per partition (threshold: 300)
- Compression ratios by column
- Query performance patterns
- Replication lag (if applicable)
- Memory usage patterns

## Additional Resources

### Reference Files

| Reference                                                                                  | Content                                  |
| ------------------------------------------------------------------------------------------ | ---------------------------------------- |
| [`references/schema-design-workflow.md`](./references/schema-design-workflow.md)           | Complete workflow with examples          |
| [`references/compression-codec-selection.md`](./references/compression-codec-selection.md) | Decision tree + benchmarks               |
| [`references/anti-patterns-and-fixes.md`](./references/anti-patterns-and-fixes.md)         | 13 deadly sins + v24.4+ status           |
| [`references/audit-and-diagnostics.md`](./references/audit-and-diagnostics.md)             | Query interpretation guide               |
| [`references/idiomatic-architecture.md`](./references/idiomatic-architecture.md)           | Parameterized views, dictionaries, dedup |

### External Documentation

- [ClickHouse Best Practices](https://clickhouse.com/docs/best-practices)
- [Altinity Knowledge Base](https://kb.altinity.com/)
- [ClickHouse Blog](https://clickhouse.com/blog)

## Related Skills

| Skill                                      | Purpose                       |
| ------------------------------------------ | ----------------------------- |
| `devops-tools:clickhouse-cloud-management` | User/permission management    |
| `quality-tools:schema-e2e-validation`      | YAML schema contracts         |
| `quality-tools:multi-agent-e2e-validation` | Database migration validation |
