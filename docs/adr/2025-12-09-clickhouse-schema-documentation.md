---
status: accepted
date: 2025-12-09
decision-maker: terrylica
consulted:
  [
    Web-Research-Agent (COMMENT ON evidence),
    Explore-Agent (cc-skills ClickHouse skills),
    Explore-Agent (plugin architecture),
  ]
research-method: multi-agent-parallel
clarification-iterations: 4
perspectives:
  [Developer-Experience, AI-Integration, Evidence-Based, Maintainability]
---

# Add Schema Documentation Guidance to ClickHouse Architect Skill

**Design Spec**: [Implementation Spec](/docs/design/2025-12-09-clickhouse-schema-documentation/spec.md)

## Context and Problem Statement

The claim that "COMMENT ON statements are the #1 way to help AI understand schema relationships" is circulating in the data community. However:

1. The claim lacks quantitative evidence and context
2. ClickHouse uses non-standard syntax (`COMMENT COLUMN`, not `COMMENT ON`)
3. The existing `clickhouse-architect` skill has no schema documentation guidance
4. Research shows semantic layers outperform comments alone at scale

How should we document schema metadata best practices for AI understanding in the ClickHouse context, with evidence-based positioning?

### Before/After

<!-- graph-easy source: before-diagram -->

```
 ⏮️ Before: Schema Design Without Documentation

        ╭───────────────────────────────╮
        │           Developer           │
        ╰───────────────────────────────╯
          │
          │
          ∨
        ┌───────────────────────────────┐
        │ clickhouse-architect SKILL.md │
        └───────────────────────────────┘
          │
          │
          ∨
        ┌───────────────────────────────┐
        │        5-Step Workflow        │
        └───────────────────────────────┘
          │
          │
          ∨
        ┌───────────────────────────────┐
        │        Schema Created         │
        └───────────────────────────────┘
          │
          │
          ∨
        ╭───────────────────────────────╮
        │       AI Queries Schema       │
        ╰───────────────────────────────╯
          :
          :
          ∨
        ╔═══════════════════════════════╗
        ║       Low Comprehension       ║
        ╚═══════════════════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Schema Design Without Documentation"; flow: south; }
[ Developer ] { shape: rounded; }
[ clickhouse-architect SKILL.md ]
[ 5-Step Workflow ]
[ Schema Created ]
[ AI Queries Schema ] { shape: rounded; }
[ Low Comprehension ] { border: double; }

[ Developer ] -> [ clickhouse-architect SKILL.md ]
[ clickhouse-architect SKILL.md ] -> [ 5-Step Workflow ]
[ 5-Step Workflow ] -> [ Schema Created ]
[ Schema Created ] -> [ AI Queries Schema ]
[ AI Queries Schema ] ..> [ Low Comprehension ]
```

</details>

<!-- graph-easy source: after-diagram -->

```
 ⏭️ After: Schema Design With Documentation

      ╭───────────────────────────────╮
      │           Developer           │
      ╰───────────────────────────────╯
        │
        │
        ∨
      ┌───────────────────────────────┐
      │ clickhouse-architect SKILL.md │
      └───────────────────────────────┘
        │
        │
        ∨
      ┌───────────────────────────────┐
      │        6-Step Workflow        │
      └───────────────────────────────┘
        │
        │
        ∨
      ┌───────────────────────────────┐
      │       Schema + COMMENTs       │
      └───────────────────────────────┘
        │
        │
        ∨
      ╭───────────────────────────────╮
      │       AI Queries Schema       │
      ╰───────────────────────────────╯
        │
        │
        ∨
      ╔═══════════════════════════════╗
      ║         20-27% Better         ║
      ╚═══════════════════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Schema Design With Documentation"; flow: south; }
[ Developer ] { shape: rounded; }
[ clickhouse-architect SKILL.md ]
[ 6-Step Workflow ]
[ Schema + COMMENTs ]
[ AI Queries Schema ] { shape: rounded; }
[ 20-27% Better ] { border: double; }

[ Developer ] -> [ clickhouse-architect SKILL.md ]
[ clickhouse-architect SKILL.md ] -> [ 6-Step Workflow ]
[ 6-Step Workflow ] -> [ Schema + COMMENTs ]
[ Schema + COMMENTs ] -> [ AI Queries Schema ]
[ AI Queries Schema ] -> [ 20-27% Better ]
```

</details>

## Decision Drivers

