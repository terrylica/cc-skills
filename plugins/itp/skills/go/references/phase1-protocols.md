**Skill**: [ITP Go Workflow](../SKILL.md)

# Phase 1 Protocols

## 1.1 Resumption Protocol

**Entry point for both fresh starts and continuations.**

1. **Detect mode**:
   - If `-c` flag: continuation mode (skip to step 2)
   - Otherwise: fresh start (skip to step 3)

2. **For continuation (`-c`)**:

   a. Find in-progress ADR:
   - Search `docs/design/*/spec.md` for `status: in_progress`
   - Or find todo list item marked `in_progress`

   b. Re-read `spec.md` and check for pending decision:
   - Look for `## Pending Decision` section
   - If found AND `-c "decision"` provided: apply decision, remove pending marker
   - If found AND `-c` alone: use last "Recommended Next Steps" as default action
   - If no pending decision: proceed to step c

   c. Check todo list for current task:
   - Find task with `status: in_progress`
   - Resume implementation from that task

   d. **Verify branch matches ADR context**:
   - Check current branch: `git branch --show-current`
   - If ADR was created on a feature branch, verify you're on that branch
   - If branch mismatch detected, warn user before proceeding

3. **Sync check** (both modes):
   - Re-read and update the design spec
   - Verify: ADR <-> Design Spec <-> Todo <-> Code alignment
   - Report any drift before proceeding

## 1.4 Decision Capture

When implementation requires a user decision:

1. **Update spec.md** with pending decision:

   ```markdown
   ## Pending Decision

   **Topic**: [What needs to be decided]
   **Options**:

   - A: [Option A description]
   - B: [Option B description]
     **Context**: [Why this decision is needed now]
     **Blocked task**: [Current task waiting on this]
   ```

2. **Update todo list**: Mark current task as `blocked: awaiting decision`

3. **Then ask**: Use AskUserQuestion with clear options

4. **After answer**:
   - Remove `## Pending Decision` section from spec.md
   - Update Decision Log in ADR
   - Mark task as `in_progress` again
   - Continue implementation

## 1.5 Status Synchronization Protocol

**Rule**: Spec `implementation-status` drives ADR `status` updates.

| Spec Status            | ->  | ADR Status    | When                             |
| ---------------------- | --- | ------------- | -------------------------------- |
| `in_progress`          | ->  | `accepted`    | Phase 1 starts                   |
| `blocked`              | ->  | `accepted`    | (no change, still accepted)      |
| `completed`            | ->  | `accepted`    | Phase 1/2 complete, not released |
| `completed` + released | ->  | `implemented` | Phase 3 complete                 |
| `abandoned`            | ->  | `rejected`    | Work stopped                     |

**At Phase 1 start** (immediately upon entering Phase 1, BEFORE executing first task):

```bash
# Update ADR status: proposed -> accepted
sed -i '' 's/^status: proposed/status: accepted/' docs/adr/$ADR_ID.md
# Update spec phase
sed -i '' 's/^phase: preflight/phase: phase-1/' docs/design/$ADR_ID/spec.md
```

**Before Phase 2** (sync checklist):

- [ ] ADR `status: accepted`
- [ ] Spec `implementation-status: in_progress` or `completed`
- [ ] Spec `phase: phase-1`
- [ ] Spec `last-updated: YYYY-MM-DD` is current
