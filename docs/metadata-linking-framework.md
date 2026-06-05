# Metadata & Linking Framework

**Task:** Task 7: Metadata & Linking Framework  
**Author:** ZenKnight  
**Date:** 2026-03-02  
**Status:** Complete

## Executive Summary

This document synthesizes findings from Tasks 1, 2, and 5 to define a comprehensive metadata and linking framework for the cc-skills ecosystem. It addresses how documentation should link to each other, defines metadata needs (tags, categories, owners), and proposes a unified linking + metadata strategy.

**Key Deliverables:**

- Metadata schema for CLAUDE.md files (frontmatter)
- Standardized linking conventions
- Cross-reference strategy
- Ownership and category taxonomy

---

## 1. Current State Analysis

### 1.1 Cross-Linking State (from Task 1)

| Link Type               | Current Usage                      | Compliance              |
| ----------------------- | ---------------------------------- | ----------------------- |
| Hub links               | All plugin CLAUDE.md have Hub link | ✅ 100%                 |
| Sibling links           | Most have, kokoro-tts missing      | ⚠️ 96%                  |
| Relative links (`./`)   | Skills, references                 | ✅ Compliant            |
| Repo-root (`/docs/...`) | ADRs                               | ⚠️ Some inconsistencies |
| Full URL                | External resources                 | ✅ Compliant            |

**Issues Identified:**

- Some plugins use hardcoded paths instead of repo-root
- Bidirectional links between spokes (docs ↔ plugins) are weak
- No cross-plugin skill references

### 1.2 Metadata现状 (from Task 2)

| Doc Type         | Metadata         | Notes                                            |
| ---------------- | ---------------- | ------------------------------------------------ |
| SKILL.md         | YAML frontmatter | ✅ Structured (name, description, allowed-tools) |
| CLAUDE.md        | None             | ❌ No frontmatter                                |
| marketplace.json | JSON             | ✅ Rich (name, category, keywords, author)       |
| hooks.json       | JSON             | ✅ Structured                                    |

**SKILL.md Frontmatter Schema (Current):**

```yaml
---
name: <skill-name>
description: <description with TRIGGERS>
allowed-tools: <comma-separated tools>
---
```

**Optional Fields (~30% usage):**

- `argument-hint`: CLI argument hints
- `model`: Recommended model (haiku, sonnet, opus)
- `disable-model-invocation`: Manual-only skills

### 1.3 Discovery Gaps (from Task 5)

1. **No Unified Skill Index** - 164 skills, no single list
2. **Weak Cross-Spoke Links** - docs/CLAUDE.md and plugins/CLAUDE.md rarely link
3. **Category/Tag Browsing Absent** - `category` and `keywords` in marketplace.json not exposed
4. **Plugin Dependencies Not Exposed** - e.g., tts-tg-sync requires kokoro-tts

---

## 2. Metadata Schema

### 2.1 CLAUDE.md Frontmatter Standard

All CLAUDE.md files should include YAML frontmatter for better discoverability and tooling:

```yaml
---
title: <Plugin Name> Plugin
description: >-
  Brief description of what this plugin does (1-2 sentences).
  Should mention key capabilities and target users.
category: <development|productivity|devops|trading|utilities|enforcement|automation|documents>
owner:
  name: <Author Name>
  url: <GitHub URL>
keywords:
  - <keyword1>
  - <keyword2>
  - <keyword3>
depends-on:
  - <plugin-name> # Optional: list required plugins
links:
  hub: ../../CLAUDE.md
  sibling: ../<other-plugin>/CLAUDE.md
  skills: ./skills/
version: <plugin-version>
last-updated: <YYYY-MM-DD>
---
```

**Field Definitions:**

| Field           | Type   | Required | Description                                 |
| --------------- | ------ | -------- | ------------------------------------------- |
| `title`         | string | Yes      | Display name, e.g., "ITP Plugin"            |
| `description`   | string | Yes      | 1-2 sentence summary                        |
| `category`      | enum   | Yes      | Plugin category (see taxonomy below)        |
| `owner.name`    | string | Yes      | Author/maintainer name                      |
| `owner.url`     | string | No       | Author's GitHub URL                         |
| `keywords`      | array  | Yes      | Searchable terms (min 3)                    |
| `depends-on`    | array  | No       | Required plugins                            |
| `links.hub`     | string | Yes      | Path to root CLAUDE.md                      |
| `links.sibling` | string | No       | Path to related plugin                      |
| `links.skills`  | string | No       | Path to skills directory                    |
| `version`       | string | Yes      | Semantic version (matches marketplace.json) |
| `last-updated`  | date   | No       | Last significant update                     |

