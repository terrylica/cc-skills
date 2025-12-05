---
allowed-tools: Read, Write, Edit, Bash(git checkout:*), Bash(git pull:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(prettier --write:*), Bash(open:*), Bash(gh repo:*), Bash(cp:*), Bash(mkdir -p:*), Bash(date:*), Bash(PLUGIN_DIR:*), Bash(uv run:*), Grep, Glob, Task
argument-hint: "Start: [name] [-b] [-r] [-p] | Resume: -c [choice]"
description: "WORKFLOW COMMAND - Execute TodoWrite FIRST, then Preflight → Phase 1 → 2 → 3. Do NOT read ~/.claude/plans/ until after TodoWrite."
---

<!-- ⛔⛔⛔ MANDATORY: READ THIS ENTIRE FILE BEFORE ANY ACTION ⛔⛔⛔ -->

# ⛔ ITP Workflow — STOP AND READ

**DO NOT ACT ON ASSUMPTIONS. Read this file first.**

This is a structured workflow command. Follow the phases in order.

Your FIRST and ONLY action right now: **Execute the TodoWrite below.**

## ⛔ MANDATORY FIRST ACTION (NO EXCEPTIONS)

**YOUR FIRST ACTION MUST BE TodoWrite with the EXACT template below.**

DO NOT:

- ❌ Read any files in ~/.claude/plans/ first
- ❌ Create your own todos
- ❌ Jump to coding
- ❌ Create a branch before TodoWrite

**MANDATORY FIRST ACTION — Copy this TodoWrite template EXACTLY:**

```
TodoWrite with todos:
# Preflight - Skill tool calls marked explicitly
# CRITICAL: Branch creation MUST be FIRST if -b flag (before any file operations)
- "Preflight: Create feature branch (if -b flag) — MUST BE FIRST" | pending
- "Preflight: Skill tool call → implement-plan-preflight" | pending
- "Preflight: Create ADR file with MADR 4.0 frontmatter" | pending
- "Preflight: Skill tool call → adr-graph-easy-architect (MANDATORY for ALL ADRs, create Before/After + Architecture diagrams)" | pending
- "Preflight: Create design spec with YAML frontmatter" | pending
- "Preflight: Verify checkpoint (ADR + spec exist)" | pending

# Phase 1 - Skill tool calls marked explicitly
- "Phase 1: Sync ADR status proposed → accepted" | pending
- "Phase 1: Skill tool call → impl-standards" | pending
- "Phase 1: Skill tool call → adr-code-traceability" | pending
- "Phase 1: Execute implementation tasks from spec.md" | pending
- "Phase 1: Skill tool call → code-hardcode-audit" | pending

# Phase 2
- "Phase 2: Format markdown with Prettier" | pending
- "Phase 2: Push to GitHub" | pending
- "Phase 2: Open files in browser" | pending

# Phase 3 — REQUIRES -r or -p flag on main/master
# On feature branches: verbose reminder shown, Phase 3 skips
# On main without flags: Phase 3 skips with "use -r or -p" message
- "Phase 3: Pre-release verification (if -r or -p on main)" | pending
- "Phase 3: Skill tool call → semantic-release (if -r flag on main)" | pending
- "Phase 3: Skill tool call → pypi-doppler (if -p flag on main)" | pending
- "Phase 3: Final status sync (if -r or -p on main)" | pending
```

**After TodoWrite completes, proceed to Preflight section below.**

---

## Quick Reference

### Skills Invoked

| Skill                      | Phase     | Purpose                         |
| -------------------------- | --------- | ------------------------------- |
| `implement-plan-preflight` | Preflight | ADR + Design Spec creation      |
| `adr-graph-easy-architect` | Preflight | Architecture diagrams           |
| `impl-standards`           | Phase 1   | Error handling, constants       |
| `adr-code-traceability`    | Phase 1   | Code-to-ADR references          |
| `code-hardcode-audit`      | Phase 1   | Pre-release validation          |
| `semantic-release`         | Phase 3   | Version tagging + release       |
| `pypi-doppler`             | Phase 3   | PyPI publishing (if applicable) |

### File Locations

| Artifact    | Path                                 | Notes                                |
| ----------- | ------------------------------------ | ------------------------------------ |
| ADR         | `/docs/adr/$ADR_ID.md`               | Permanent                            |
| Design Spec | `/docs/design/$ADR_ID/spec.md`       | Permanent, SSoT after Preflight      |
| Global Plan | `~/.claude/plans/<adj-verb-noun>.md` | **EPHEMERAL** - replaced on new plan |

### Spec YAML Frontmatter

```yaml
---
adr: YYYY-MM-DD-slug # Links to ADR (programmatic)
source: ~/.claude/plans/<adj-verb-noun>.md # Global plan (EPHEMERAL)
implementation-status: in_progress # in_progress | blocked | completed | abandoned
phase: preflight # preflight | phase-1 | phase-2 | phase-3
last-updated: YYYY-MM-DD
---
```

**Note**: The `source` field preserves the global plan filename for traceability, but the file may no longer exist after a new plan is created.

### ADR ID Format

```
ADR_ID="$(date +%Y-%m-%d)-<slug>"
```

Example: `2025-12-01-clickhouse-aws-ohlcv-ingestion`

### Folder Structure

```text
/docs/
  adr/
    YYYY-MM-DD-slug.md          # ADR file
  design/
    YYYY-MM-DD-slug/            # Design folder (1:1 with ADR)
      spec.md                   # Active implementation spec (SSoT)
```

**Naming Rule**: Use exact same `YYYY-MM-DD-slug` for both ADR and Design folder.

---

## CRITICAL: Mandatory Workflow Execution

**THIS WORKFLOW IS NON-NEGOTIABLE. DO NOT SKIP ANY PHASE.**

You MUST execute ALL phases in order, regardless of task complexity:

1. **Step 0**: TodoWrite initialization (FIRST ACTION - NO EXCEPTIONS)
2. **Preflight**: ADR + Design Spec creation
3. **Phase 1**: Implementation per spec.md
4. **Phase 2**: Format & Push
5. **Phase 3**: Release (if on main/master)

**FORBIDDEN BEHAVIORS:**

- ❌ Deciding "this is simple, skip the workflow"
- ❌ Jumping directly to implementation without TodoWrite
- ❌ Skipping ADR/Design Spec for "document fixes" or "small changes"
- ❌ Making autonomous judgments to bypass phases

**If the task seems too simple for this workflow**: Stop and ask the user if they want to proceed without `/itp`. Do NOT silently skip phases.

---

## Arguments

Parse `$ARGUMENTS` for:

| Argument     | Short | Description                                                       | Default                         |
| ------------ | ----- | ----------------------------------------------------------------- | ------------------------------- |
| `slug`       | -     | Feature name for ADR ID (e.g., `clickhouse-aws-ohlcv-ingestion`)  | Derive from Global Plan context |
| `--branch`   | `-b`  | Create branch `{type}/{adr-id}` from main/master                  | Work on current branch          |
| `--continue` | `-c`  | Continue in-progress work; optionally provide decision            | Last "Recommended Next Steps"   |
| `--release`  | `-r`  | Enable semantic-release in Phase 3 (required on main for release) | Skip Phase 3 release            |
| `--publish`  | `-p`  | Enable PyPI publishing in Phase 3 (required on main for publish)  | Skip Phase 3 publish            |

**Usage Examples**:

```text
# Fresh start modes (no release)
/itp                   # Derive slug, stay on current branch
/itp my-feature        # Custom slug, stay on current branch
/itp -b                # Derive slug, create {type}/{adr-id} branch
/itp my-feature -b     # Custom slug, create {type}/{adr-id} branch

# Feature branch with release intent (reminder shown, Phase 3 skips)
/itp my-feature -b -r        # Intent to release after merge
/itp my-feature -b -r -p     # Intent to release + publish after merge

# Release modes (on main/master only)
/itp -r                # On main: run semantic-release only
/itp -p                # On main: run PyPI publish only
/itp -r -p             # On main: full release + publish

# Continuation modes
/itp -c                # Continue: auto-detect ADR, resume
/itp -c "use Redis"    # Continue with explicit decision
```

**Mode Selection**:

- Fresh start: `[slug] [-b]` — creates new ADR
- Continuation: `-c [decision]` — resumes existing ADR

These modes are **mutually exclusive**. `-c` cannot be combined with `slug` or `-b`.

**Branch Type**: Determine `{type}` from ADR nature (conventional commits):

| Type       | When                                   |
| ---------- | -------------------------------------- |
| `feat`     | New capability or feature              |
| `fix`      | Bug fix                                |
| `refactor` | Code restructuring, no behavior change |
| `docs`     | Documentation only                     |
| `chore`    | Maintenance, tooling, dependencies     |
| `perf`     | Performance improvement                |

**Slug Derivation**: If no slug is provided, derive an appropriate kebab-case slug from the Global Plan's context (the feature/task being implemented). The slug should be descriptive (3-5 words) and capture the essence of the feature.

**Word Economy Rule**: Each word in the slug MUST convey unique meaning. Avoid redundancy.

| Example                          | Verdict | Reason                                                           |
| -------------------------------- | ------- | ---------------------------------------------------------------- |
| `clickhouse-database-migration`  | ❌ Bad  | "database" redundant (ClickHouse IS a database)                  |
| `clickhouse-aws-ohlcv-ingestion` | ✅ Good | clickhouse=tech, aws=platform, ohlcv=data-type, ingestion=action |
| `user-auth-token-refresh`        | ✅ Good | user=scope, auth=domain, token=artifact, refresh=action          |
| `api-endpoint-rate-limiting`     | ✅ Good | api=layer, endpoint=target, rate=metric, limiting=action         |

**ADR ID**: See [Quick Reference](#adr-id-format) for format. The ADR ID is the canonical identifier used in:

- ADR file, Design folder, Code references, Branch name (if `-b`)

---

## Workflow Preview

**Detect branch and show expected workflow before starting.**

```bash
CURRENT_BRANCH=$(git branch --show-current)
WILL_BE_ON_MAIN=true

# If -b flag used, will end up on feature branch
if [ -n "$BRANCH_FLAG" ]; then
  WILL_BE_ON_MAIN=false
fi

# If already not on main/master
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  WILL_BE_ON_MAIN=false
fi
```

**Show workflow preview based on branch and flags:**

| Condition                      | Workflow                        | Message                                               |
| ------------------------------ | ------------------------------- | ----------------------------------------------------- |
| main/master, no flags          | `Preflight → 1 → 2 → END`       | "Phase 3 skipped. Use -r for release, -p for publish" |
| main/master, `-r`              | `Preflight → 1 → 2 → 3.2`       | "Running semantic-release..."                         |
| main/master, `-p`              | `Preflight → 1 → 2 → 3.3`       | "Running PyPI publish..."                             |
| main/master, `-r -p`           | `Preflight → 1 → 2 → 3.2 → 3.3` | "Running full release..."                             |
| feature (`-b`), no `-r`/`-p`   | `Preflight → 1 → 2 → END`       | Standard feature branch message                       |
| feature (`-b`), with `-r`/`-p` | `Preflight → 1 → 2 → END`       | Verbose reminder (see Phase 3)                        |

**Phase 3 now requires explicit flags on main/master.** This is a breaking change from previous behavior where Phase 3 ran automatically.

---

## Step 0: Initialize Todo List (ALREADY DONE)

**If you followed the ⛔ STOP instruction at the top, this step is complete.**

The TodoWrite template is at the top of this file. If you haven't executed it yet, **STOP and go back to the top**.

**Mark each todo `in_progress` before starting, `completed` when done.**

### Preflight Gate (MANDATORY)

**You CANNOT proceed to Phase 1 until ALL Preflight todos are marked `completed`.**

Before starting "Phase 1: Execute implementation tasks":

1. Verify all `Preflight:` todos show `completed`
2. Verify ADR file exists at `/docs/adr/$ADR_ID.md`
3. Verify design spec exists at `/docs/design/$ADR_ID/spec.md`

If any Preflight item is not complete, **STOP** and complete it first. Do NOT skip ahead.

---

## Preflight: Artifact Setup

**MANDATORY Skill tool call: `implement-plan-preflight`** — activate NOW before proceeding.

This skill provides detailed ADR and Design Spec creation instructions.

The skill provides:

- MADR 4.0 frontmatter template and required sections
- Perspectives taxonomy (11 types)
- Step-by-step workflow for ADR and design spec creation
- Validation script for checkpoint verification

### Preflight Steps (via skill)

1. **P.0**: **Create feature branch FIRST** (if `-b` flag) — MUST happen before ANY file operations
2. **P.1**: **MANDATORY Skill tool call: `implement-plan-preflight`** — activate NOW for ADR/spec instructions
3. **P.2**: Create ADR file — path in [Quick Reference](#file-locations)
4. **P.2.1**: **ADR Diagram Creation (MANDATORY for ALL ADRs)**

   **ALL ADRs require BOTH diagrams — NO EXCEPTIONS, regardless of task complexity.**
   - INVOKE: **Skill tool call with `adr-graph-easy-architect`** — triggers diagram workflow
   - CREATE: **Before/After diagram** — visualizes state change in Context section
   - CREATE: **Architecture diagram** — visualizes component relationships in Architecture section
   - VERIFY: Confirm BOTH diagrams embedded in ADR before proceeding

   **BLOCKING GATE**: Do NOT proceed to P.3 until BOTH diagrams are verified in ADR.

   **Common mistake**: Skipping diagrams for "simple" ADRs. Even documentation-only ADRs benefit from Before/After visualization.

5. **P.3**: Create design spec — path in [Quick Reference](#file-locations)
6. **P.4**: Verify checkpoint

**WHY P.0 FIRST**: Files created before `git checkout -b` stay on main/master. Branch must exist before ADR/spec creation.

### Preflight Checkpoint (MANDATORY)

**STOP. Verify artifacts exist before proceeding to Phase 1.**

Run validator:

```bash
# Environment-agnostic path (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
uv run "$PLUGIN_DIR/skills/implement-plan-preflight/scripts/preflight-validator.py" $ADR_ID
```

Or verify manually:

- [ ] ADR file exists at `/docs/adr/$ADR_ID.md`
- [ ] ADR has YAML frontmatter with all 7 required fields
- [ ] ADR has `status: proposed` (initial state)
- [ ] ADR has `**Design Spec**:` link in header
- [ ] **DIAGRAM CHECK 1**: ADR has **Before/After diagram** in Context section (graph-easy block showing state change)
- [ ] **DIAGRAM CHECK 2**: ADR has **Architecture diagram** in Architecture section (graph-easy block showing components)

**⛔ DIAGRAM VERIFICATION (BLOCKING):**
If either diagram is missing, **STOP** and invoke `adr-graph-easy-architect` skill again.
Search ADR for `<!-- graph-easy source:` — you need TWO separate blocks.

- [ ] Design spec exists at `/docs/design/$ADR_ID/spec.md`
- [ ] Design spec has YAML frontmatter with all 5 required fields
- [ ] Design spec has `implementation-status: in_progress`
- [ ] Design spec has `phase: preflight`
- [ ] Design spec has `**ADR**:` backlink in header
- [ ] Feature branch created (if `-b` flag specified)

**If any item is missing**: Complete it now. Do NOT proceed to Phase 1.

---

## Phase 1: Implementation

### 1.1 Resumption Protocol

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
   - If found AND `-c "decision"` provided → apply decision, remove pending marker
   - If found AND `-c` alone → use last "Recommended Next Steps" as default action
   - If no pending decision → proceed to step c

   c. Check todo list for current task:
   - Find task with `status: in_progress`
   - Resume implementation from that task

   d. **Verify branch matches ADR context**:
   - Check current branch: `git branch --show-current`
   - If ADR was created on a feature branch, verify you're on that branch
   - If branch mismatch detected, warn user before proceeding

3. **Sync check** (both modes):
   - Re-read and update the design spec
   - Verify: ADR ↔ Design Spec ↔ Todo ↔ Code alignment
   - Report any drift before proceeding

### 1.2 Implement the Spec

Execute each task in `spec.md`:

1. Mark current task as `in_progress` in todo list
2. Implement the change
3. Verify it works
4. Update `spec.md` to reflect completion
5. Mark task as `completed`
6. Move to next task

### 1.3 Engineering Standards

**Skill Execution Order** (invoke sequentially, in this order):

1. **`impl-standards`** — Apply error handling & constants patterns FIRST
2. **`adr-code-traceability`** — Add ADR references to code SECOND
3. **`code-hardcode-audit`** — Final audit LAST (before Phase 2)

**MANDATORY Skill tool call: `impl-standards`** — activate NOW for detailed standards.

**MANDATORY Skill tool call: `adr-code-traceability`** — activate NOW for ADR references in code.

**MANDATORY Skill tool call: `code-hardcode-audit`** — activate NOW before release.

### 1.4 Decision Capture

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

### 1.5 Status Synchronization Protocol

**Rule**: Spec `implementation-status` drives ADR `status` updates.

| Spec Status            | →   | ADR Status    | When                             |
| ---------------------- | --- | ------------- | -------------------------------- |
| `in_progress`          | →   | `accepted`    | Phase 1 starts                   |
| `blocked`              | →   | `accepted`    | (no change, still accepted)      |
| `completed`            | →   | `accepted`    | Phase 1/2 complete, not released |
| `completed` + released | →   | `implemented` | Phase 3 complete                 |
| `abandoned`            | →   | `rejected`    | Work stopped                     |

**At Phase 1 start** (immediately upon entering Phase 1, BEFORE executing first task):

```bash
# Update ADR status: proposed → accepted
sed -i '' 's/^status: proposed/status: accepted/' docs/adr/$ADR_ID.md
# Update spec phase
sed -i '' 's/^phase: preflight/phase: phase-1/' docs/design/$ADR_ID/spec.md
```

**Before Phase 2** (sync checklist):

- [ ] ADR `status: accepted`
- [ ] Spec `implementation-status: in_progress` or `completed`
- [ ] Spec `phase: phase-1`
- [ ] Spec `last-updated: YYYY-MM-DD` is current

### Phase 1 Success Criteria

- [ ] Implementation complete per spec.md
- [ ] All artifacts synced (ADR ↔ spec ↔ todo ↔ code)
- [ ] New files include `ADR: {adr-id}` in file header
- [ ] Non-obvious changes have inline `ADR:` comments

---

## Phase 2: Format & Push

### 2.1 Format Markdown

Run Prettier against ADR and spec:

```bash
prettier --write --no-config --parser markdown --prose-wrap preserve \
  docs/adr/$ADR_ID.md \
  docs/design/$ADR_ID/spec.md
```

### 2.2 Push to GitHub

```bash
git add docs/adr/$ADR_ID.md docs/design/$ADR_ID/
git commit -m "docs: add ADR and design spec for <slug>"

# If --branch was used:
git push -u origin <type>/$ADR_ID

# If working on current branch (default):
git push origin $(git branch --show-current)
```

### 2.3 Open in Browser

```bash
# Get repo URL and current branch
REPO_URL=$(gh repo view --json url -q .url)
BRANCH=$(git branch --show-current)

open "$REPO_URL/blob/$BRANCH/docs/adr/$ADR_ID.md"
open "$REPO_URL/blob/$BRANCH/docs/design/$ADR_ID/spec.md"
```

### Phase 2 Success Criteria

- [ ] Markdown formatted with Prettier
- [ ] Pushed to GitHub
- [ ] Files viewable in browser

---

## Phase 3: Release & Publish (Requires -r or -p Flag on Main)

**Phase 3 requires EXPLICIT flags. It does NOT run automatically.**

### Entry Gate Logic

Parse flags from invocation:

- `RELEASE_FLAG`: true if `-r` or `--release` provided
- `PUBLISH_FLAG`: true if `-p` or `--publish` provided

```bash
# Check branch
CURRENT_BRANCH=$(git branch --show-current)

# Parse flags
RELEASE_FLAG=false
PUBLISH_FLAG=false
[[ "$ARGUMENTS" =~ -r|--release ]] && RELEASE_FLAG=true
[[ "$ARGUMENTS" =~ -p|--publish ]] && PUBLISH_FLAG=true
```

**Case 1: Feature Branch (not main/master)**

```bash
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  if [ "$RELEASE_FLAG" = true ] || [ "$PUBLISH_FLAG" = true ]; then
    # Verbose reminder when flags provided on feature branch
    echo "  ⚠️  PHASE 3 DEFERRED (Feature Branch)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  You provided release/publish flags on a feature branch:"
    [ "$RELEASE_FLAG" = true ] && echo "    -r (release): YES"
    [ "$PUBLISH_FLAG" = true ] && echo "    -p (publish): YES"
    echo ""
    echo "  Current branch: $CURRENT_BRANCH"
    echo ""
    echo "  Phase 3 CANNOT run on feature branches."
    echo "  These flags are recorded as YOUR INTENT for after merge."
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │ NEXT STEPS (you must do these manually):                │"
    echo "  ├─────────────────────────────────────────────────────────┤"
    echo "  │ 1. Create PR: gh pr create                              │"
    echo "  │ 2. Get approval and merge to main/master                │"
    echo "  │ 3. Switch: git checkout main && git pull                │"
    [ "$RELEASE_FLAG" = true ] && echo "  │ 4. Release: /itp -r    # semantic-release              │"
    [ "$PUBLISH_FLAG" = true ] && echo "  │ 5. Publish: /itp -p    # PyPI publish                  │"
    echo "  │                                                         │"
    echo "  │ Or combine: /itp -r -p    # for both                    │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
    echo "  The release/publish steps will NOT happen automatically."
    echo "  You MUST manually run them after merging to main."
  else
    # Standard feature branch message (no flags)
    echo "  ✅ WORKFLOW COMPLETE (Phase 2)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Current branch: $CURRENT_BRANCH"
    echo "  Phase 3 (Release): SKIPPED - not on main/master"
    echo ""
    echo "  Next steps:"
    echo "    1. Create PR: gh pr create"
    echo "    2. Get approval and merge to main/master"
    echo "    3. Run /itp -r on main to release (or /itp -r -p for both)"
  fi
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  exit 0
fi
```

**Case 2: Main/Master WITHOUT flags**

```bash
if [ "$RELEASE_FLAG" = false ] && [ "$PUBLISH_FLAG" = false ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  ℹ️  PHASE 3 SKIPPED (No Flags)"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "  You are on: $CURRENT_BRANCH"
  echo "  But no release/publish flags were provided."
  echo ""
  echo "  To release this version, run one of:"
  echo "    /itp -r       # semantic-release (version + changelog + GitHub)"
  echo "    /itp -p       # PyPI publishing (if applicable)"
  echo "    /itp -r -p    # both release and publish"
  echo ""
  echo "  Phase 3 requires explicit intent via flags."
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  exit 0
fi
```

**Case 3: Main/Master WITH flags** → Proceed to Phase 3 subsections below.

### 3.1 Pre-Release Verification

Before releasing:

- [ ] All Success Criteria items in design spec are checked off
- [ ] Status value in design spec is updated (e.g., `Accepted`, `Implemented`)
- [ ] ADR and spec.md are in sync with final implementation
- [ ] Version fields use `semantic-release` patterns (no dynamic versioning)

### 3.2 Semantic Release (if -r flag)

**Condition**: Only execute if `-r` or `--release` flag was provided.

```bash
if [ "$RELEASE_FLAG" = true ]; then
  # Proceed with semantic-release
fi
```

**MANDATORY Skill tool call: `semantic-release`** — activate NOW for version tagging and release.

- Follow the [Local Release Workflow](../skills/semantic-release/references/local-release-workflow.md)
- Conventional commits → tag → release → changelog → push

### 3.3 PyPI Publishing (if -p flag)

**Condition**: Only execute if `-p` or `--publish` flag was provided.

```bash
if [ "$PUBLISH_FLAG" = true ]; then
  # Proceed with PyPI publishing
fi
```

Only if package pre-exists on PyPI:

- **MANDATORY Skill tool call: `pypi-doppler`** — activate NOW to publish

### 3.4 Earthly Pipeline

Use Earthly as canonical pipeline:

- Non-blocking, observability-first
- Ensure GitHub Release exists
- Record stats/errors
- Pushover alert
- Wire into GitHub Actions

### Phase 3 Success Criteria

- [ ] ADR status updated to `accepted` or `implemented`
- [ ] Release completed via semantic-release
- [ ] If feature branch: PR created, Phase 3 skipped
