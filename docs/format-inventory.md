# Format Inventory: Cross-Platform Format Analysis

**Task:** Task 2: Cross-Platform Format Analysis  
**Date:** 2026-03-02  
**Status:** Completed

## Executive Summary

This analysis catalogs all documentation formats across the cc-skills ecosystem and identifies inconsistencies. The ecosystem uses **3 primary markdown types** (SKILL.md, CLAUDE.md, README.md), **2 JSON schemas** for validation, and **YAML for configuration**. Overall, the format strategy is consistent, with minor inconsistencies noted below.

---

## 1. Documentation Format Inventory

### 1.1 Markdown File Types

| Type | Count | Location | Frontmatter | Purpose |
|------|-------|----------|-------------|---------|
| **SKILL.md** | 164 | `plugins/*/skills/*/SKILL.md` | YAML | Skill definitions with metadata |
| **CLAUDE.md** | 26 | `plugins/*/CLAUDE.md`, root | None | Claude Code context for plugins |
| **README.md** | 31 | `plugins/*/README.md` | None | Human-facing plugin documentation |
| **docs/*.md** | 88 | `docs/` | None | Reference docs, ADRs, design specs |
| **evolution-log.md** | ~100+ | `skills/*/references/` | None | Skill version history |
| **references/*.md** | ~400+ | `skills/*/references/` | None | Skill reference documentation |

### 1.2 JSON Configuration Files

| File | Count | Purpose |
|------|-------|---------|
| `marketplace.json` | 1 | Plugin registry (SSoT) |
| `hooks.json` | 23 | Hook configurations (one per plugin) |
| `package.json` | 1 | Node dependencies |
| `plugin.json` | 1 | Root plugin definition |
| `*.schema.json` | 5 | JSON schemas for validation |

**JSON Schema Files:**
- `scripts/marketplace.schema.json` — Validates marketplace.json
- `scripts/hooks.schema.json` — Validates hooks.json
- `plugins/devops-tools/skills/session-chronicle/references/provenance-schema.json`
- `plugins/devops-tools/skills/session-chronicle/references/s3-manifest-schema.json`
- `plugins/devops-tools/skills/session-chronicle/references/session-entry-schema.json`

### 1.3 YAML Configuration Files

| File | Count | Purpose |
|------|-------|---------|
| `.releaserc.yml` | 1 | Semantic-release configuration |
| `lychee.toml` | 1 | Link checking configuration |
| `sgconfig.yml` | 1 | ast-grep configuration |
| `skills/*/assets/*.yaml` | ~25 | Skill-specific configurations, rules, templates |

---

## 2. SKILL.md Frontmatter Analysis

### 2.1 Standard Schema (All 164 SKILL.md files)

```yaml
---
name: <skill-name>
description: <description with TRIGGERS>
allowed-tools: <comma-separated tool list>
---
```

### 2.2 Optional Fields (Used in ~30% of skills)

| Field | Type | Usage | Example |
|-------|------|-------|---------|
| `argument-hint` | string | CLI argument hints | `"[-r repo] [-b branch]"` |
| `model` | string | Recommended model | `haiku`, `sonnet` |
| `disable-model-invocation` | boolean | Manual-only skills | `true` |

### 2.3 Inconsistencies Identified

1. **Description formatting**: Some include "TRIGGERS" keyword, others don't
2. **Tool naming**: Inconsistent casing (e.g., `AskUserQuestion` vs `askuserquestion`)
3. **argument-hint**: Missing from ~40% of skills
4. **model field**: Used inconsistently (~15% of skills)

---

## 3. CLAUDE.md Analysis

### 3.1 Root CLAUDE.md
- Location: `./CLAUDE.md`
- No frontmatter
- Contains: Navigation tables, essential commands, plugin list

### 3.2 Plugin CLAUDE.md Files (23 plugins)
- Location: `plugins/*/CLAUDE.md`
- No frontmatter
- Structure varies by plugin:
  - Some have "Hub + Sibling" navigation links
  - Some have detailed workflow documentation
  - Some have API references

### 3.3 Inconsistencies

1. **Plugin count discrepancy**: Root CLAUDE.md says "20 plugins" but marketplace.json lists 23
2. **Structure variation**: Some plugins have comprehensive docs, others minimal
3. **Navigation links**: Not all plugins include "Hub" and "Sibling" links

---

## 4. JSON Schema Usage

### 4.1 marketplace.schema.json
- **Location:** `scripts/marketplace.schema.json`
- **Purpose:** Validates `.claude-plugin/marketplace.json`
- **Standard:** JSON Schema draft-07
- **Enforces:** Required fields, naming patterns (kebab-case), version semver

### 4.2 hooks.schema.json
- **Location:** `scripts/hooks.schema.json`
- **Purpose:** Validates plugin hooks.json files
- **Standard:** JSON Schema draft-07
- **Enforces:** Valid hook event names, matcher patterns

### 4.3 Inconsistencies

1. **Schema validation not automated**: Schemas exist but not integrated into CI
2. **Session chronicle schemas**: Located in references/ rather than scripts/

---

## 5. YAML vs JSON Usage

### 5.1 When to Use JSON
- Configuration that benefits from comments (hooks.json)
- Data files with complex structure (marketplace.json)
- Files requiring strict validation

### 5.2 When to Use YAML
- Configuration files with inheritance (releaserc.yml)
- Human-edited configs with nested structures (sgconfig.yml)
- Test fixtures and rules (ast-grep rules)

### 5.3 Inconsistencies

1. **Mixed formats for similar purposes**: Some plugin configs use JSON, others could use YAML
2. **No clear guidelines**: Project lacks explicit JSON vs YAML decision criteria

---

## 6. Recommended Unified Strategy

### 6.1 Standardize SKILL.md Frontmatter

**Required Fields:**
```yaml
---
name: <kebab-case-name>
description: <description>
allowed-tools: <comma-separated tools>
---
```

**Recommended Optional Fields:**
```yaml
argument-hint: "<cli-args>"
model: <haiku|sonnet|opus>
disable-model-invocation: <true|false>
```

**Recommendations:**
1. Add `argument-hint` to all skills with CLI arguments
2. Standardize tool naming (PascalCase)
3. Remove redundant "TRIGGERS" from descriptions (search uses full text)
4. Add schema validation to `validate-plugins.mjs`

### 6.2 Standardize CLAUDE.md Files

1. **Fix plugin count**: Update root CLAUDE.md to say "23 plugins"
2. **Add navigation template**: Ensure all plugin CLAUDE.md files include:
   ```markdown
   > **Hub**: [Root CLAUDE.md](../../CLAUDE.md)
   > **Sibling**: [Other Plugin CLAUDE.md](../other-plugin/CLAUDE.md)
   ```
3. **Create CLAUDE.md template** in plugin-dev skill

### 6.3 JSON/YAML Guidelines

| Use Case | Recommended Format |
|----------|-------------------|
| Plugin registry | JSON (marketplace.json) |
| Hooks configuration | JSON (hooks.json) |
| Release config | YAML (.releaserc.yml) |
| Link checking | YAML (lychee.toml) |
| Code analysis rules | YAML (*.yml) |
| Data schemas | JSON (*.schema.json) |

### 6.4 Validation Integration

1. **Add JSON schema validation** to `scripts/validate-plugins.mjs`
2. **Create SKILL.md frontmatter validator** using existing schemas
3. **Automate CLAUDE.md navigation link checking** with lychee

---

## 7. Summary of Findings

| Aspect | Status | Action Needed |
|--------|--------|---------------|
| SKILL.md format | ✅ Consistent | Add optional fields, schema validation |
| CLAUDE.md format | ⚠️ Minor issues | Fix plugin count, standardize navigation |
| JSON schemas | ✅ Good | Integrate into CI |
| YAML usage | ✅ Appropriate | Document guidelines |
| Cross-references | ⚠️ Inconsistent | Add validation |

---

## Appendix: File Counts

```
SKILL.md files:      164
CLAUDE.md files:      26
README.md files:      31
docs/*.md files:     88
JSON files:           71
YAML files:           27
---
Total markdown:     ~830
Total config:        ~98
```
