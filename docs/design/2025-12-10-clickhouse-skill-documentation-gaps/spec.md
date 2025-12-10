---
adr: 2025-12-10-clickhouse-skill-documentation-gaps
source: ~/.claude/plans/lazy-forging-engelbart.md
implementation-status: completed
phase: phase-1
last-updated: 2025-12-10
---

# Implementation Spec: ClickHouse Skill Documentation Gaps

**ADR**: [Close Documentation Gaps in ClickHouse Skill Ecosystem](/docs/adr/2025-12-10-clickhouse-skill-documentation-gaps.md)

## Summary

Close documentation gaps in 5 ClickHouse-related skills by adding port clarifications, credential flow documentation, specialized trigger phrases, and PyPI policy warnings.

## Implementation Tasks

- [x] C2: Test ClickHouse Cloud ports empirically (443 vs 8443) - Both work (load balancer accepts both)
- [x] C5: Add Credential Prerequisites section to clickhouse-pydantic-config
- [x] C6: Specialize trigger phrases in clickhouse-architect and schema-e2e-validation
- [x] C8: Add PyPI policy warning to doppler-workflows

## Files to Modify

### `plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md`

**Changes**: Update port documentation based on empirical testing

Current (line ~28-46):

```markdown
Port: 443 (HTTPS)
```

Target:

```markdown
## ClickHouse Cloud Ports

| Port | Protocol   | Use Case                                 |
| ---- | ---------- | ---------------------------------------- |
| 8443 | HTTPS      | HTTP interface, DBeaver JDBC, REST API   |
| 9440 | Native TLS | clickhouse-client, Python native drivers |
```

### `plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md`

**Changes**: Add Credential Prerequisites section after Quick Start

New section:

````markdown
## Credential Prerequisites

Before using cloud mode, obtain credentials:

1. **From 1Password**: Use `clickhouse-cloud-management` skill to retrieve or create users
2. **To .env file**: Store in `.env` (gitignored):

```bash
CLICKHOUSE_USER_READONLY=your_user
CLICKHOUSE_PASSWORD_READONLY=your_password
```
````

**Skill chain**: `clickhouse-cloud-management` (create user) → `.env` → `clickhouse-pydantic-config` (generate config)

````

### `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`

**Changes**: Specialize trigger phrases for "design" focus

Current description (line 4-8):
```yaml
description: >
  This skill should be used when the user asks to "design ClickHouse schema",
  "select compression codecs", "audit table structure", "optimize query performance",
  "migrate to ClickHouse", "tune ORDER BY", "fix partition key", "review schema",
  or mentions "ClickHouse performance", "compression benchmark", "schema validation",
  "MergeTree optimization", "SharedMergeTree", "ReplicatedMergeTree".
````

Target description:

```yaml
description: >
  This skill should be used when the user asks to "design ClickHouse schema",
  "select compression codecs", "audit table structure", "optimize query performance",
  "migrate to ClickHouse", "tune ORDER BY", "fix partition key", "review schema design",
  or mentions "ClickHouse performance", "compression benchmark", "MergeTree optimization",
  "SharedMergeTree", "ReplicatedMergeTree". For YAML schema contract validation,
  use schema-e2e-validation skill instead.
```

### `plugins/quality-tools/skills/schema-e2e-validation/SKILL.md`

**Changes**: Specialize trigger phrases for "validate YAML" focus

Current description (line 3):

```yaml
description: Run Earthly E2E validation for schema-first data contracts. Use when validating schema changes, testing YAML against live ClickHouse, or regenerating types/DDL/docs.
```

Target description:

```yaml
description: >
  Run Earthly E2E validation for YAML schema contracts. Use when validating YAML schema
  changes, testing schema contracts against live ClickHouse, or regenerating Python types,
  DDL, and docs from YAML. For SQL schema design and optimization, use clickhouse-architect
  skill instead.
```

### `plugins/devops-tools/skills/doppler-workflows/SKILL.md`

**Changes**: Add PyPI policy warning section

New section (add after existing content):

```markdown
## PyPI Publishing Policy

For PyPI publishing, see [`pypi-doppler` skill](../pypi-doppler/SKILL.md) for **LOCAL-ONLY** workspace policy.

**Do NOT** configure PyPI publishing in GitHub Actions or CI/CD pipelines.
```

## Success Criteria

- [x] Port documentation updated (after empirical test) - Both 443 and 8443 work
- [x] Credential flow section added to clickhouse-pydantic-config
- [x] Trigger phrases disambiguated between architect and e2e skills
- [x] PyPI policy warning added to doppler-workflows
- [ ] All modified files pass Prettier formatting

## Key Decisions

| Decision         | Value                                        |
| ---------------- | -------------------------------------------- |
| Scope            | Documentation only (no structural changes)   |
| Port source      | ClickHouse official docs + empirical testing |
| Credential flow  | Document chain, don't automate               |
| Trigger strategy | Add cross-reference in description           |