### 2.2 Category Taxonomy

Standardized categories derived from marketplace.json:

| Category       | Description                 | Plugins                                                                                   |
| -------------- | --------------------------- | ----------------------------------------------------------------------------------------- |
| `development`  | Code development tools      | plugin-dev, gh-tools, rust-tools                                                          |
| `productivity` | Workflow automation         | itp, mise, gmail-commander, calcom-commander, productivity-tools                          |
| `devops`       | Infrastructure & deployment | devops-tools, dotfiles-tools, asciinema-tools, git-town-workflow, kokoro-tts, tts-tg-sync |
| `trading`      | Financial trading           | mql5, quant-research                                                                      |
| `utilities`    | General utilities           | statusline-tools                                                                          |
| `enforcement`  | Workflow enforcement        | itp-hooks                                                                                 |
| `automation`   | Autonomous automation       | ru                                                                                        |
| `documents`    | Documentation tools         | doc-tools, quality-tools                                                                  |

### 2.3 SKILL.md Enhanced Frontmatter

Extend existing SKILL.md schema with cross-referencing fields:

```yaml
---
name: <skill-name>
description: <description>
allowed-tools: <comma-separated tools>

# Enhanced fields
argument-hint: "<cli-args>" # Existing optional
model: <haiku|sonnet|opus> # Existing optional
disable-model-invocation: <bool> # Existing optional

# New cross-reference fields
category: <category-name> # Inherit from plugin or custom
related-skills:
  - <other-skill-name> # Skills in same plugin
  - <plugin>/<skill-name> # Skills in other plugins
related-docs:
  - ../README.md # Plugin README
  - ../../docs/adr/<adr-num>.md # Related ADRs
tags:
  - <tag1>
  - <tag2>
owner: <skill-author> # Override plugin owner if different
---
```

### 2.4 docs/\*.md Frontmatter Standard

For documentation files in `docs/`:

```yaml
---
title: <Document Title>
description: <Brief description for search>
type: <adr|design|guide|reference|troubleshooting>
status: <draft|review|active|deprecated>
owner: <team-or-author>
tags:
  - <tag1>
  - <tag2>
links:
  related:
    - <path-to-related-doc>
  replaces:
    - <path-to-replaced-doc>
  see-also:
    - <path>
version: <document-version>
last-updated: <YYYY-MM-DD>
---
```

---

## 3. Linking Conventions

### 3.1 Link Type Standards

| Context                       | Link Type | Example                                              |
| ----------------------------- | --------- | ---------------------------------------------------- |
| Skill to Skill (same plugin)  | Relative  | `[skill-name](./skills/skill-name/SKILL.md)`         |
| Skill to Skill (cross-plugin) | Relative  | `[graph-easy](../../itp/skills/graph-easy/SKILL.md)` |
| Plugin CLAUDE to Hub          | Relative  | `[Root CLAUDE.md](../../CLAUDE.md)`                  |
| Plugin CLAUDE to Sibling      | Relative  | `[gh-tools](../gh-tools/CLAUDE.md)`                  |
| Plugin CLAUDE to docs         | Repo-root | `[ADR Guide](/docs/adr/)`                            |
| docs to docs (same dir)       | Relative  | `[related doc](./other-file.md)`                     |
| docs to ADRs                  | Repo-root | `/docs/adr/0012-example-adr.md`                      |
| External resources            | Full URL  | `[External Doc](https://example.com)`                |

### 3.2 Link Syntax Rules

1. **Use descriptive link text**: `[Release automation]` not `[here]` or `[link]`
2. **Prefer relative paths**: Always use relative links within the repo
3. **Use repo-root for cross-dir**: `/docs/...` for docs/ ↔ plugins/ linking
4. **External links need validation**: External URLs should be in lychee.toml exclusion or validated
5. **Anchor links for headings**: Use `[Section Name](#section-slug)` for same-page navigation

### 3.3 Bidirectional Linking Strategy

Each CLAUDE.md should link to related documents AND be linked from them:

