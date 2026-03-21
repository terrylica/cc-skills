# Search & Discovery Architecture

**Task**: Task 5: Search & Discovery Architecture  
**Author**: NiceXenon  
**Date**: 2026-03-02

## Executive Summary

This document analyzes the current search and discovery mechanisms in the cc-skills ecosystem and provides recommendations for a unified discovery architecture. The ecosystem contains **23 plugins** with **164 SKILL.md files**, yet lacks comprehensive cross-referencing and search capabilities.

---

## Current Discovery Mechanisms

### 1. Hub-and-Spoke Navigation Model

The primary navigation follows a hierarchical structure:

```
Root CLAUDE.md (Hub)
    ├── plugins/CLAUDE.md (Spoke 1)
    │       └── {plugin}/CLAUDE.md (Deep)
    └── docs/CLAUDE.md (Spoke 2)
            └── Various topic docs
```

**Link Density Analysis:**
- Root CLAUDE.md: 14 outbound links
- plugins/CLAUDE.md: 27 outbound links (21 plugin CLAUDE.md files)
- docs/CLAUDE.md: 8 outbound links to sub-docs

**Finding**: The hub-and-spoke model works well for initial orientation but lacks depth in cross-referencing between spokes.

### 2. Skill Discovery (Slash Commands)

Skills are discovered via:

1. **Frontmatter metadata** in each SKILL.md:
   ```yaml
   ---
   name: adr-graph-easy-architect
   description: ASCII architecture diagrams...
   allowed-tools: Bash, Read, Write, Edit
   ---
   ```

2. **Slash command invocation**: Users type `/<skill-name>` to invoke

3. **Trigger phrases** (stored in description): e.g., "TRIGGERS - ADR diagram, architecture diagram"

**Statistics:**
- 164 SKILL.md files across 23 plugins
- Skills organized in `plugins/{plugin}/skills/{skill-name}/SKILL.md` structure

**Finding**: No unified skill index. Users must know the plugin name or browse plugin directories.

### 3. Plugin Registry (marketplace.json)

The Single Source of Truth (SSoT) is `.claude-plugin/marketplace.json`:

- Contains 23 plugin entries with:
  - `name`, `description`, `version`
  - `keywords` array (searchable)
  - `category` (enumeration)
  - `author`, `source`, `hooks`

**Keywords for discovery:**
- plugin-dev: ["plugin", "skill", "validation", "silent-failures", "meta-skill"...]
- itp: ["adr", "workflow", "implementation", "release", "semantic-release"...]
- gh-tools: ["github", "pull-request", "gfm", "link-validation"...]

**Finding**: Keywords provide some discoverability but are not exposed to end users in the Claude Code interface.

### 4. Link Validation (Lychee)

The `lychee.toml` configuration provides broken link detection:
- Caches results for 7 days
- Excludes external URLs with rate limits
- Checks markdown files across the ecosystem

**Finding**: Validates link integrity but doesn't provide search functionality.

### 5. Validation Script (validate-plugins.mjs)

Comprehensive validation that checks:
- Plugin registration in marketplace.json
- Required fields in JSON entries
- Source/hook paths exist
- Skill frontmatter (name + description)
- Inter-plugin dependencies

**Finding**: Enforces structure but doesn't enhance user discovery.

---

## Discoverability Gaps

### Gap 1: No Unified Skill Index
- **Problem**: 164 skills exist but no single place lists them all
- **Impact**: Users can't discover skills across plugins
- **Example**: A user looking for "link validation" doesn't know it exists in `link-tools` plugin

### Gap 2: No Full-Text Search
- **Problem**: Cannot search skill descriptions or content
- **Impact**: Users must manually browse or guess
- **Example**: Searching for "markdown" returns no results across skills

### Gap 3: Weak Cross-Spoke Links
- **Problem**: docs/CLAUDE.md and plugins/CLAUDE.md don't fully link to each other
- **Impact**: Documentation is siloed
- **Finding**: Root CLAUDE.md links to both spokes, but spokes rarely link to each other

### Gap 4: Category/Tag Browsing Absent
- **Problem**: marketplace.json has `category` and `keywords` but no UI exposure
- **Impact**: No way to browse by category (devops, productivity, trading...)
- **Example**: Want all "productivity" plugins → must check marketplace.json manually

### Gap 5: No Skill-to-Skill References
- **Problem**: Skills don't reference related skills in other plugins
- **Impact**: No way to discover "similar" skills
- **Example**: `itp:release` and `mise:release` are related but not linked

