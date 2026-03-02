# Task for crew-worker

# Task Assignment

**Task ID:** task-5
**Task Title:** Task 5: Search & Discovery Architecture
**PRD:** /Users/terryli/eon/cc-skills/PRD.md


## Your Mission

Implement this task following the crew-worker protocol:
1. Join the mesh
2. Read task spec to understand requirements
3. Start task and reserve files
4. Implement the feature
5. Commit your changes
6. Release reservations and mark complete

## Concurrent Tasks

These tasks are being worked on by other workers in this wave. Discover their agent names after joining the mesh via `pi_messenger({ action: "list" })`.

- task-6: Task 6: Content Deduplication Analysis
- task-7: Task 7: Metadata & Linking Framework
- task-8: Task 8: Accessibility & Findability Review
- task-9: Task 9: Governance & Maintenance Model

## Recent Activity

12:29 OakYak released .claude-plugin/
12:29 OakYak released CLAUDE.md
12:30 GoldUnion released docs/
12:30 GoldUnion completed task-1 — Created docs/standards-compliance-matrix.md - comprehensive audit of all 23 plugin CLAUDE.md files against documented standards. Found key issues: root CLAUDE.md says 20 plugins (should be 23), plugins/CLAUDE.md lists 21 (missing kokoro-tts and gitnexus-tools), header format inconsistencies, and incomplete tables in several plugins.
12:30 IronPhoenix started task-3 — Task 3: Toolchain & Automation Landscape
12:30 OakYak completed task-2 — Created docs/format-inventory.md with comprehensive format analysis: cataloged 830+ markdown files (164 SKILL.md, 26 CLAUDE.md, 31 README.md, 88 docs/*.md), reviewed JSON schemas (marketplace.schema.json, hooks.schema.json), analyzed YAML usage, and provided recommendations for unified format strategy.
12:30 PureMoon started task-4 — Task 4: Version Consistency Strategy
12:30 OakYak ✦ Completed task-2: Cross-Platform Format Analysis — created docs/format-inventory.md with format inventory, frontmatter analysis, JSON schema review, and unified strategy recommendations

## Task Specification

# Task 5: Search & Discovery Architecture

Investigate how users find documentation across the ecosystem. Analyze current search mechanisms, indexing and cross-referencing现状, and propose a unified search/discovery approach.

Approach:
- Review current navigation in CLAUDE.md hub-and-spoke model
- Check how skills are discovered (skill name in frontmatter → slash commands)
- Analyze link density: which docs link to which
- Identify discoverability gaps

Deliverable: Discovery architecture with search enhancement recommendations


## Plan Context

Now I have a comprehensive understanding of the cc-skills project. Let me compile the task breakdown.

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
2. **Phase 2 (Parallel)**: Tasks 7, 8, 9 c

[Spec truncated - read full spec from .pi/messenger/crew/plan.md]
## Coordination

**Message budget: 10 messages this session.** The system enforces this — sends are rejected after the limit.

**Broadcasts go to the team feed — only the user sees them live.** Other workers see your broadcasts in their initial context only. Use DMs for time-sensitive peer coordination.

### Announce yourself
After joining the mesh and starting your task, announce what you're working on:

```typescript
pi_messenger({ action: "broadcast", message: "Starting <task-id> (<title>) — will create <files>" })
```

### Coordinate with peers
If a concurrent task involves files or interfaces related to yours, send a brief DM. Only message when there's a concrete coordination need — shared files, interfaces, or blocking questions.

```typescript
pi_messenger({ action: "send", to: "<peer-name>", message: "I'm exporting FormatOptions from types.ts — will you need it?" })
```

### Responding to messages
If a peer asks you a direct question, reply briefly. Ignore messages that don't require a response. Do NOT start casual conversations.

### On completion
Announce what you built:

```typescript
pi_messenger({ action: "broadcast", message: "Completed <task-id>: <file> exports <symbols>" })
```

### Reservations
Before editing files, check if another worker has reserved them via `pi_messenger({ action: "list" })`. If a file you need is reserved, message the owner to coordinate. Do NOT edit reserved files without coordinating first.

### Questions about dependencies
If your task depends on a completed task and something about its implementation is unclear, read the code and the task's progress log at `.pi/messenger/crew/tasks/<task-id>.progress.md`. Dependency authors are from previous waves and are no longer in the mesh.

### Claim next task
After completing your assigned task, check if there are ready tasks you can pick up:

```typescript
pi_messenger({ action: "task.ready" })
```

If a task is ready, claim and implement it. If `task.start` fails (another worker claimed it first), check for other ready tasks. Only claim if your current task completed cleanly and quickly.