```
Plugin CLAUDE.md
    ├── Links to: Hub (root CLAUDE.md)
    ├── Links to: Sibling plugins (when related)
    ├── Links to: Key skills
    └── Links to: Related ADRs/design docs

Should be linked from:
    ├── Root CLAUDE.md (plugin table)
    ├── plugins/CLAUDE.md (plugin list)
    └── Related plugin CLAUDE.md (if dependency)
```

### 3.4 Cross-Plugin Skill References

Add "Related Skills" section to plugin CLAUDE.md:

```markdown
## Related Skills

### Within This Plugin

| Skill                                      | Purpose      |
| ------------------------------------------ | ------------ |
| [skill-name](./skills/skill-name/SKILL.md) | What it does |

### In Other Plugins

| Skill                                                 | Plugin     | Purpose                |
| ----------------------------------------------------- | ---------- | ---------------------- |
| [validate](../../link-tools/skills/validate/SKILL.md) | link-tools | Lychee link validation |
```

---

## 4. Ownership Model

### 4.1 Ownership Hierarchy

```
Root CLAUDE.md
    └── Owner: Project maintainer (terrylica)
        └── docs/CLAUDE.md
            └── Owner: Docs team
                └── docs/adr/*.md
                    └── Owner: ADR author
                └── docs/design/*.md
                    └── Owner: Design author
        └── plugins/CLAUDE.md
            └── Owner: Project maintainer
                └── plugins/{plugin}/CLAUDE.md
                    └── Owner: Plugin author (from marketplace.json)
                        └── skills/*/SKILL.md
                            └── Owner: Skill author (or plugin author)
```

### 4.2 Ownership Metadata

| Doc Type             | Owner Source            | Override Allowed |
| -------------------- | ----------------------- | ---------------- |
| Root CLAUDE.md       | Project maintainer      | No               |
| docs/CLAUDE.md       | Docs owner              | No               |
| docs/\*.md           | Explicit in frontmatter | Yes              |
| plugins/\*/CLAUDE.md | marketplace.json author | Yes              |
| skills/\*/SKILL.md   | Inherit from plugin     | Yes              |

### 4.3 Ownership Responsibilities

| Role                   | Responsibilities                                   |
| ---------------------- | -------------------------------------------------- |
| **Project Maintainer** | Root docs, plugin registry, release process        |
| **Docs Owner**         | docs/ structure, ADR process, standards compliance |
| **Plugin Author**      | Plugin CLAUDE.md, skills, hooks.json               |
| **ADR Author**         | Specific ADR content, status updates               |
| **Design Author**      | Design spec content, implementation tracking       |

---

## 5. Implementation Recommendations

### 5.1 Priority 1: CLAUDE.md Frontmatter (High Impact)

Add frontmatter to all 26 CLAUDE.md files. Example transformation:

**Before:**

```markdown
# itp Plugin

> Implement-The-Plan workflow: ADR-driven 4-phase development...
```

**After:**

```yaml
---
title: ITP Plugin
description: >-
  Implement-The-Plan workflow with ADR-driven 4-phase development:
  preflight, implementation, formatting, and release automation.
category: productivity
owner:
  name: Terry Li
  url: https://github.com/terrylica
keywords:
  - adr
  - workflow
  - implementation
  - preflight
  - graph-easy
links:
  hub: ../../CLAUDE.md
  sibling: ../itp-hooks/CLAUDE.md
version: 11.73.0
---

# ITP Plugin

> Implement-The-Plan workflow: ADR-driven 4-phase development...
```

### 5.2 Priority 2: Cross-Reference Section (High Impact)

Add to each plugin CLAUDE.md:

```markdown
## Related Documentation

### Skills

| Skill                                      | Purpose         |
| ------------------------------------------ | --------------- |
| [adr-create](./skills/adr-create/SKILL.md) | Create new ADRs |

### Dependencies

- Requires: None
- Related: [itp-hooks](../itp-hooks/CLAUDE.md) for enforcement

### External Resources

- [ADR GitHub](https://github.com/terrylica/cc-skills/tree/main/docs/adr)
- [MADR Format](https://github.com/adr/madr)
```

### 5.3 Priority 3: Unified Skill Index (Medium Impact)

Create `docs/skills-index.md`:

```markdown
# Skill Index

Browse all 164 skills across 23 plugins.

## By Category

### Development

| Skill            | Plugin     | Description               |
| ---------------- | ---------- | ------------------------- |
| adr-create       | itp        | Create new ADRs           |
| validate-plugins | plugin-dev | Validate plugin structure |

### Productivity

| Skill            | Plugin | Description                      |
| ---------------- | ------ | -------------------------------- |
| go               | itp    | 4-phase ADR-driven workflow      |
| run-full-release | mise   | Run repo's mise release pipeline |

## By Keyword

Search: \_\_\_ (future: full-text search)

## Alphabetical

...
```

### 5.4 Priority 4: Metadata Validation (Medium Impact)

Add to `scripts/validate-plugins.mjs`:

1. Validate CLAUDE.md frontmatter (required fields)
2. Validate cross-reference links exist
3. Validate skill-to-skill references
4. Validate ownership metadata consistency

### 5.5 Priority 5: Orphan Detection (Low Impact)

Add to validation script:

- Report docs with no inbound links
- Report skills not linked from any CLAUDE.md
- Report plugins not listed in root CLAUDE.md

---

## 6. Schema Validation Rules

### 6.1 Required Frontmatter Fields

**CLAUDE.md:**

- `title`: non-empty string
- `description`: non-empty string, max 200 chars
- `category`: must match taxonomy
- `owner.name`: non-empty string
- `keywords`: array, min 3 items
- `version`: semver format

**SKILL.md:**

- `name`: kebab-case
- `description`: non-empty string
- `allowed-tools`: non-empty string

### 6.2 Link Validation Rules

| Rule                 | Severity | Description                      |
| -------------------- | -------- | -------------------------------- |
| Broken internal link | Error    | Target must exist                |
| Missing Hub link     | Warning  | CLAUDE.md should link to root    |
| Missing category     | Warning  | Metadata should include category |
| Orphan skill         | Info     | Skill not linked from CLAUDE.md  |
| Missing owner        | Warning  | Ownership metadata required      |

---

## 7. Migration Path

### Phase 1: Schema Definition (Complete)

- [x] Define metadata schema (this document)
- [x] Define linking conventions
- [x] Define ownership model

### Phase 2: Tooling (Future)

- [ ] Update validate-plugins.mjs
- [ ] Add frontmatter validator
- [ ] Add link validator

### Phase 3: Incremental Migration (Future)

- [ ] Add frontmatter to root CLAUDE.md
- [ ] Add frontmatter to docs/CLAUDE.md
- [ ] Add frontmatter to plugins/CLAUDE.md
- [ ] Add cross-reference sections
- [ ] Create skills index

### Phase 4: Validation Enforcement (Future)

- [ ] CI checks for frontmatter
- [ ] CI checks for link integrity
- [ ] Orphan detection reports

---

## 8. Related Tasks

| Task                                       | Status         | Relevance                                   |
| ------------------------------------------ | -------------- | ------------------------------------------- |
| Task 1: Documentation Standards Audit      | ✅ Complete    | Compliance matrix, gap analysis             |
| Task 2: Cross-Platform Format Analysis     | ✅ Complete    | Format inventory, frontmatter schema        |
| Task 5: Search & Discovery Architecture    | ✅ Complete    | Discovery gaps, skill index recommendations |
| Task 6: Content Deduplication Analysis     | 🔄 In Progress | Duplicate detection (assumed)               |
| Task 8: Accessibility & Findability Review | 🚫 Pending     | Broken link validation                      |
| Task 9: Governance & Maintenance Model     | 🚫 Pending     | Ownership enforcement                       |

---

## 9. Appendix: Quick Reference

### Link Patterns Cheatsheet

```markdown
<!-- Within same plugin -->

[Skill Name](./skills/skill-name/SKILL.md)

<!-- Cross-plugin -->

[Skill Name](../../other-plugin/skills/skill-name/SKILL.md)

<!-- To root docs -->

[ADR Guide](/docs/adr/)

<!-- To root CLAUDE -->

[Hub](../../CLAUDE.md)

<!-- External -->

[External](https://example.com)
```

### Category Values

```
development, productivity, devops, trading, utilities, enforcement, automation, documents
```

### Metadata Field Checklist

**CLAUDE.md:**

- [ ] title
- [ ] description
- [ ] category
- [ ] owner.name
- [ ] keywords (≥3)
- [ ] version
- [ ] links.hub

**SKILL.md:**

- [ ] name
- [ ] description
- [ ] allowed-tools
- [ ] (optional) related-skills
- [ ] (optional) tags

---

_Generated by Task 7: Metadata & Linking Framework_
