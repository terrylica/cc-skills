---
adr: 2025-12-09-clickhouse-schema-documentation
source: ~/.claude/plans/adaptive-leaping-sloth.md
implementation-status: completed
phase: phase-1
last-updated: 2025-12-09
---

# Implementation Spec: Schema Documentation Guidance for ClickHouse Architect

**ADR**: [Add Schema Documentation Guidance to ClickHouse Architect Skill](/docs/adr/2025-12-09-clickhouse-schema-documentation.md)

## Summary

Extend the existing `clickhouse-architect` skill with a new reference file covering COMMENT patterns and naming conventions for AI schema understanding. Correct the overstated "#1" claim with evidence-based positioning from AtScale, SNAILS, and TigerData research.

## Implementation Tasks

- [x] Create `references/schema-documentation.md` reference file
- [x] Update `SKILL.md` with reference link in table
- [x] Add Step 6 mention in Core Methodology section

## Files to Create

### `plugins/quality-tools/skills/clickhouse-architect/references/schema-documentation.md`

Content structure:

| Section                    | Purpose                                    |
| -------------------------- | ------------------------------------------ |
| Evidence-Based Positioning | Quantitative research (20-27% vs 3-4x)     |
| ClickHouse COMMENT Syntax  | Table and column level examples            |
| Naming Conventions         | SNAILS research patterns and anti-patterns |
| Replication Considerations | Caveat table for different engine types    |
| Integration with Workflow  | Add Step 6 to schema design workflow       |
| When to Graduate           | Scale thresholds for semantic layers       |

## Files to Modify

### `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`

Changes:

1. Add reference link to "Additional Resources" table
2. Brief mention in "Core Methodology" after step 5

## Evidence Summary

| Approach        | AI Accuracy Improvement   | Source                    |
| --------------- | ------------------------- | ------------------------- |
| Schema Comments | 20-27%                    | TigerData, Oracle AI      |
| Semantic Layers | 3-4x (16%→54%)            | AtScale, Snowflake Cortex |
| Natural Naming  | Statistically significant | SNAILS (SIGMOD 2025)      |

## ClickHouse Syntax Reference

**Table comments:**

```sql
CREATE TABLE trades (...) COMMENT 'Description here'
ALTER TABLE trades MODIFY COMMENT 'Updated description'
```

**Column comments:**

```sql
ALTER TABLE trades COMMENT COLUMN price 'Execution price in quote currency'
```

**Query comments:**

```sql
SELECT name, comment FROM system.columns
WHERE database = 'default' AND table = 'trades';
```

## Replication Caveats

| Operation                | ReplicatedMergeTree  | SharedMergeTree    |
| ------------------------ | -------------------- | ------------------ |
| `MODIFY COMMENT` (table) | Single replica only  | Propagates         |
| `COMMENT COLUMN`         | Propagates correctly | Propagates         |
| MV column comments       | Does NOT propagate   | Does NOT propagate |

## Success Criteria

- [x] New reference file created at correct path
- [x] SKILL.md references the new file
- [x] ClickHouse syntax is accurate (COMMENT COLUMN, not COMMENT ON)
- [x] Evidence citations included (AtScale, SNAILS, TigerData)
- [x] Replication caveats documented
- [x] Naming conventions section with examples
- [x] "When to graduate" guidance included

## Key Decisions

| Decision  | Value                                                 |
| --------- | ----------------------------------------------------- |
| Placement | Extend `clickhouse-architect` with new reference file |
| Scope     | COMMENT syntax + naming conventions (SNAILS research) |
| Scripts   | None - documentation only                             |
| Messaging | Correct the claim with quantitative evidence          |
