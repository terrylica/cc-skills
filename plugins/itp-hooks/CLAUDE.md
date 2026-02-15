# itp-hooks Plugin

> Claude Code hooks for ITP workflow enforcement, code correctness, and commit validation.

## Overview

This plugin provides PreToolUse and PostToolUse hooks that enforce development standards, prevent common mistakes, and ensure compliance with project requirements.

## Hooks

### PreToolUse Hooks

| Hook                                   | Matcher           | Purpose                                                                                                                                    |
| -------------------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `pretooluse-guard.sh`                  | Write\|Edit       | Implementation standards enforcement                                                                                                       |
| `pretooluse-fake-data-guard.mjs`       | Write             | Prevents fake/placeholder data in production code                                                                                          |
| `pretooluse-version-guard.mjs`         | Write\|Edit       | Version consistency validation                                                                                                             |
| `pretooluse-process-storm-guard.mjs`   | Bash\|Write\|Edit | Prevents fork bomb patterns                                                                                                                |
| `pretooluse-cwd-deletion-guard.ts`     | Bash              | Prevents deleting the current working directory                                                                                            |
| `pretooluse-vale-claude-md-guard.ts`   | Write\|Edit       | **Rejects** CLAUDE.md edits with Vale violations                                                                                           |
| `pretooluse-hoisted-deps-guard.mjs`    | Write\|Edit       | pyproject.toml root-only and path escape policies                                                                                          |
| `pretooluse-gpu-optimization-guard.ts` | Write\|Edit       | GPU optimization enforcement (AMP, batch sizing)                                                                                           |
| `pretooluse-mise-hygiene-guard.ts`     | Write\|Edit       | mise.toml hygiene (line limit, secrets detection)                                                                                          |
| `pretooluse-file-size-guard.ts`        | Write\|Edit       | File size bloat prevention (per-extension limits)                                                                                          |
| `sred-commit-guard.ts`                 | Bash              | SR&ED commit format enforcement                                                                                                            |
| `pretooluse-pueue-wrap-guard.ts`       | Bash              | Auto-wraps long-running commands with pueue + injects OP_SERVICE_ACCOUNT_TOKEN for Claude Automation vault (MUST be LAST PreToolUse entry) |

### PostToolUse Hooks

| Hook                              | Matcher           | Purpose                                                     |
| --------------------------------- | ----------------- | ----------------------------------------------------------- |
| `posttooluse-reminder.ts`         | Bash\|Write\|Edit | Context-aware reminders (UV, Pueue, graph-easy, ADR sync)   |
| `code-correctness-guard.sh`       | Bash\|Write\|Edit | Silent failure detection only (NO unused imports, NO style) |
| `posttooluse-vale-claude-md.ts`   | Write\|Edit       | Vale terminology check on CLAUDE.md files                   |
| `posttooluse-glossary-sync.ts`    | Write\|Edit       | Auto-sync GLOSSARY.md to Vale vocabulary                    |
| `posttooluse-terminology-sync.ts` | Write\|Edit       | Project CLAUDE.md to global GLOSSARY.md sync                |

## SR&ED Commit Guard

The `sred-commit-guard.ts` hook enforces commit messages that include both:

1. **Conventional commit type** (feat, fix, docs, etc.)
2. **SR&ED git trailers** for Canada CRA tax credit compliance

### Required Format

```
<type>(<scope>): <subject>

<body>

SRED-Type: <category>
SRED-Claim: <claim-id>  (optional)
```

### SR&ED Categories

| Category                   | CRA Definition                                                            |
| -------------------------- | ------------------------------------------------------------------------- |
| `experimental-development` | Systematic work to produce new materials, devices, products, or processes |
| `applied-research`         | Original investigation with specific practical application in view        |
| `basic-research`           | Original investigation without specific practical application             |
| `systematic-investigation` | Work involving hypothesis, testing, and analysis                          |

### Example Commit

```
feat(ith-python): implement adaptive TMAEG threshold algorithm

Adds volatility-regime-aware threshold adjustment for ITH epoch detection.

SRED-Type: experimental-development
SRED-Claim: 2026-Q1-ITH
```

### Extraction for CRA Claims

```bash
# List all SR&ED commits
git log --format='%H|%ad|%s|%(trailers:key=SRED-Type,valueonly)' --date=short | grep -v '|$'

# Sum by category
git log --format='%(trailers:key=SRED-Type,valueonly)' | sort | uniq -c
```

## Plan Mode Detection

