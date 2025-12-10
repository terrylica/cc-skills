---
status: accepted
date: 2025-12-10
decision-makers: terryli
consulted: claude-code
informed: cc-skills-users
---

# Close Documentation Gaps in ClickHouse Skill Ecosystem

## Context and Problem Statement

The cc-skills repository contains 5 ClickHouse-related skills that work together but lack cross-references and consistent documentation. Analysis revealed 6 actionable gaps (3 HIGH, 3 MEDIUM severity) that confuse users about:

1. Which port to use for ClickHouse Cloud (443 vs 8443)
2. How credentials flow between skills
3. Which skill handles "schema validation" requests
4. PyPI publishing policy enforcement

## Decision Drivers

- Users report confusion about port configuration
- No documented credential handoff between clickhouse-cloud-management and clickhouse-pydantic-config
- Trigger phrase overlap between clickhouse-architect and schema-e2e-validation
- Doppler policy for PyPI publishing not enforced via cross-references

## Considered Options

1. **Merge competing skills** - Combine schema-e2e-validation into clickhouse-pydantic-config
2. **Add cross-references and clarifications** - Document gaps without structural changes
3. **Create umbrella "ClickHouse Workflow" skill** - New skill orchestrating others

## Decision Outcome

Chosen option: **"Add cross-references and clarifications"** because:

- Skills are orthogonal, not competing (schema definition vs connection config)
- Minimal changes preserve existing user workflows
- Documentation fixes are lower risk than structural changes

### Architecture Visualization

**Before: Skills Without Cross-References**

<details>
<summary>graph-easy source</summary>

```
[clickhouse-architect] --> [clickhouse-cloud-management]
[clickhouse-architect] --> [clickhouse-pydantic-config]
[clickhouse-architect] --> [schema-e2e-validation]
[clickhouse-cloud-management] --> [clickhouse-pydantic-config]
```

</details>

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 ∨
┌───────────────────────┐     ┌─────────────────────────────┐     ┌────────────────────────────┐
│ clickhouse-architect  │ ──> │ clickhouse-cloud-management │ ──> │ clickhouse-pydantic-config │
└───────────────────────┘     └─────────────────────────────┘     └────────────────────────────┘
  │
  │
  ∨
┌───────────────────────┐
│ schema-e2e-validation │
└───────────────────────┘
```

**After: Skills With Documentation + Doppler Policy**

<details>
<summary>graph-easy source</summary>

```
[clickhouse-architect] --> [clickhouse-cloud-management]
[clickhouse-architect] --> [clickhouse-pydantic-config]
[clickhouse-architect] --> [schema-e2e-validation]
[clickhouse-cloud-management] --> [clickhouse-pydantic-config]
[doppler-workflows] --> [pypi-doppler]
```

</details>

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 ∨
┌───────────────────────┐     ┌─────────────────────────────┐     ┌────────────────────────────┐
│ clickhouse-architect  │ ──> │ clickhouse-cloud-management │ ──> │ clickhouse-pydantic-config │
└───────────────────────┘     └─────────────────────────────┘     └────────────────────────────┘
  │
  │
  ∨
┌───────────────────────┐
│ schema-e2e-validation │
└───────────────────────┘
┌───────────────────────┐     ┌─────────────────────────────┐
│   doppler-workflows   │ ──> │        pypi-doppler         │
└───────────────────────┘     └─────────────────────────────┘
```

### Confirmation

- Skills remain orthogonal (no structural changes)
- Documentation changes are additive
- Existing workflows unaffected

### Consequences

**Good:**

- Clear port guidance (8443 for HTTP, 9440 for Native)
- Credential flow documented
- Trigger disambiguation prevents wrong skill invocation
- PyPI policy enforced via cross-reference

**Bad:**

- Requires maintaining cross-references when skills evolve
- Port information duplicated across skills

**Neutral:**

- C1 (deployment workflow) and C3 (missing ADR) deferred to future work

## Conflict Resolution Summary

| ID  | Conflict                | Resolution                                   |
| --- | ----------------------- | -------------------------------------------- |
| C1  | Missing deployment flow | DEFER - tackle after documentation fixes     |
| C2  | Port 443 vs 8443        | TEST EMPIRICALLY then update docs            |
| C3  | Missing ADR (e2e)       | DEFER - address after documentation fixes    |
| C4  | No Related Skills       | SKIP - user decision                         |
| C5  | Credential handoff      | IMPLEMENT in clickhouse-pydantic-config      |
| C6  | Trigger ambiguity       | IMPLEMENT specialized triggers               |
| C7  | YAML vs SQL SSoT        | RESOLVED - orthogonal concerns, not conflict |
| C8  | Doppler policy gap      | IMPLEMENT warning + redirect to pypi-doppler |

## More Information

### Files to Modify

| File                                                               | Change                                      |
| ------------------------------------------------------------------ | ------------------------------------------- |
| `plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md` | Clarify port usage (8443 HTTP, 9440 Native) |
| `plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md`  | Add Credential Prerequisites section        |
| `plugins/quality-tools/skills/clickhouse-architect/SKILL.md`       | Specialize triggers for "design"            |
| `plugins/quality-tools/skills/schema-e2e-validation/SKILL.md`      | Specialize triggers for "validate YAML"     |
| `plugins/devops-tools/skills/doppler-workflows/SKILL.md`           | Add PyPI policy warning                     |

### Research Sources

- [ClickHouse Cloud Ports Documentation](https://clickhouse.com/docs/cloud/security/cloud-endpoints-api)
- Plan file: `~/.claude/plans/lazy-forging-engelbart.md`
