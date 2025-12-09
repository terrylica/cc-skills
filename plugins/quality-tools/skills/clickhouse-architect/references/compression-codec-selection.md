**Skill**: [ClickHouse Architect](../SKILL.md)

# Compression Codec Selection

<!-- ADR: 2025-12-09-clickhouse-architect-skill -->

Decision guide and benchmarks for selecting optimal ClickHouse compression codecs.

## Quick Selection Guide

| Column Type               | Recommended Codec      | Example                                            |
| ------------------------- | ---------------------- | -------------------------------------------------- |
| DateTime/DateTime64       | DoubleDelta + ZSTD     | `timestamp DateTime64(3) CODEC(DoubleDelta, ZSTD)` |
| Float (prices, gauges)    | Gorilla + ZSTD         | `price Float64 CODEC(Gorilla, ZSTD)`               |
| Integer (counters, IDs)   | T64 + ZSTD             | `count UInt64 CODEC(T64, ZSTD)`                    |
| Integer (slowly changing) | Delta + ZSTD           | `version UInt32 CODEC(Delta, ZSTD)`                |
| String (< 10k unique)     | LowCardinality(String) | `status LowCardinality(String)`                    |
| String (high cardinality) | ZSTD(3)                | `description String CODEC(ZSTD(3))`                |
| General/Mixed             | ZSTD(3)                | Default compression level 3                        |

## CRITICAL SAFETY WARNING

**Never combine Delta/DoubleDelta with Gorilla codecs**.

This combination causes **DATA CORRUPTION** (PR #45652):

```sql
-- DANGEROUS - DATA CORRUPTION RISK
column Float64 CODEC(Delta, Gorilla, ZSTD)
column Float64 CODEC(DoubleDelta, Gorilla, ZSTD)

-- SAFE - Use codecs independently
price Float64 CODEC(Gorilla, ZSTD)
timestamp DateTime64 CODEC(DoubleDelta, ZSTD)
```

## Codec Reference

### DoubleDelta

**Best for**: Monotonically increasing timestamps, sequence numbers

**How it works**: Stores difference of differences (second derivative)

**Typical ratio**: 10-50x for timestamps

```sql
timestamp DateTime64(3) CODEC(DoubleDelta, ZSTD)
event_time DateTime CODEC(DoubleDelta, ZSTD)
sequence_id UInt64 CODEC(DoubleDelta, ZSTD)  -- If monotonic
```

### Gorilla

**Best for**: Float values (prices, measurements, gauges)

**How it works**: XOR-based encoding for IEEE 754 floats

**Typical ratio**: 5-15x for financial data

**Restriction**: Float32/Float64 only

```sql
price Float64 CODEC(Gorilla, ZSTD)
temperature Float32 CODEC(Gorilla, ZSTD)
percentage Float64 CODEC(Gorilla, ZSTD)
```

### T64

**Best for**: General integers, especially with ZSTD

**How it works**: Transform to 64-bit chunks, compress value distribution

**Typical ratio**: 3-8x

**Note**: Works best with ZSTD, not LZ4

```sql
count UInt64 CODEC(T64, ZSTD)
user_id UInt32 CODEC(T64, ZSTD)
quantity Int64 CODEC(T64, ZSTD)
```

### Delta

**Best for**: Slowly changing integer values

**How it works**: Stores differences between consecutive values

**Typical ratio**: 5-20x for small deltas

```sql
version UInt32 CODEC(Delta, ZSTD)
revision Int32 CODEC(Delta, ZSTD)
```

### LowCardinality

**Best for**: String columns with < 10,000 unique values

**How it works**: Dictionary encoding with integer references

**Typical improvement**: 4x query speed, 3-5x compression

```sql
status LowCardinality(String)
country LowCardinality(String)
exchange LowCardinality(String)
```

### ZSTD

**Best for**: General-purpose compression, always as final codec

**Levels**: 1-22 (default 1, recommended 3 for balance)

```sql
-- Level 3 is good balance of speed/ratio
description String CODEC(ZSTD(3))
json_payload String CODEC(ZSTD(3))
```

### LZ4

**Best for**: Speed-critical scenarios (slightly faster than ZSTD)

**Trade-off**: 10-20% worse compression than ZSTD

```sql
-- Only if decompression speed is critical
log_line String CODEC(LZ4)
```

## Codec Chaining

Always chain specialized codecs with general-purpose compression:

| Specialized Codec | Chain With |
| ----------------- | ---------- |
| DoubleDelta       | ZSTD       |
| Gorilla           | ZSTD       |
| T64               | ZSTD       |
| Delta             | ZSTD       |

**Always chain** DoubleDelta, Gorilla, T64, Delta with ZSTD or LZ4.

## Benchmark Results

Typical compression ratios (higher is better):

| Column Type      | No Codec | ZSTD Only | Specialized + ZSTD |
| ---------------- | -------- | --------- | ------------------ |
| DateTime64       | 1x       | 3-4x      | 15-50x             |
| Float prices     | 1x       | 2-3x      | 8-15x              |
| Integer counters | 1x       | 2-4x      | 5-10x              |
| Low-card strings | 1x       | 3-5x      | 10-20x (LowCard)   |

## Validation Query

Check compression effectiveness:

```sql
SELECT
    column,
    type,
    compression_codec,
    formatReadableSize(data_compressed_bytes) AS compressed,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed,
    round(data_uncompressed_bytes / data_compressed_bytes, 2) AS ratio
FROM system.columns
WHERE database = 'your_database'
    AND table = 'your_table'
ORDER BY data_uncompressed_bytes DESC;
```

## Migration

To change codec on existing column:

```sql
-- Add new column with desired codec
ALTER TABLE trades ADD COLUMN price_new Float64 CODEC(Gorilla, ZSTD);

-- Copy data
ALTER TABLE trades UPDATE price_new = price WHERE 1;

-- Swap columns
ALTER TABLE trades DROP COLUMN price;
ALTER TABLE trades RENAME COLUMN price_new TO price;
```

## Related References

- [Schema Design Workflow](./schema-design-workflow.md)
- [Anti-Patterns and Fixes](./anti-patterns-and-fixes.md)