Hooks can detect when Claude is in plan mode and skip validation. This prevents blocking during planning phase when Claude writes to plan files or explores the codebase.

### Usage

```typescript
import { isPlanMode, allow } from "./pretooluse-helpers.ts";

const planContext = isPlanMode(input, {
  checkPermission: true,
  checkPath: true,
});
if (planContext.inPlanMode) {
  logger.debug("Skipping in plan mode", { reason: planContext.reason });
  return allow();
}
```

### Detection Signals

| Signal                             | Priority  | Description                                          |
| ---------------------------------- | --------- | ---------------------------------------------------- |
| `permission_mode: "plan"`          | Primary   | Claude Code sets this when `EnterPlanMode` is active |
| File path `/plans/*.md`            | Secondary | Catches writes to plan directories                   |
| Active files in `~/.claude/plans/` | Tertiary  | Expensive filesystem check (disabled by default)     |

### Hooks with Plan Mode Support

- `pretooluse-version-guard.mjs` - Skips version checks in plan mode
- `pretooluse-mise-hygiene-guard.ts` - Skips hygiene checks in plan mode

**ADR**: [/docs/adr/2026-02-05-plan-mode-detection-hooks.md](/docs/adr/2026-02-05-plan-mode-detection-hooks.md)

## Read-Only Command Detection