- **Evidence-Based**: Position based on quantitative research (AtScale, SNAILS, TigerData)
- **ClickHouse-Specific**: Use correct syntax (COMMENT COLUMN, not COMMENT ON)
- **Practical Guidance**: Include naming conventions (SNAILS research)
- **Scalability Context**: Document when to graduate beyond comments

## Considered Options

1. **New standalone skill** - Create `clickhouse-schema-documentation` skill
2. **Extend clickhouse-architect** - Add reference file to existing skill
3. **Doc-tools placement** - Add to documentation standards plugin
4. **Ignore the claim** - Let users figure it out

## Decision Outcome

**Chosen option**: "Extend clickhouse-architect with new reference file"

This approach:

- Integrates with existing schema design workflow
- Keeps the ClickHouse ecosystem compact
- Adds Step 6 (documentation) to the 5-step workflow
- Provides evidence-based positioning

### Implementation

Create `references/schema-documentation.md` in the clickhouse-architect skill with:

1. Evidence-based positioning (comments = 20-27%, semantic layers = 3-4x)
2. ClickHouse COMMENT syntax (table and column level)
3. Naming conventions (SNAILS research)
4. Replication considerations
5. "When to graduate" guidance

### Consequences

**Good**:

- Corrects overstated claims with evidence
- Provides actionable ClickHouse-specific guidance
- Integrates with existing schema design workflow
- Includes naming conventions (often overlooked)

**Neutral**:

- Increases clickhouse-architect skill scope slightly
- Requires updating SKILL.md reference table

**Bad**:

- May disappoint users expecting "silver bullet" solution

## Architecture

<!-- graph-easy source: architecture-diagram -->

```
 🏗️ Architecture: Schema Documentation Integration

    ┌──────────┐     ┏━━━━━━━━━━━━━━━━━━━━━━━━━┓
    │ SKILL.md │ <── ┃  clickhouse-architect   ┃
    └──────────┘     ┗━━━━━━━━━━━━━━━━━━━━━━━━━┛
                       │
                       │
                       ∨
                     ┌─────────────────────────┐
                     │       references/       │
                     └─────────────────────────┘
                       │
                       │
                       ∨
                     ╔═════════════════════════╗
                     ║ schema-documentation.md ║
                     ╚═════════════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Architecture: Schema Documentation Integration"; flow: south; }
[ clickhouse-architect ] { border: bold; }
[ SKILL.md ]
[ references/ ]
[ schema-documentation.md ] { border: double; }

[ clickhouse-architect ] -> [ SKILL.md ]
[ clickhouse-architect ] -> [ references/ ]
[ references/ ] -> [ schema-documentation.md ]
```

</details>

### Key Components

| Component                            | Purpose                               |
| ------------------------------------ | ------------------------------------- |
| `references/schema-documentation.md` | New reference file with full guidance |
| `SKILL.md` update                    | Add reference link to table           |
| Schema Design Workflow               | Add Step 6 for documentation          |

### Research Evidence Summary

| Approach        | AI Accuracy Improvement   | Source                    |
| --------------- | ------------------------- | ------------------------- |
| Schema Comments | 20-27%                    | TigerData, Oracle AI      |
| Semantic Layers | 3-4x (16%→54%)            | AtScale, Snowflake Cortex |
| Natural Naming  | Statistically significant | SNAILS (SIGMOD 2025)      |

## More Information

### ClickHouse Syntax (NOT Standard SQL)

```sql
-- Table comments
CREATE TABLE trades (...) COMMENT 'Description here'
ALTER TABLE trades MODIFY COMMENT 'Updated description'

-- Column comments
ALTER TABLE trades COMMENT COLUMN price 'Execution price in quote currency'
```

### Replication Caveats

- `MODIFY COMMENT` (table): Single replica only
- `COMMENT COLUMN`: Propagates correctly on ReplicatedMergeTree
- Materialized View column comments: Do NOT propagate

### Related ADRs

- [clickhouse-architect-skill](/docs/adr/2025-12-09-clickhouse-architect-skill.md) - Parent skill ADR

### Sources

- AtScale 2025: "How Semantic Layers Make GenAI 3X More Accurate"
- SNAILS (SIGMOD 2025): Schema naming impact on NL-to-SQL accuracy
- TigerData: "The Database Has a New User—LLMs"
- ClickHouse Blog: "How We Made Our Internal Data Warehouse AI-First"
