---
adr: 2025-12-10-clickhouse-skill-delegation
source: ~/.claude/plans/lazy-forging-engelbart.md
implementation-status: in_progress
phase: phase-2
last-updated: 2025-12-10
---

# ClickHouse Skill Delegation Enhancement

**ADR**: [ClickHouse Skill Delegation Enhancement](/docs/adr/2025-12-10-clickhouse-skill-delegation.md)

## Problem Statement

When users invoke `clickhouse-architect` (the hub skill), Claude doesn't automatically delegate to related skills when the user's needs extend beyond schema design. Users miss the workflow to `cloud-management` → `pydantic-config` → `schema-e2e-validation`.

## Solution: Add Delegation Guide to Hub Skill

**Approach**: Keep current names, add prescriptive delegation guidance so the architect skill knows when to invoke related skills.

---

## Implementation Plan

### Step 1: Add Skill Delegation Guide to clickhouse-architect

**File**: `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`

Add after "Core Methodology" section:

```markdown
## Skill Delegation Guide

This skill is the **hub** for ClickHouse-related tasks. When the user's needs extend beyond schema design, invoke the related skills below.

### Delegation Decision Matrix

| User Need                                       | Invoke Skill                               | Trigger Phrases                                      |
| ----------------------------------------------- | ------------------------------------------ | ---------------------------------------------------- |
| Create database users, manage permissions       | `devops-tools:clickhouse-cloud-management` | "create user", "GRANT", "permissions", "credentials" |
| Configure DBeaver, generate connection JSON     | `devops-tools:clickhouse-pydantic-config`  | "DBeaver", "client config", "connection setup"       |
| Validate schema contracts against live database | `quality-tools:schema-e2e-validation`      | "validate schema", "Earthly E2E", "schema contract"  |

### Typical Workflow Sequence

1. **Schema Design** (THIS SKILL) → Design ORDER BY, compression, partitioning
2. **User Setup** → `clickhouse-cloud-management` (if cloud credentials needed)
3. **Client Config** → `clickhouse-pydantic-config` (generate DBeaver JSON)
4. **Validation** → `schema-e2e-validation` (CI/CD schema contracts)

### Example: Full Stack Request

**User**: "I need to design a trades table for ClickHouse Cloud and set up DBeaver to query it."

**Expected behavior**:

1. Use THIS skill for schema design
2. Invoke `clickhouse-cloud-management` for creating database user
3. Invoke `clickhouse-pydantic-config` for DBeaver configuration
```

---

### Step 2: Update Trigger Description in clickhouse-architect

**File**: `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`

Update frontmatter description to include delegation guidance:

```yaml
description: >
  ClickHouse schema design authority (hub skill). Use when designing schemas,
  selecting compression codecs, tuning ORDER BY, optimizing queries, or
  reviewing table structure. **Delegates to**: clickhouse-cloud-management
  for user creation, clickhouse-pydantic-config for DBeaver config,
  schema-e2e-validation for YAML contracts. Triggers: "design ClickHouse
  schema", "compression codecs", "MergeTree optimization", "ORDER BY tuning",
  "partition key", "ClickHouse performance", "SharedMergeTree",
  "ReplicatedMergeTree", "migrate to ClickHouse".
```

---

### Step 3: Add Prescriptive Triggers to Spoke Skills

**File**: `plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md`

Add after "Troubleshooting" section:

```markdown
## Next Steps After User Creation

After creating a ClickHouse user, invoke **`devops-tools:clickhouse-pydantic-config`** to generate DBeaver configuration with the new credentials.
```

**File**: `plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md`

Already has "Credential Prerequisites" - verify it includes:

```markdown
**Skill chain**: `clickhouse-cloud-management` → `.env` → `clickhouse-pydantic-config`
```

**File**: `plugins/quality-tools/skills/schema-e2e-validation/SKILL.md`

Add "Design Authority" section:

```markdown
## Design Authority

This skill validates schemas but does not design them. For schema design guidance (ORDER BY, compression, partitioning), invoke **`quality-tools:clickhouse-architect`** first.
```

---

### Step 4: Add Related Skills to schema-e2e-validation

**File**: `plugins/quality-tools/skills/schema-e2e-validation/SKILL.md`

Add "Related Skills" section:

```markdown
## Related Skills

| Skill                                      | Purpose                         |
| ------------------------------------------ | ------------------------------- |
| `quality-tools:clickhouse-architect`       | Schema design before validation |
| `devops-tools:clickhouse-cloud-management` | Cloud credentials for E2E tests |
| `devops-tools:clickhouse-pydantic-config`  | Client configuration            |
```

---

## Files to Modify

| File                                                               | Change                                             |
| ------------------------------------------------------------------ | -------------------------------------------------- |
| `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`       | Add Delegation Guide section, update description   |
| `plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md` | Add "Next Steps" prescriptive section              |
| `plugins/quality-tools/skills/schema-e2e-validation/SKILL.md`      | Add "Design Authority" + "Related Skills" sections |

---

## Validation

After implementation, test with these prompts:

1. "Design a trades table for ClickHouse Cloud and help me connect via DBeaver"
   - Should invoke: architect → cloud-management → pydantic-config

2. "I need to validate my schema contract against live ClickHouse"
   - Should invoke: schema-e2e-validation (possibly architect first for design review)

3. "Create a read-only user for my ClickHouse Cloud instance"
   - Should invoke: cloud-management → suggest pydantic-config for client setup

---

## Success Criteria

- [x] Delegation Guide section added to clickhouse-architect
- [x] Frontmatter description updated with delegation info
- [x] Next Steps section added to clickhouse-cloud-management
- [x] Design Authority and Related Skills added to schema-e2e-validation
- [x] ADR code traceability comments added to modified files
