**ADR**: [ITP Workflow Todo Insertion (Not Overwrite)](/docs/adr/2025-12-05-itp-todo-insertion-merge.md)

# Design Spec: ITP Workflow Todo Insertion (Not Overwrite)

**Status**: In Progress
**Target File**: `/Users/terryli/eon/cc-skills/plugins/itp/commands/itp.md`

## Problem Statement

The ITP workflow command currently instructs:

> "**MANDATORY FIRST ACTION — Copy this TodoWrite template EXACTLY**"

This **OVERWRITES** any existing todos from:

- The plan file (`~/.claude/plans/*.md`)
- Previous work sessions
- User's manually created todos

## Desired Behavior

1. **INSERT** ITP workflow todos alongside existing todos (not replace)
2. **Holistically consider** priorities between plan file and ITP workflow
3. **Ask user** via `AskUserQuestion` when priority conflicts exist

## Implementation Plan

### Step 1: Modify the Mandatory First Action Section (Lines 17-62)

**Current** (problematic):

```markdown
**MANDATORY FIRST ACTION — Copy this TodoWrite template EXACTLY:**

TodoWrite with todos:

- "Preflight: ..." | pending
  ...
```

**Proposed** (insertion-aware):

```markdown
**MANDATORY FIRST ACTION — Insert ITP Todos (Preserve Existing)**

1. **Read existing todos** via mental model of TodoRead
2. **Check plan file** at `~/.claude/plans/*.md` for existing priorities
3. **Merge strategy**:
   - Existing todos from plan file → keep at their priority
   - ITP workflow todos → insert as structured workflow
   - If conflict → use AskUserQuestion to clarify

**Insert these ITP todos (DO NOT overwrite existing):**

TodoWrite appending to existing todos:
[ITP template here]
```

### Step 2: Add Merge Strategy Section

Insert new section after the template explaining:

- When to ask user about priority conflicts
- How to handle existing todos that overlap with ITP phases
- Example AskUserQuestion for priority conflicts

### Step 3: Add Plan File Awareness

Add instruction to:

1. Read `~/.claude/plans/*.md` if exists
2. Extract any existing todos or tasks from plan
3. Present holistic view before inserting ITP todos

## Files to Modify

| File                          | Change                                      |
| ----------------------------- | ------------------------------------------- |
| `plugins/itp/commands/itp.md` | Rewrite lines 17-62 for insertion semantics |

## User Decisions (Confirmed)

| Question              | Decision                                                  |
| --------------------- | --------------------------------------------------------- |
| **Merge position**    | INTERLEAVE intelligently - map plan tasks into ITP phases |
| **Conflict handling** | Always ask user via AskUserQuestion                       |
| **Plan awareness**    | Always check `~/.claude/plans/` before creating todos     |

## Detailed Implementation

### New Section: Step 0 - Plan Integration (Before TodoWrite)

Add new mandatory step BEFORE the current TodoWrite:

```markdown
## Step 0: Plan-Aware Todo Integration (MANDATORY FIRST ACTION)

### Step 0.1: Check for Existing Plan File

1. Check if a plan file exists in `~/.claude/plans/`
2. If exists: Read the plan file and extract any tasks/todos
3. If system-reminder mentions a plan file: use that path

### Step 0.2: Check Existing Todos

1. Mentally model what's in TodoRead (existing todos)
2. Note any in_progress or pending items

### Step 0.3: Merge Strategy

**INTERLEAVE plan tasks into ITP phases:**

| Plan Task Type                 | Maps To ITP Phase      |
| ------------------------------ | ---------------------- |
| Research, explore, understand  | Preflight (before ADR) |
| Design, architecture decisions | Preflight (in ADR)     |
| Implementation tasks           | Phase 1                |
| Testing, validation            | Phase 1 (after impl)   |
| Documentation, cleanup         | Phase 2                |
| Release, deploy                | Phase 3                |

### Step 0.4: Conflict Resolution

**If a plan task doesn't clearly map to an ITP phase:**

Use AskUserQuestion:

- Option A: Insert before Preflight (do first)
- Option B: Insert into Phase 1 (during implementation)
- Option C: Insert after Phase 2 (do last, before release)

### Step 0.5: Holistic TodoWrite

After mapping, create a MERGED todo list that:

- Preserves all existing todos from plan file
- Inserts ITP workflow todos at appropriate positions
- Uses clear prefixes: `[Plan]` for plan items, `[ITP]` for workflow items
```

### Modified TodoWrite Template

```markdown
TodoWrite with todos (MERGED - preserving existing):

# From plan file (if any) - mapped to appropriate phases

- "[Plan] {task from plan}" | {status from plan}

# ITP Preflight

- "[ITP] Preflight: Create feature branch (if -b flag)" | pending
- "[ITP] Preflight: Skill -> implement-plan-preflight" | pending
- "[ITP] Preflight: Create ADR file" | pending
- "[ITP] Preflight: Skill -> adr-graph-easy-architect" | pending
- "[ITP] Preflight: Create design spec" | pending
- "[ITP] Preflight: Verify checkpoint" | pending

# ITP Phase 1

- "[Plan] {implementation tasks from plan}" | pending
- "[ITP] Phase 1: Sync ADR status" | pending
- "[ITP] Phase 1: Skill -> impl-standards" | pending
- "[ITP] Phase 1: Skill -> adr-code-traceability" | pending
- "[ITP] Phase 1: Execute implementation" | pending
- "[ITP] Phase 1: Skill -> code-hardcode-audit" | pending

# ITP Phase 2

- "[ITP] Phase 2: Format with Prettier" | pending
- "[ITP] Phase 2: Push to GitHub" | pending

# ITP Phase 3

- "[ITP] Phase 3: Release (if flags)" | pending
```

## Files to Modify

| File                          | Lines       | Change                                              |
| ----------------------------- | ----------- | --------------------------------------------------- |
| `plugins/itp/commands/itp.md` | 17-62       | Replace overwrite with merge logic                  |
| `plugins/itp/commands/itp.md` | New section | Add Step 0 (Plan Integration) before current Step 0 |

## Implementation Checklist

- [ ] Add Step 0: Plan Integration section (before current mandatory action)
- [ ] Modify TodoWrite template to show merge pattern
- [ ] Add AskUserQuestion example for conflicts
- [ ] Update "DO NOT" list to include "DO NOT ignore existing todos"
- [ ] Add prefix convention `[Plan]` and `[ITP]` for clarity