### Gap 6: Plugin Dependencies Not Exposed
- **Problem**: `tts-tg-sync` requires `kokoro-tts` but this isn't visible to users
- **Impact**: Users don't understand plugin relationships

---

## Recommendations

### Recommendation 1: Create Unified Skill Index (Priority: High)

**File**: `docs/discovery/skill-index.md`

```markdown
# Skill Index

Browse skills by category or search by keyword.

## All Skills (164)

| Skill | Plugin | Description | Triggers |
|-------|--------|-------------|----------|
| adr-graph-easy-architect | itp | ASCII architecture diagrams | ADR diagram, architecture |
| semantic-release | itp | Automated releases via semantic-release | release, version, publish |
...
```

**Benefit**: Single navigation point for all skills.

### Recommendation 2: Add Cross-Reference Links (Priority: High)

Enhance CLAUDE.md files with bidirectional links:

- **plugins/CLAUDE.md** → Add link to `docs/CLAUDE.md`
- **docs/CLAUDE.md** → Add link to `plugins/CLAUDE.md`
- Each plugin CLAUDE.md → Link to related skills in other plugins

**Example** (plugins/itp/CLAUDE.md):
```markdown
## Related Skills

- [semantic-release](../mise/skills/release/SKILL.md) - Mise release tasks
- [link-validation](../link-tools/skills/validate/SKILL.md) - Lychee integration
```

### Recommendation 3: Generate Skill Metadata Index (Priority: Medium)

Create a machine-readable index for potential tooling:

**File**: `.claude-plugin/skill-index.json`

```json
{
  "skills": [
    {
      "name": "semantic-release",
      "plugin": "itp",
      "description": "Automated semantic versioning and releases",
      "triggers": ["release", "version", "publish", "changelog"],
      "keywords": ["semantic-release", "changelog", "versioning"],
      "path": "plugins/itp/skills/release/SKILL.md"
    }
  ]
}
```

**Usage**: Enable future search tools, slash command autocomplete.

### Recommendation 4: Add Category Browsing to Root CLAUDE.md (Priority: Medium)

Enhance root CLAUDE.md with category-based plugin listing:

```markdown
## Plugins by Category

### Development (7)
- plugin-dev, gh-tools, gitnexus-tools, rust-tools, devops-tools...

### Productivity (5)
- itp, gmail-commander, calcom-commander, mise, productivity-tools

### DevOps (5)
- devops-tools, asciinema-tools, git-town-workflow, kokoro-tts, tts-tg-sync

### Trading (2)
- mql5, quant-research
```

### Recommendation 5: Document Plugin Dependencies (Priority: Medium)

Add dependency visualization to root CLAUDE.md:

```markdown
## Plugin Dependencies

```
tts-tg-sync ──requires──► kokoro-tts
git-town-workflow ──requires──► git-town
```
```

### Recommendation 6: Enhance Skill Triggers (Priority: Low)

Standardize trigger phrase format across all SKILL.md files:

```yaml
---
name: semantic-release
description: Automated semantic versioning and releases
triggers:
  - release
  - version
  - publish
  - changelog
  - major/minor/patch
allowed-tools: Bash, Git, npm
---
```

**Benefit**: Enables future NLP-based skill matching.

---

## Implementation Priority

| Priority | Recommendation | Effort | Impact |
|----------|---------------|--------|--------|
| 1 | Unified Skill Index | Low | High |
| 2 | Cross-Reference Links | Medium | High |
| 3 | Skill Metadata Index | Medium | Medium |
| 4 | Category Browsing | Low | Medium |
| 5 | Dependency Documentation | Low | Low |
| 6 | Enhanced Triggers | High | Low |

---

## Related Tasks

- **Task 1**: Documentation Standards Audit (completed) - standards-compliance-matrix.md
- **Task 2**: Format Inventory (completed) - format-inventory.md
- **Task 4**: Version Consistency Strategy - in progress
- **Task 6**: Content Deduplication Analysis - parallel task
- **Task 7**: Metadata & Linking Framework - parallel task
- **Task 8**: Accessibility & Findability Review - parallel task

---

## Conclusion

The cc-skills ecosystem has a solid hub-and-spoke navigation model but lacks unified discovery mechanisms for its 164 skills. The primary gaps are:

1. No central skill index
2. No full-text or keyword search
3. Weak cross-references between spokes
4. Hidden category/keyword metadata

Implementing Recommendations 1-4 would significantly improve discoverability with moderate effort.
