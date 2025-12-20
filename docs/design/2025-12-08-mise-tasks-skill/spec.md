---
adr: 2025-12-08-mise-tasks-skill
source: ~/.claude/plans/lucky-wondering-pizza.md
implementation-status: completed
phase: released
last-updated: 2025-12-20
---

# Design Spec: Create mise-tasks Skill + Enhance mise-configuration Cross-Reference

**ADR**: [Create mise-tasks Skill with Bidirectional Cross-References](/docs/adr/2025-12-08-mise-tasks-skill.md)

## Objective

Create comprehensive mise `[tasks]` skill with bidirectional cross-references to `mise-configuration`, enabling AI coding agents to discover opportunities for task orchestration during ITP workflows.

---

## Research Summary

### Source Analysis

| Source                        | Key Findings                                                                            |
| ----------------------------- | --------------------------------------------------------------------------------------- |
| **spicy-conjuring-planet.md** | Advanced patterns: `depends`, `depends_post`, `hide`, `usage` args, hidden helper tasks |
| **mise-configuration skill**  | **ZERO** [tasks] coverage - confirmed gap                                               |
| **Official mise docs**        | 10 complexity levels; `hide=true` is official (not `_` prefix)                          |
| **ITP integration**           | mise tasks **complement** but cannot **replace** /itp:go                                |

### Empirical Validation (mise 2025.12.0)

**ALL planned features VALIDATED** via help output, docs, and codebase inspection:

| Feature Category  | Features                                                                  | Status    |
| ----------------- | ------------------------------------------------------------------------- | --------- |
| **Core**          | `run`, `description`, `alias`, `depends`, `depends_post`, `hide`, `usage` | ALL WORK  |
| **File Tracking** | `sources`, `outputs`                                                      | VALIDATED |
| **Execution**     | `confirm`, `quiet`, `silent`, `raw`                                       | VALIDATED |
| **Advanced**      | `tools`, `mise watch`, `--jobs`                                           | VALIDATED |

**18 task properties confirmed** from official docs - full schema available.

---

## User Decisions

| Question                | Answer                                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------------------- |
| Skill structure         | **Both** - new mise-tasks + cross-reference in mise-configuration                              |
| Coverage depth          | **Comprehensive** (Levels 1-10) - reference-grade                                              |
| ITP integration         | mise-configuration **prescriptively invokes** mise-tasks when detecting workflow opportunities |
| Cross-reference pattern | **Bidirectional with AI prescriptive reminders**                                               |

---

## Implementation Tasks

### Part 1: Create `mise-tasks` Skill

**Location**: `plugins/itp/skills/mise-tasks/`

- [x] **Task 1.1**: Create `SKILL.md` (comprehensive, ~3000 words)
- [x] **Task 1.2**: Create `references/patterns.md` (real-world patterns)
- [x] **Task 1.3**: Create `references/arguments.md` (usage spec deep-dive)
- [x] **Task 1.4**: Create `references/advanced.md` (monorepo, watch)

#### SKILL.md Structure (10 levels)

1. **When to Use** - Triggers + prescriptive AI discovery reminder
2. **Quick Reference** - Task syntax, dependency types, commands
3. **Level 1-2: Basic Tasks** - `run`, `description`, `alias`, `dir`, `env`
4. **Level 3-4: Dependencies** - `depends`, `depends_post`, `wait_for`, chaining
5. **Level 5: Hidden Tasks** - `hide = true`, colon-prefix naming (`test:unit`)
6. **Level 6: Task Arguments** - `usage` spec (NEW method), deprecation warning
7. **Level 7: File Tracking** - `sources`, `outputs`, skip logic
8. **Level 8: Advanced Execution** - `confirm`, `quiet`, `silent`, `raw`, `tools`
9. **Level 9: Watch Mode** - `mise watch`, `--on-busy-update`
10. **Level 10: Monorepo** - `//` prefix, `...` wildcards, experimental
11. **Integration with [env]** - Tasks inherit env, `_.file` for credentials
12. **Anti-Patterns** - Don't replace /itp:go, don't use for TodoWrite
13. **Cross-Reference** - Link to mise-configuration

### Part 2: Enhance `mise-configuration` Skill

- [x] **Task 2.1**: Add "Task Orchestration Integration" section to SKILL.md
- [x] **Task 2.2**: Add `[tasks]` stub to patterns.md template

### Part 3: Update ITP Plugin

- [x] **Task 3.1**: Update ITP README badge (9 to 10 skills)

---

## Critical Files

| Priority | File                                                           | Action                 |
| -------- | -------------------------------------------------------------- | ---------------------- |
| 1        | `plugins/itp/skills/mise-tasks/SKILL.md`                       | CREATE                 |
| 2        | `plugins/itp/skills/mise-tasks/references/patterns.md`         | CREATE                 |
| 3        | `plugins/itp/skills/mise-tasks/references/arguments.md`        | CREATE                 |
| 4        | `plugins/itp/skills/mise-tasks/references/advanced.md`         | CREATE                 |
| 5        | `plugins/itp/skills/mise-configuration/SKILL.md`               | MODIFY                 |
| 6        | `plugins/itp/skills/mise-configuration/references/patterns.md` | MODIFY                 |
| 7        | `plugins/itp/README.md`                                        | MODIFY (badge 9 to 10) |

---

## Success Criteria

- [x] mise-tasks SKILL.md covers all 10 levels
- [x] Cross-references are bidirectional
- [x] Prescriptive AI reminders are clear
- [x] Anti-patterns documented (don't replace /itp:go)
- [x] Real-world patterns from spicy-conjuring-planet included
- [x] ITP README badge updated to 10 skills
- [x] All links are relative (marketplace format)
