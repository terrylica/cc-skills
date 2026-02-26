**Skill**: [ITP Go Workflow](../SKILL.md)

# TodoWrite Merge Strategy

## Step 0.1: Check for Existing Plan File

1. Check if a plan file exists in `~/.claude/plans/`
2. If system-reminder mentions a plan file path: use that specific path
3. If plan file exists: Read it and extract any tasks/todos from it

## Step 0.2: Check Existing Todos

1. Check your mental model of existing todos (from prior conversation)
2. Note any `in_progress` or `pending` items that should be preserved

## Step 0.3: Merge Strategy (INTERLEAVE)

**Map plan tasks into ITP phases intelligently:**

| Plan Task Type                 | Maps To ITP Phase      |
| ------------------------------ | ---------------------- |
| Research, explore, understand  | Preflight (before ADR) |
| Design, architecture decisions | Preflight (in ADR)     |
| Implementation tasks           | Phase 1                |
| Testing, validation            | Phase 1 (after impl)   |
| Documentation, cleanup         | Phase 2                |
| Release, deploy                | Phase 3                |

## Step 0.4: Conflict Resolution

**If a plan task doesn't clearly map to an ITP phase, use AskUserQuestion:**

```
AskUserQuestion with questions:
- question: "Where should '{task_name}' be placed in the ITP workflow?"
  header: "Task placement"
  options:
    - label: "Before Preflight"
      description: "Do this task first, before ADR creation"
    - label: "Phase 1"
      description: "Do during implementation"
    - label: "After Phase 2"
      description: "Do last, before release"
  multiSelect: false
```

## Step 0.5: Create MERGED TodoWrite

**After mapping, create a MERGED todo list using these prefixes:**

- `[Plan]` -- Tasks from the plan file
- `[ITP]` -- ITP workflow tasks

**MANDATORY TodoWrite template (MERGE with existing, do NOT overwrite):**

```
TodoWrite with todos (MERGED - preserving existing):

# From plan file (if any) - mapped to Preflight
# Example: "[Plan] Research existing implementation" | pending

# ITP Preflight - Skill tool calls marked explicitly
# CRITICAL: Branch creation MUST be FIRST if -b flag (before any file operations)
- "[ITP] Preflight: Create feature branch (if -b flag) — MUST BE FIRST" | pending
- "[ITP] Preflight: Skill tool call → implement-plan-preflight" | pending
- "[ITP] Preflight: Create ADR file with MADR 4.0 frontmatter" | pending
- "[ITP] Preflight: Skill tool call → adr-graph-easy-architect (Before/After + Architecture diagrams)" | pending
- "[ITP] Preflight: Create design spec with YAML frontmatter" | pending
- "[ITP] Preflight: Verify checkpoint (ADR + spec exist)" | pending

# From plan file (if any) - mapped to Phase 1
# Example: "[Plan] Implement the new feature" | pending

# ITP Phase 1 - Skill tool calls marked explicitly
- "[ITP] Phase 1: Sync ADR status proposed → accepted" | pending
- "[ITP] Phase 1: Skill tool call → impl-standards" | pending
- "[ITP] Phase 1: Skill tool call → mise-configuration (if new scripts)" | pending
- "[ITP] Phase 1: Skill tool call → adr-code-traceability" | pending
- "[ITP] Phase 1: Execute implementation tasks from spec.md" | pending
- "[ITP] Phase 1: Skill tool call → code-hardcode-audit" | pending

# From plan file (if any) - mapped to Phase 2
# Example: "[Plan] Update documentation" | pending

# ITP Phase 2
- "[ITP] Phase 2: Format markdown with Prettier" | pending
- "[ITP] Phase 2: Push to GitHub" | pending
- "[ITP] Phase 2: Open files in browser" | pending

# ITP Phase 3 — REQUIRES -r or -p flag on main/master
- "[ITP] Phase 3: Pre-release verification (if -r or -p on main)" | pending
- "[ITP] Phase 3: Skill tool call → semantic-release (if -r flag on main)" | pending
- "[ITP] Phase 3: Skill tool call → pypi-doppler (if -p flag on main)" | pending
- "[ITP] Phase 3: Final status sync (if -r or -p on main)" | pending
```

**After TodoWrite completes, proceed to Preflight section in SKILL.md.**
