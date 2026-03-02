# Planning Outline

## 1. PRD Understanding Summary
The PRD calls for a comprehensive documentation alignment initiative across the cc-skills ecosystem. Key aspects:

- **23 plugins** (not 20 as mentioned in root CLAUDE.md) with individual CLAUDE.md files
- **164 SKILL.md files** across all plugins
- **Multiple documentation locations**: root, docs/, plugins/*/, skill references
- **Various formats**: Markdown, JSON (marketplace.json, hooks.json, schemas), YAML (.releaserc.yml, lychee.toml)
- **Documentation tools**: validate-plugins.mjs (comprehensive), lychee (link checking), custom path linting
- **Known issues**: Root CLAUDE.md says 20 plugins but there are 23; some plugin entries in README may be outdated

The 9 investigative tasks are well-defined in the PRD and represent parallel investigative work that feeds into 3 synthesis tasks.

## 2. Relevant Code/Docs/Resources Reviewed
| Resource | Path | Purpose |
|----------|------|---------|
| Root CLAUDE.md | `/CLAUDE.md` | Hub documentation with navigation |
| Plugin CLAUDE.md | `plugins/CLAUDE.md` | Plugin development guide (21 plugins listed) |
| Docs CLAUDE.md | `docs/CLAUDE.md` | Documentation standards |
| Marketplace.json | `.claude-plugin/marketplace.json` | SSoT for 23 plugins |
| validate-plugins.mjs | `scripts/validate-plugins.mjs` | Comprehensive plugin validation |
| lychee.toml | `lychee.toml` | Link checking config |
| ADR directory | `docs/adr/` | 40+ ADRs in MADR format |
| Design specs | `docs/design/` | Implementation specs (1:1 with ADRs) |
| Sample plugin CLAUDE.md | `plugins/itp/CLAUDE.md`, `plugins/devops-tools/CLAUDE.md` | Different structure/completeness |

## 3. Sequential Implementation Steps
Based on the PRD dependencies:

1. **Phase 1 (Parallel)**: Run all 9 investigative tasks simultaneously - each worker investigates their assigned perspective independently
2. **Phase 2 (Parallel)**: Tasks 7, 8, 9 can only start after receiving outputs from earlier tasks
3. **Phase 3 (Synthesis)**: Aggregate findings into unified documentation alignment plan with specific recommendations

## 4. Parallelized Task Graph
### Task Graph Visualization

```
PARALLEL WAVE 1 (Investigative):
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│ Task 1  │ │ Task 2  │ │ Task 3  │ │ Task 4  │ │ Task 5  │ │ Task 6  │
│Doc Audit│ │Format   │ │Toolchain│ │Version  │ │Search   │ │Dedupe   │
│         │ │Analysis │ │         │ │Strategy │ │         │ │         │
└────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
     │           │           │           │           │           │
     └───────────┴───────────┼───────────┴───────────┘           │
                             │                                   │
PARALLEL WAVE 2 (Synthesis):│                                   │
┌────────────────────────────┴───────────────────────────────┐   │
│                     TASK 7                                  │
│            Metadata & Linking Framework                     │
│    (needs outputs from 1, 2, 5, 6)                        │
└────────────────────────────┬───────────────────────────────┘   │
                           │                                   │
┌───────────────────────────┼───────────────────────────────┐   │
│                       TASK 8                               │   │
│          Accessibility & Findability Review               │   │
│            (needs outputs from 1, 5, 6)                   │   │
└───────────────────────────┬───────────────────────────────┘   │
                           │                                   │
┌───────────────────────────┼───────────────────────────────┐   │
│                       TASK 9                               │   │
│        Governance & Maintenance Model                      │   │
│           (needs outputs from 1, 3, 6)                   │   │
└───────────────────────────────────────────────────────────┘   
```

---

## Gap Analysis

### Missing Requirements
- **Inconsistent plugin count**: Root CLAUDE.md says 20 plugins, plugins/CLAUDE.md says 21, marketplace.json has 23
- **No unified format strategy**: Mixed formats across plugins (some have rich tables, others minimal)
- **Documentation ownership unclear**: No explicit owner field in plugin CLAUDE.md files
- **Version sync gap**: Version in CLAUDE.md files is manual, not automated

### Edge Cases
- **Disconnected plugins**: Some plugins may have no cross-references to other docs
- **Orphaned content**: Files in docs/ that are never linked from anywhere
- **Stale links**: Links to deprecated plugins or removed files

### Security Considerations
- **Sensitive data in docs**: 1Password references in devops-tools CLAUDE.md should be reviewed
- **Token exposure**: Any accidental credential leaks in documentation

### Testing Requirements
- **Link validation**: Verify all markdown links work (lychee already runs)
- **Cross-reference validation**: Ensure bidirectional links between related docs
- **Format consistency**: Automated checks for CLAUDE.md structure uniformity

---

## Tasks

### Task 1: Documentation Standards Audit

Investigate what documentation standards currently exist and document the current state across all 23 plugins. Audit existing CLAUDE.md files for structure/format consistency, identify gaps, redundancies, and inconsistencies, and document current conventions in use.

**Approach**:
- Parse all 23 plugin CLAUDE.md files and extract: section headers, table structures, link patterns, frontmatter usage
- Compare against the documented standards in docs/CLAUDE.md
- Identify which plugins follow vs deviate from standards

**Deliverable**: Standards compliance matrix with per-plugin gap analysis

Dependencies: none

### Task 2: Cross-Platform Format Analysis

Investigate what documentation formats are used where across the ecosystem. Map all doc types: README.md, CLAUDE.md, SKILL.md, docs/*.md, JSON schemas, and identify format inconsistencies and compatibility issues.

**Approach**:
- Catalog all markdown files by location and type
- Analyze frontmatter consistency across SKILL.md files (validate-plugins.mjs already checks for name/description)
- Review JSON schema usage (marketplace.schema.json, hooks.schema.json)
- Identify where YAML is used vs JSON

**Deliverable**: Format inventory with recommended unified strategy

Dependencies: none

### Task 3: Toolchain & Automation Landscape

Investigate what tools generate or manage documentation. Catalog doc-related tools: validation scripts, generators, linters, and assess automation maturity and gaps.

**Approach**:
- Map all scripts in scripts/ directory related to docs
- Analyze validate-plugins.mjs capabilities and limitations
- Review lychee link checking setup and results
- Identify manual vs automated processes

**Deliverable**: Tool inventory with maturity assessment and consolidation opportunities

Dependencies: none

### Task 4: Version Consistency Strategy

Investigate how documentation should track with code versions. Analyze current versioning patterns in docs vs code, research best practices for doc versioning, and propose a unified strategy.

**Approach**:
- Review where versions appear: marketplace.json, package.json, plugin.json, individual CLAUDE.md files
- Check if versions are synced automatically
- Research doc versioning approaches (keep it simple vs semantic versioning in frontmatter)

**Deliverable**: Version sync strategy with implementation recommendations

Dependencies: none

### Task 5: Search & Discovery Architecture

Investigate how users find documentation across the ecosystem. Analyze current search mechanisms, indexing and cross-referencing现状, and propose a unified search/discovery approach.

**Approach**:
- Review current navigation in CLAUDE.md hub-and-spoke model
- Check how skills are discovered (skill name in frontmatter → slash commands)
- Analyze link density: which docs link to which
- Identify discoverability gaps

**Deliverable**: Discovery architecture with search enhancement recommendations

Dependencies: none

### Task 6: Content Deduplication Analysis

Investigate what content is duplicated or orphaned. Identify repeated patterns, copy-pasted content, find orphaned docs with no links, and map content ownership and freshness.

**Approach**:
- Find common text patterns across CLAUDE.md files (e.g., "Hub:" links)
- Identify docs that are never linked from anywhere
- Check for duplicate information (e.g., same instructions in multiple plugins)
- Map last-modified dates across documentation

**Deliverable**: Deduplication plan with orphan identification

Dependencies: none

### Task 7: Metadata & Linking Framework

Synthesize findings from Tasks 1, 2, 5, and 6 to recommend how docs should link to each other. Define cross-linking state, metadata needs (tags, categories, owners), and propose a linking + metadata strategy.

**Deliverable**: Metadata schema and linking conventions

Dependencies: Task 1, Task 2, Task 5, Task 6

### Task 8: Accessibility & Findability Review

Synthesize findings from Tasks 1, 5, and 6 to assess docs accessibility and findability. Check for broken links, missing alt text, navigation usability, and external search visibility.

**Deliverable**: Accessibility improvements with implementation plan

Dependencies: Task 1, Task 5, Task 6

### Task 9: Governance & Maintenance Model

Synthesize findings from Tasks 1, 3, and 6 to propose governance structure. Document current ownership patterns, review/update workflows, and propose governance structure.

**Deliverable**: Governance model with ownership assignments and maintenance workflows

Dependencies: Task 1, Task 3, Task 6

---

```tasks-json
[
  {
    "title": "Task 1: Documentation Standards Audit",
    "description": "Investigate what documentation standards currently exist and document the current state across all 23 plugins. Audit existing CLAUDE.md files for structure/format consistency, identify gaps, redundancies, and inconsistencies, and document current conventions in use.\n\nApproach:\n- Parse all 23 plugin CLAUDE.md files and extract: section headers, table structures, link patterns, frontmatter usage\n- Compare against the documented standards in docs/CLAUDE.md\n- Identify which plugins follow vs deviate from standards\n\nDeliverable: Standards compliance matrix with per-plugin gap analysis",
    "dependsOn": []
  },
  {
    "title": "Task 2: Cross-Platform Format Analysis",
    "description": "Investigate what documentation formats are used where across the ecosystem. Map all doc types: README.md, CLAUDE.md, SKILL.md, docs/*.md, JSON schemas, and identify format inconsistencies and compatibility issues.\n\nApproach:\n- Catalog all markdown files by location and type\n- Analyze frontmatter consistency across SKILL.md files\n- Review JSON schema usage (marketplace.schema.json, hooks.schema.json)\n- Identify where YAML is used vs JSON\n\nDeliverable: Format inventory with recommended unified strategy",
    "dependsOn": []
  },
  {
    "title": "Task 3: Toolchain & Automation Landscape",
    "description": "Investigate what tools generate or manage documentation. Catalog doc-related tools: validation scripts, generators, linters, and assess automation maturity and gaps.\n\nApproach:\n- Map all scripts in scripts/ directory related to docs\n- Analyze validate-plugins.mjs capabilities and limitations\n- Review lychee link checking setup and results\n- Identify manual vs automated processes\n\nDeliverable: Tool inventory with maturity assessment and consolidation opportunities",
    "dependsOn": []
  },
  {
    "title": "Task 4: Version Consistency Strategy",
    "description": "Investigate how documentation should track with code versions. Analyze current versioning patterns in docs vs code, research best practices for doc versioning, and propose a unified strategy.\n\nApproach:\n- Review where versions appear: marketplace.json, package.json, plugin.json, individual CLAUDE.md files\n- Check if versions are synced automatically\n- Research doc versioning approaches\n\nDeliverable: Version sync strategy with implementation recommendations",
    "dependsOn": []
  },
  {
    "title": "Task 5: Search & Discovery Architecture",
    "description": "Investigate how users find documentation across the ecosystem. Analyze current search mechanisms, indexing and cross-referencing现状, and propose a unified search/discovery approach.\n\nApproach:\n- Review current navigation in CLAUDE.md hub-and-spoke model\n- Check how skills are discovered (skill name in frontmatter → slash commands)\n- Analyze link density: which docs link to which\n- Identify discoverability gaps\n\nDeliverable: Discovery architecture with search enhancement recommendations",
    "dependsOn": []
  },
  {
    "title": "Task 6: Content Deduplication Analysis",
    "description": "Investigate what content is duplicated or orphaned. Identify repeated patterns, copy-pasted content, find orphaned docs with no links, and map content ownership and freshness.\n\nApproach:\n- Find common text patterns across CLAUDE.md files (e.g., \"Hub:\" links)\n- Identify docs that are never linked from anywhere\n- Check for duplicate information (e.g., same instructions in multiple plugins)\n- Map last-modified dates across documentation\n\nDeliverable: Deduplication plan with orphan identification",
    "dependsOn": []
  },
  {
    "title": "Task 7: Metadata & Linking Framework",
    "description": "Synthesize findings from Tasks 1, 2, 5, and 6 to recommend how docs should link to each other. Define cross-linking state, metadata needs (tags, categories, owners), and propose a linking + metadata strategy.\n\nDeliverable: Metadata schema and linking conventions",
    "dependsOn": ["Task 1: Documentation Standards Audit", "Task 2: Cross-Platform Format Analysis", "Task 5: Search & Discovery Architecture", "Task 6: Content Deduplication Analysis"]
  },
  {
    "title": "Task 8: Accessibility & Findability Review",
    "description": "Synthesize findings from Tasks 1, 5, and 6 to assess docs accessibility and findability. Check for broken links, missing alt text, navigation usability, and external search visibility.\n\nDeliverable: Accessibility improvements with implementation plan",
    "dependsOn": ["Task 1: Documentation Standards Audit", "Task 5: Search & Discovery Architecture", "Task 6: Content Deduplication Analysis"]
  },
  {
    "title": "Task 9: Governance & Maintenance Model",
    "description": "Synthesize findings from Tasks 1, 3, and 6 to propose governance structure. Document current ownership patterns, review/update workflows, and propose governance structure.\n\nDeliverable: Governance model with ownership assignments and maintenance workflows",
    "dependsOn": ["Task 1: Documentation Standards Audit", "Task 3: Toolchain & Automation Landscape", "Task 6: Content Deduplication Analysis"]
  }
]
```
