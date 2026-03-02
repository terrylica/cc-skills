# PRD: Align All Docs

## Problem Statement

**PROSTAT**: align all docs

The documentation across the cc-skills ecosystem (20 plugins, multiple docs directories, various skill files) is fragmented, inconsistent, and lacks a unified strategy. We need to investigate and plan a comprehensive documentation alignment initiative.

## Background

The cc-skills project contains:
- 20 marketplace plugins with individual CLAUDE.md files
- Multiple documentation locations (docs/, plugins/*/CLAUDE.md, root README.md)
- Various documentation formats (Markdown, JSON, YAML)
- Multiple documentation tools and generation systems
- Inconsistent linking conventions and navigation patterns

## Success Criteria

1. Unified documentation strategy across all plugins and docs
2. Consistent format, structure, and linking conventions
3. Clear ownership and maintenance workflows
4. Automated validation and enforcement
5. Improved discoverability and navigation

---

## 9 Investigative Perspectives (Tasks)

### Task 1: Documentation Standards Audit
**Investigate**: What documentation standards currently exist? What's the current state of docs across all 20 plugins?
- Audit existing CLAUDE.md files for structure/format consistency
- Identify gaps, redundancies, and inconsistencies
- Document current conventions in use

### Task 2: Cross-Platform Format Analysis
**Investigate**: What documentation formats are used where?
- Map all doc types: README.md, CLAUDE.md, SKILL.md, docs/*.md, JSON schemas
- Identify format inconsistencies and compatibility issues
- Recommend unified format strategy

### Task 3: Toolchain & Automation Landscape
**Investigate**: What tools generate or manage documentation?
- Catalog doc-related tools: validation scripts, generators, linters
- Assess automation maturity and gaps
- Identify opportunities for consolidation

### Task 4: Version Consistency Strategy
**Investigate**: How should docs track with code versions?
- Current versioning patterns in docs vs code
- Best practices for doc versioning
- Proposed strategy for cc-skills

### Task 5: Search & Discovery Architecture
**Investigate**: How do users find documentation?
- Current search mechanisms across the ecosystem
- Indexing and cross-referencing现状
- Proposed unified search/discovery approach

### Task 6: Content Deduplication Analysis
**Investigate**: What content is duplicated or orphaned?
- Identify repeated patterns, copy-pasted content
- Find orphaned docs with no links
- Map content ownership and freshness

### Task 7: Metadata & Linking Framework
**Investigate**: How should docs link to each other?
- Current cross-linking state
- Metadata needs (tags, categories, owners)
- Proposed linking + metadata strategy

### Task 8: Accessibility & Findability Review
**Investigate**: Are docs accessible and findable?
- Check for broken links, missing alt text
- Navigation usability assessment
- External search visibility analysis

### Task 9: Governance & Maintenance Model
**Investigate**: Who owns what docs? How are they maintained?
- Current ownership patterns
- Review/update workflows
- Proposed governance structure

---

## Task Dependencies

**Parallel (no dependencies)** - These can run simultaneously:
- Task 1: Documentation Standards Audit
- Task 2: Cross-Platform Format Analysis
- Task 3: Toolchain & Automation Landscape
- Task 4: Version Consistency Strategy
- Task 5: Search & Discovery Architecture
- Task 6: Content Deduplication Analysis

**Sequential (need earlier outputs)**:
- Task 7: Metadata & Linking Framework (needs outputs from 1, 2, 5, 6)
- Task 8: Accessibility & Findability Review (needs outputs from 1, 5, 6)
- Task 9: Governance & Maintenance Model (needs outputs from 1, 3, 6)

---

## Dynamic Task Creation (DCTG) Instructions

Each task worker MUST use Dynamic Task Creation:
1. Start by investigating ONE angle of your assigned perspective
2. Based on findings, call `pi_messenger({ action: "task.create", ... })` to spawn follow-up sub-tasks
3. Each sub-task emerges naturally from discoveries — NOT pre-defined
4. Use `bash` for empirical validation (ls, cat, grep) when needed
5. Create isolated scaffolding directories under `/tmp/crew-<perspective>/` for any code experiments
6. After completing your investigation, broadcast your key findings to all peers using `pi_messenger({ action: "send", to: "all", message: "..." })`

---

## Acceptance Criteria

- [ ] All 9 tasks completed with actionable findings
- [ ] Each task spawns at least one dynamic sub-task based on discoveries
- [ ] Cross-cutting findings shared with relevant peer tasks
- [ ] Final synthesis produces unified documentation alignment plan