Hooks can skip validation for read-only commands (grep, find, ls, etc.) to reduce noise. This follows the [Claude Code hooks best practice](https://code.claude.com/docs/en/hooks) of skipping non-destructive operations.

### Usage

```typescript
import { isReadOnly, allow } from "./pretooluse-helpers.ts";

if (tool_name === "Bash") {
  const command = tool_input.command || "";
  if (isReadOnly(command)) {
    return allow(); // Skip validation for read-only commands
  }
}
```

### Detected Read-Only Commands

| Category      | Commands                                          |
| ------------- | ------------------------------------------------- |
| Search        | `rg`, `grep`, `ag`, `ack`, `find`, `fd`, `locate` |
| File viewing  | `cat`, `less`, `head`, `tail`, `bat`              |
| Directory     | `ls`, `tree`, `exa`, `eza`                        |
| Git read-only | `git status`, `git log`, `git diff`, `git show`   |
| Package info  | `npm list`, `pip list`, `cargo tree`              |

### Hooks with Read-Only Detection

- `pretooluse-process-storm-guard.mjs` - Skips process storm checks for read-only commands
- `pretooluse-cwd-deletion-guard.ts` - Skips CWD deletion checks for read-only commands

## CWD Deletion Guard

The `pretooluse-cwd-deletion-guard.ts` hook prevents commands that would delete the current working directory. When CWD is deleted, the shell becomes permanently broken — every subsequent command (including `cd`) fails with exit code 1.

### Two Lessons Encoded

| Lesson              | Problem                                   | Solution                                                |
| ------------------- | ----------------------------------------- | ------------------------------------------------------- |
| Never delete CWD    | Shell unrecoverable after `rm -rf $(pwd)` | `cd /tmp && rm -rf <target>`                            |
| Don't rm + re-clone | Wasteful and breaks CWD                   | `git remote set-url` + `git fetch` + `git reset --hard` |

### Detection Patterns

| Pattern          | Example                                               |
| ---------------- | ----------------------------------------------------- |
| Exact path match | `rm -rf /path/to/cwd` where path = CWD                |
| Parent deletion  | `rm -rf ~/fork-tools` when CWD is `~/fork-tools/repo` |
| Relative CWD     | `rm -rf .` or `rm -rf ./`                             |
| Shell expansion  | `rm -rf $(pwd)` or `rm -rf $PWD`                      |
| Tilde expansion  | `rm -rf ~/project` matching CWD                       |

### Git-Aware Guidance

When the command includes `git clone` or `gh repo clone` (rm-before-reclone pattern), the denial message suggests `git remote set-url` instead:

```bash
# Instead of: rm -rf ~/fork-tools/repo && git clone <new-url> ~/fork-tools/repo
# Do:
git remote set-url origin <new-url>
git fetch origin
git reset --hard origin/main
```

### Escape Hatch

Add `# CWD-DELETE-OK` comment to bypass:

```bash
rm -rf ~/fork-tools/repo  # CWD-DELETE-OK
```

## File Size Bloat Guard

The `pretooluse-file-size-guard.ts` hook prevents single-file bloat by checking line count before Write/Edit operations. Uses `ask` mode (confirmation dialog) so the user can override when intentional.

### Detection

| Tool  | Method                                                                  |
| ----- | ----------------------------------------------------------------------- |
| Write | Counts lines in proposed `content`                                      |
| Edit  | Reads existing file, applies `old_string` → `new_string`, counts result |

### Default Thresholds

| Extension                  | Warn | Block |
| -------------------------- | ---- | ----- |
| `.rs`, `.py`, `.ts`, `.go` | 500  | 1000  |
| `.md`                      | 800  | 1500  |
| `.toml`                    | 200  | 500   |
| `.json`                    | 1000 | 3000  |
| Other                      | 500  | 1000  |

### Exclusions

Lock files (`*.lock`, `package-lock.json`, `Cargo.lock`, `uv.lock`), generated files (`*.generated.*`, `*.min.js`, `*.min.css`).

### Escape Hatch

Add `# FILE-SIZE-OK` comment anywhere in the file to suppress the warning.

### Configuration

Create `.claude/file-size-guard.json` (project-level) or `~/.claude/file-size-guard.json` (global):

```json
{
  "defaults": { "warn": 600, "block": 1200 },
  "extensions": { ".rs": { "warn": 400, "block": 800 } },
  "excludes": ["my-generated-file.ts"]
}
```

### Plan Mode

Automatically skipped when Claude is in planning phase.

## Language Policy

Per `lifecycle-reference.md`, **TypeScript/Bun is preferred** for new hooks:

- `sred-commit-guard.ts` - TypeScript (complex validation, educational feedback)
- Simple pattern matching - bash acceptable

## Vale Terminology Enforcement

The Vale terminology hooks enforce consistent terminology across all CLAUDE.md files.

### Architecture

```
~/.claude/docs/GLOSSARY.md  ◄──── SSoT (Single Source of Truth)
         │
         │ bidirectional sync via glossary-sync.ts
         ▼
~/.claude/.vale/styles/
  ├── config/vocabularies/TradingFitness/accept.txt
  └── TradingFitness/Terminology.yml
```

### Hook Chain (PreToolUse + PostToolUse)

**PreToolUse (REJECTS before edit)**:

1. **pretooluse-vale-claude-md-guard.ts** → Runs Vale on proposed content, REJECTS if issues found

**PostToolUse (informational after edit)**:

1. **posttooluse-vale-claude-md.ts** → Runs Vale, shows terminology violations (visibility only)
2. **posttooluse-glossary-sync.ts** → (if GLOSSARY.md changed) Updates Vale vocabulary
3. **posttooluse-terminology-sync.ts** → Syncs project terms to global GLOSSARY.md + duplicate detection

### Implementation Details (posttooluse-vale-claude-md.ts)

The PostToolUse Vale hook is **cwd-agnostic** and works from any directory:

1. **Config discovery**: Walks UP from the file's directory to find `.vale.ini`, falls back to `~/.claude/.vale.ini`
2. **Directory change**: Runs Vale from the file's directory so glob patterns like `[CLAUDE.md]` match
3. **ANSI stripping**: Removes color codes from Vale output for reliable regex parsing
4. **Summary parsing**: Extracts error/warning/suggestion counts from Vale's summary line

### PreToolUse vs PostToolUse

| Hook Type   | When             | Can Reject? | Use Case                         |
| ----------- | ---------------- | ----------- | -------------------------------- |
| PreToolUse  | BEFORE tool runs | YES         | Block bad edits                  |
| PostToolUse | AFTER tool runs  | NO          | Inform about issues (visibility) |

The PreToolUse hook uses `permissionDecision: "ask"` by default (shows dialog). Change MODE to `"deny"` for hard rejection.

> **Note**: glossary-sync runs before terminology-sync to ensure Vale vocabulary is current before terminology validation.

### Duplicate Detection

The terminology-sync hook scans ALL configured CLAUDE.md files and BLOCKS on conflicts:

| Conflict Type     | Example                                      | Action Required               |
| ----------------- | -------------------------------------------- | ----------------------------- |
| Definition        | "ITH" defined differently in 2 projects      | Consolidate to ONE definition |
| Acronym           | "ITH" vs "Investment-TH" for same term       | Standardize to ONE acronym    |
| Acronym collision | "CV" = "Coefficient of Variation" AND others | Rename one acronym            |

### Scan Configuration

Edit `~/.claude/docs/GLOSSARY.md` to configure scan paths:

```markdown
<!-- SCAN_PATHS:
- ~/eon/*/CLAUDE.md
- ~/eon/*/*/CLAUDE.md
- ~/.claude/docs/GLOSSARY.md
-->
```

## Skills

| Skill               | Purpose                                             |
| ------------------- | --------------------------------------------------- |
| `itp-hooks:setup`   | Check and install hook dependencies                 |
| `hooks-development` | Hook development reference (lifecycle-reference.md) |

## Pueue Reminder for Long-Running Tasks

The `posttooluse-reminder.ts` hook detects long-running tasks and suggests using [Pueue](https://github.com/Nukesor/pueue) for job orchestration.

### Why Pueue?

| Benefit                 | Description                                   |
| ----------------------- | --------------------------------------------- |
| SSH disconnect survival | Daemon runs independently of terminal session |
| Crash recovery          | Queue persisted to disk, auto-resumes         |
| Resource management     | Per-group parallelism limits                  |
| Easy restart            | `pueue restart <id>` for failed jobs          |

### Detection Patterns

The hook triggers on commands matching these patterns:

| Pattern                    | Example                                   |
| -------------------------- | ----------------------------------------- |
| `populate_cache` scripts   | `python populate_full_cache.py --phase 1` |
| `bulk_insert/load/import`  | `python bulk_insert_data.py`              |
| Symbol + threshold         | `--symbol BTCUSDT --threshold 250`        |
| Shell for/while loops      | `for symbol in ...; do ...; done`         |
| SSH with long-running cmds | `ssh bigblack 'python populate_cache.py'` |

### Exceptions (No Reminder)

- Already using `pueue add`
- Status/plan/help flags (`--status`, `--plan`, `--help`)
- Already backgrounded (`nohup`, `screen`, `tmux`, `&`)
- Documentation (`echo`, comments)

### Example Reminder

```
[PUEUE-REMINDER] Long-running task detected - consider using Pueue

EXECUTED: ssh bigblack 'python populate_cache.py --phase 1'
PREFERRED: ssh bigblack "~/.local/bin/pueue add -- python populate_cache.py --phase 1"

WHY PUEUE:
- Daemon survives SSH disconnects, crashes, reboots
- Queue persisted to disk - auto-resumes after failure
- Per-group parallelism limits (avoid resource exhaustion)
- Easy restart of failed jobs: pueue restart <id>
```

### Reference

- Issue: [rangebar-py#77](https://github.com/terrylica/rangebar-py/issues/77)
- Pueue: [github.com/Nukesor/pueue](https://github.com/Nukesor/pueue)

## Code Correctness Philosophy

The `code-correctness-guard.sh` hook checks **only for silent failure patterns** - code that fails without visible errors.

### What IS Checked (Runtime Bugs)

| Rule    | What It Catches                       | Why It Matters                        |
| ------- | ------------------------------------- | ------------------------------------- |
| E722    | Bare `except:`                        | Catches KeyboardInterrupt, hides bugs |
| S110    | `try-except-pass`                     | Silently swallows all errors          |
| S112    | `try-except-continue`                 | Silently skips loop iterations        |
| BLE001  | `except Exception`                    | Too broad, hides specific errors      |
| PLW1510 | `subprocess.run` without `check=True` | Command failures are silent           |

### What is NOT Checked (Cosmetic/Style)

| Rule | What It Would Check | Why It's Excluded                        |
| ---- | ------------------- | ---------------------------------------- |
| F401 | Unused imports      | Cosmetic; IDE/pre-commit responsibility  |
| F841 | Unused variables    | Cosmetic; no runtime impact              |
| I    | Import sorting      | Style preference                         |
| E/W  | PEP8 style          | Formatting; use `ruff format` separately |
| ANN  | Type annotations    | Handled by mypy/pyright, not hooks       |
| D    | Docstrings          | Documentation; not bugs                  |

### Justification for NOT Checking Unused Imports

1. **Development-in-progress**: Imports are often added before the code that uses them
2. **Intentional re-exports**: `__init__.py` imports symbols solely to re-export them
3. **Type-only imports**: `TYPE_CHECKING` blocks contain imports used only for type hints
4. **IDE responsibility**: Unused imports are best handled by IDE auto-remove features
5. **Low severity**: No runtime failures, security issues, or silent bugs
6. **Pre-commit/CI is better**: Catch in git hooks or CI, not interactive sessions

## References

- [lifecycle-reference.md](skills/hooks-development/references/lifecycle-reference.md) - Hook lifecycle and best practices
- [bootstrap-monorepo.md](../itp/skills/mise-tasks/references/bootstrap-monorepo.md) - SR&ED commit conventions section
