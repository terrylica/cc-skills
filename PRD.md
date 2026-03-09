# PRD.md - Nested CLAUDE.md Link Farm Migration

## PROSTAT

**Goal**: Migrate/rectify/prune/update/grow nested Project Memory CLAUDE.md files to support the Link Farm + Hub-and-Spoke with Progressive Disclosure pattern, enabling new Claude Code CLI AI coding sessions to autonomously discover project structure.

---

## 9 Investigative Perspectives (Tasks)

### Task 1: Root CLAUDE.md Audit & Link Validation
- **Purpose**: Audit the root CLAUDE.md for completeness and validate all outgoing links
- **Dependencies**: None (parallel start)
- **Scope**: Verify root CLAUDE.md has proper hub-and-spoke links to docs/, plugins/, and child directories

### Task 2: docs/ Directory CLAUDE.md Analysis
- **Purpose**: Analyze docs/CLAUDE.md and its children for Link Farm coverage
- **Dependencies**: None (parallel start)
- **Scope**: Check docs/adr/, docs/design/, docs/troubleshooting/ for nested CLAUDE.md files and proper linking

### Task 3: plugins/ Directory CLAUDE.md Analysis
- **Purpose**: Analyze plugins/CLAUDE.md for proper structure and verify all 25 plugin CLAUDE.md files
- **Dependencies**: Task 1 (sequential - needs root to link properly)
- **Scope**: Verify plugins/CLAUDE.md lists all plugins, check each plugin has CLAUDE.md with proper Hub+Sibling links

### Task 4: docs/adr/ Nested CLAUDE.md Investigation
- **Purpose**: Determine if docs/adr/ subdirectories need individual CLAUDE.md files
- **Dependencies**: Task 2 (sequential - needs docs/CLAUDE.md analysis first)
- **Scope**: Investigate each ADR subdirectory, decide which need CLAUDE.md for progressive disclosure

### Task 5: docs/design/ Nested CLAUDE.md Investigation
- **Purpose**: Determine if docs/design/ subdirectories need individual CLAUDE.md files
- **Dependencies**: Task 2 (sequential - needs docs/CLAUDE.md analysis first)
- **Scope**: Investigate each design subdirectory, decide which need CLAUDE.md

### Task 6: docs/troubleshooting/ Nested CLAUDE.md Investigation
- **Purpose**: Analyze docs/troubleshooting/ for nested CLAUDE.md requirements
- **Dependencies**: Task 2 (sequential - needs docs/CLAUDE.md analysis first)
- **Scope**: Review troubleshooting guides and determine structure

### Task 7: Plugin CLAUDE.md Standardization
- **Purpose**: Ensure all 25 plugin CLAUDE.md files follow the Hub+Sibling+Child pattern
- **Dependencies**: Task 3 (sequential - needs plugin analysis first)
- **Scope**: Audit each plugin's CLAUDE.md for proper navigation links, fix any missing/broken links

### Task 8: Cross-Link Validation & Broken Link Detection
- **Purpose**: Validate all inter-CLAUDE.md links across the project
- **Dependencies**: None (parallel start - can run independently)
- **Scope**: Run link validation, identify broken links, report findings to peers

### Task 9: Progressive Disclosure Gap Analysis
- **Purpose**: Identify missing deep-link paths and create missing CLAUDE.md files
- **Dependencies**: Tasks 4, 5, 6, 7, 8 (sequential - needs all prior findings)
- **Scope**: Based on all findings, create new CLAUDE.md files where needed, document gap findings

---

## Execution Strategy

1. **Parallel Cluster**: Tasks 1, 2, 8 can run in parallel (independent)
2. **Sequential Chain**: Task 3 → Task 7; Task 2 → Tasks 4, 5, 6
3. **Final Synthesis**: Task 9 depends on all prior tasks

## Success Criteria

- All root-level links validated
- All 25 plugin CLAUDE.md files verified with proper Hub+Sibling navigation
- Documented decision on which nested directories need CLAUDE.md files
- Created missing CLAUDE.md files where beneficial for autonomous discovery
- Link validation passes with no broken references

---

## Dynamic Task Creation (DCTG) Instructions

Each task worker must:
1. Start by investigating one angle of its assigned perspective
2. Based on findings, call `pi_messenger({ action: "task.create" })` to spawn follow-up sub-tasks
3. Each sub-task emerges naturally from discoveries — NOT pre-defined
4. Workers use bash for empirical validation when needed
5. Workers create isolated scaffolding directories under `/tmp/crew-<perspective>/` for any code experiments

**After completing investigation, broadcast key findings to all peers.**
