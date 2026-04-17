# itp-hooks Plugin

> Claude Code hooks for ITP workflow enforcement, code correctness, and commit validation.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gh-tools CLAUDE.md](../gh-tools/CLAUDE.md)

## Overview

This plugin provides PreToolUse and PostToolUse hooks that enforce development standards, prevent common mistakes, and ensure compliance with project requirements.

## Hooks

### PreToolUse Hooks

| Hook                                   | Matcher           | Purpose                                                                                                                                                                                                      |
| -------------------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pretooluse-fake-data-guard.mjs`       | Write             | Prevents fake/placeholder data in production code                                                                                                                                                            |
| `pretooluse-version-guard.mjs`         | Write\|Edit       | Version consistency validation                                                                                                                                                                               |
| `pretooluse-process-storm-guard.mjs`   | Bash\|Write\|Edit | Prevents fork bomb patterns                                                                                                                                                                                  |
| `pretooluse-cwd-deletion-guard.ts`     | Bash              | Prevents deleting the current working directory                                                                                                                                                              |
| `pretooluse-vale-claude-md-guard.ts`   | Write\|Edit       | **Rejects** CLAUDE.md edits with Vale violations                                                                                                                                                             |
| `pretooluse-hoisted-deps-guard.mjs`    | Write\|Edit       | pyproject.toml root-only and path escape policies                                                                                                                                                            |
| `pretooluse-gpu-optimization-guard.ts` | Write\|Edit       | GPU optimization enforcement (AMP, batch sizing)                                                                                                                                                             |
| `pretooluse-mise-hygiene-guard.ts`     | Write\|Edit       | mise.toml hygiene (line limit, secrets detection)                                                                                                                                                            |
| `pretooluse-file-size-guard.ts`        | Write\|Edit       | File size bloat prevention (per-extension limits)                                                                                                                                                            |
| `pretooluse-native-binary-guard.ts`    | Write\|Edit       | Enforces compiled Swift binaries for launchd (no bash scripts)                                                                                                                                               |
| `pretooluse-pyi-stub-guard.ts`         | Write\|Edit       | Validates `.pyi` stub files match source signatures                                                                                                                                                          |
| `pretooluse-inline-ignore-guard.ts`    | Write\|Edit       | Blocks inline ignore comments (`# noqa`, `# type: ignore`, `// eslint-disable`, `// biome-ignore`, `// oxlint-ignore`) — enforces config-level suppression                                                   |
| `pretooluse-uv-enforcement-guard.ts`   | Bash              | Blocks non-UV Python package operations (pip, conda, pipx, virtualenv)                                                                                                                                       |
| `pretooluse-pueue-local-guard.ts`      | Bash              | Ensures pueue commands target local daemon (not remote)                                                                                                                                                      |
| `pretooluse-cargo-tty-guard.ts`        | Bash              | **Cargo TTY suspension prevention** — Redirects `cargo bench/test/build &` to PUEUE daemon (eliminates stdin inheritance, prevents SIGSTOP). See [Full Guide](../../docs/cargo-tty-suspension-prevention.md) |
| `pretooluse-pueue-wrap-guard.ts`       | Bash              | Auto-wraps long-running commands with pueue + injects OP_SERVICE_ACCOUNT_TOKEN for Claude Automation vault (MUST be LAST PreToolUse entry)                                                                   |

> **Note**: `sred-commit-guard.ts` was migrated from a PreToolUse hook to the `/mise:sred-commit` slash command. The script remains for CLI validation (`--validate-message`, `--git-hook`).

### PostToolUse Hooks

| Hook                               | Matcher                | Purpose                                                                                   |
| ---------------------------------- | ---------------------- | ----------------------------------------------------------------------------------------- |
| `posttooluse-reminder.ts`          | Bash\|Write\|Edit      | Context-aware reminders (UV, Pueue, graph-easy, ADR sync)                                 |
| `code-correctness-guard.sh`        | Bash\|Write\|Edit      | Silent failure detection only (NO unused imports, NO style)                               |
| `posttooluse-vale-claude-md.ts`    | Write\|Edit            | Vale terminology check on CLAUDE.md files                                                 |
| `posttooluse-glossary-sync.ts`     | Write\|Edit            | Auto-sync GLOSSARY.md to Vale vocabulary                                                  |
| `posttooluse-terminology-sync.ts`  | Write\|Edit            | Project CLAUDE.md to global GLOSSARY.md sync                                              |
| `posttooluse-readme-pypi-links.ts` | Write\|Edit\|MultiEdit | Validates PyPI badge/link consistency in README files                                     |
| `posttooluse-ssot-principles.ts`   | Write\|Edit            | SSoT/DI principles with ast-grep detection (once per session)                             |
| `posttooluse-ty-type-check.ts`     | Write\|Edit            | ty type checker on .py/.pyi files with --python-version 3.13, concise output (every edit) |
| `posttooluse-tsgo-type-check.ts`   | Write\|Edit            | tsgo type checker on .ts/.tsx files (~170ms project check, every edit)                    |
| `posttooluse-oxlint-check.ts`      | Write\|Edit            | oxlint correctness+suspicious lint on JS/TS files (~50ms, every edit)                     |
| `posttooluse-biome-lint.ts`        | Write\|Edit            | biome complementary lint on JS/TS (useConst, noDoubleEquals, node: protocol)              |

### Stop Hooks

| Hook                         | Purpose                                                                                   |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `stop-hook-error-summary.ts` | Summarizes hook errors from the session on Claude exit                                    |
| `stop-ty-project-check.ts`   | Project-wide ty type check on exit (only if .py files were edited, --python-version 3.13) |

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

The `pretooluse-file-size-guard.ts` hook prevents single-file bloat by checking line count before Write/Edit operations. Uses tiered approach: warn via PostToolUse (soft notification), block via `deny` (hard block with guidance) at the block threshold.

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

The PreToolUse hook uses `permissionDecision: "deny"` (hard rejection). Change MODE to `"ask"` for a permission dialog instead.

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

- [hooks-development](./skills/hooks-development/SKILL.md)
- [setup](./skills/setup/SKILL.md)

## Environment Variables (Hook Context)

These variables are **set by Claude Code** when a hook fires — hooks read them, not users. Document them here so hook authors know the contract.

| Variable                 | Source               | Description                                                                                       |
| ------------------------ | -------------------- | ------------------------------------------------------------------------------------------------- |
| `CLAUDE_SESSION_ID`      | Claude Code runtime  | UUID of the current session; used for per-session gate files and session-scoped caches            |
| `CLAUDE_CONVERSATION_ID` | Claude Code runtime  | Conversation UUID (alias surfaced by some hook events)                                            |
| `CLAUDE_PROJECT_DIR`     | Claude Code runtime  | Absolute path to the project root Claude is working in; used to resolve `.claude/` config files   |
| `CLAUDE_HOOK_SPAWNED`    | set by hook wrappers | Set to `1` when a hook is running via a wrapper process; guards against recursive hook invocation |

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

## Native Binary Guard (macOS Launchd)

The `pretooluse-native-binary-guard.ts` hook enforces that all macOS launchd services use compiled native binaries (Swift preferred), never bash scripts.

### Why

Using `/bin/bash` in launchd plists shows a generic "bash" entry in System Settings > Login Items, which looks like unidentified malware. Compiled Swift binaries show their actual executable name (e.g., "calendar-announce").

### Detections

| Pattern                              | Example                               | Decision            |
| ------------------------------------ | ------------------------------------- | ------------------- |
| `.sh`/`.bash` file in automation dir | `~/.claude/automation/foo/run.sh`     | **DENY**            |
| `.plist` with `/bin/bash`            | `<string>/bin/bash</string>`          | **DENY**            |
| `.plist` with `.sh` script path      | `<string>/path/to/script.sh</string>` | **DENY**            |
| `.swift` file in automation dir      | `~/.claude/automation/foo/Main.swift` | ALLOW               |
| `.plist` with compiled binary        | `<string>/path/to/binary</string>`    | ALLOW               |
| Any file outside automation dirs     | `~/eon/project/script.sh`             | ALLOW (not checked) |

### Scope (Narrow)

Only triggers for files in these directories:

- `~/.claude/automation/`
- `~/Library/LaunchAgents/`
- `~/Library/LaunchDaemons/`

### Performance

Uses a **raw-stdin fast path**: checks for launchd-related keywords (`.plist`, `.sh`, `LaunchAgent`, `automation/`) in the raw stdin string BEFORE JSON parsing. For 99%+ of Write/Edit calls (normal code files), exits in <1ms without parsing JSON.

### Required Pattern

```bash
# 1. Write logic in Swift
vim ~/.claude/automation/my-tool/swift-cli/MyTool.swift

# 2. Compile to native binary
swiftc -O -framework EventKit -o my-tool MyTool.swift

# 3. Reference binary directly in plist (NOT /bin/bash)
# <string>$HOME/.claude/automation/my-tool/swift-cli/my-tool</string>
```

### TypeScript Services: Swift Runner + `bun --watch`

For TypeScript/Bun services (bots, sync daemons), the Swift binary acts as a thin launcher that delegates to `bun --watch run`. This gives you:

- **Launchd compliance**: Named binary in Login Items (not "bash")
- **Auto-restart on code changes**: `bun --watch` uses kqueue (macOS native, zero overhead) to restart the process when any `.ts` file changes — no manual kills needed
- **Clean process tree**: launchd → Swift runner → `bun --watch` → TypeScript service

```swift
// Runner binary (compile with: swiftc -O -o my-bot my-bot-runner.swift)
process.arguments = ["--watch", "run", scriptPath]
```

| Service type                       | Launchd binary      | Runtime                       |
| ---------------------------------- | ------------------- | ----------------------------- |
| System integration (EventKit, TCC) | Swift (full logic)  | Native                        |
| TypeScript bot/daemon              | Swift (thin runner) | `bun --watch run src/main.ts` |

**Anti-pattern**: `bun --hot` for long-running services (stale module state across reloads). Use `--watch` (full process restart).

Reference: `~/.claude/automation/claude-telegram-sync/telegram-bot-runner.swift`

### Escape Hatch

Add `# BASH-LAUNCHD-OK` (in scripts) or `<!-- BASH-LAUNCHD-OK -->` (in plists) to bypass.

### TCC Anti-Pattern: Duplicate EventKit Access

**Problem**: Each compiled Swift binary that imports EventKit triggers a separate macOS TCC prompt ("Would Like Full Access to Your Calendar"). Multiple binaries = multiple manual approval dialogs.

**Fix**: Designate ONE binary as the EventKit reader (e.g., `calendar-event-reader`). Other binaries call it as a subprocess and parse its JSON stdout. Only the reader needs the TCC grant.

| Pattern                                    | TCC Prompts | Approach     |
| ------------------------------------------ | ----------- | ------------ |
| 3 binaries each import EventKit            | 3 prompts   | Anti-pattern |
| 1 reader binary + 2 callers via subprocess | 1 prompt    | Correct      |

### TCC Anti-Pattern: Subprocess Credential Access

**Problem**: A launchd Swift binary that spawns `op` (1Password CLI) as a subprocess on every run triggers the macOS TCC prompt "would like to access data from other apps" — even though the binary is compiled Swift. **Compiled language does NOT bypass TCC. TCC is based on what the binary does at runtime, not what language it's written in.**

**Context**: The `gmail-oauth-token-hourly-refresher` runs hourly to refresh OAuth access tokens. It originally called `op item get` on every run to fetch OAuth app credentials (`client_id`/`client_secret`) from 1Password.

**Fix**: Cache static credentials locally on first run. Subsequent runs read from local cache files only — no subprocess spawning, no TCC prompt.

```swift
// Cache file: ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
// Check cache first; fall back to `op` only when cache is missing

if cacheExists && cacheValid {
    clientId = cache["client_id"]       // Local file read — no TCC
    clientSecret = cache["client_secret"]
} else {
    // One-time 1Password fetch → TCC prompt appears ONCE
    fetchFromOP() → writeCache()        // All future runs skip this branch
}
```

**When to apply**: Any binary that fetches the same static credentials (OAuth app credentials, API keys, etc.) on every invocation. Dynamic credentials (tokens, session keys) cannot be cached and must be fetched fresh — but those typically live in local files already.

**To force re-fetch** (e.g., after rotating credentials in 1Password):

```bash
rm ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
```

| Pattern                                    | TCC Prompts      | Approach     |
| ------------------------------------------ | ---------------- | ------------ |
| Call `op` on every hourly run              | Every run        | Anti-pattern |
| Cache static creds, call `op` only on miss | Once (first run) | Correct      |

### Reference

- Examples: `~/.claude/automation/calendar-alarm-sweep/swift-cli/` (CalendarAnnounce.swift, CalendarAlarmSweep.swift)
- Credential caching: `~/.claude/automation/gmail-token-refresher/main.swift`

## Inline Ignore Policy

The `pretooluse-inline-ignore-guard.ts` (PreToolUse) blocks new inline ignore comments, and `code-correctness-guard.sh` (PostToolUse) warns about existing ones.

### Hierarchy (Enforced)

1. **FIX THE ERROR** (preferred) — add type annotations, casts, None checks, `__all__` for re-exports
2. **CONFIG-LEVEL IGNORE** (only for tool/library limitations):
   - ruff: `[lint.per-file-ignores]` in `ruff.toml`
   - ty: `[[overrides]]` in `ty.toml` with `include` pattern
   - oxlint: `.oxlintrc.json` rules section
   - biome: `biome.json` linter.rules section
3. **NEVER**: Inline `# noqa` / `# type: ignore` / `// eslint-disable`

### Detection Patterns

| Language        | Patterns Detected                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Python (.py)    | `# noqa`, `# noqa: XXX`, `# type: ignore`, `# type: ignore[xxx]`, `# ty: ignore`, `# ty: ignore[xxx]`                  |
| JS/TS (.ts etc) | `// eslint-disable-next-line`, `// eslint-disable-line`, `/* eslint-disable */`, `// biome-ignore`, `// oxlint-ignore` |

### Enforcement

| Hook              | Event       | Behavior                                                |
| ----------------- | ----------- | ------------------------------------------------------- |
| PreToolUse guard  | Write\|Edit | **DENY** if proposed content introduces new ignores     |
| PostToolUse audit | Write\|Edit | **WARN** about existing inline ignores (full-file scan) |

For Edit: only denies if `new_string` has more ignores than `old_string` (net-new detection).

### Escape Hatch

Add `# INLINE-IGNORE-OK` or `// INLINE-IGNORE-OK` on the same line:

```python
import pysbd  # type: ignore[import]  # INLINE-IGNORE-OK
```

## Code Correctness Philosophy

The `code-correctness-guard.sh` hook checks **only for silent failure patterns** - code that fails without visible errors.

### What IS Checked (Runtime Bugs)

| Rule    | What It Catches                       | Why It Matters                        |
| ------- | ------------------------------------- | ------------------------------------- |
| E722    | Bare `except:`                        | Catches KeyboardInterrupt, hides bugs |
| S110    | `try-except-pass`                     | Silently swallows all errors          |
| S112    | `try-except-continue`                 | Silently skips loop iterations        |
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

## ty Type Checker Configuration

ty runs at two levels: **per-file** on every .py/.pyi edit (PostToolUse) and **project-wide** on session exit (Stop hook). Both always pass `--python-version 3.13` explicitly to override ty's default of Python 3.14.

### Recommended ty.toml

Projects using ty should also pin the version in `ty.toml` for consistency when running ty manually:

```toml
[environment]
python-version = "3.13"

[terminal]
output-format = "concise"
```

The hooks pass `--python-version 3.13` explicitly regardless of `ty.toml`, but having the config ensures manual `ty check` runs also use 3.13.

### Silent Failures Only

The hooks never block on ty configuration errors (exit code 2) or internal bugs (exit code 101). These are treated as ty issues, not type errors, and the hook exits silently. Only actual type diagnostics trigger a block/context message.

### Gate File Mechanism

The PostToolUse hook writes a gate file to `/tmp/.claude-ty-edits/{sessionId}.edited` after each .py/.pyi edit. The Stop hook checks for these gate files to decide whether to run the project-wide check. Gate files are cleaned up after the Stop hook runs.

## LSP Configuration

**Status**: DISABLED (2026-01-12) - pyright-langserver caused process storms.

### To Disable LSP (all three required)

```bash
# 1. Environment variable
grep ENABLE_LSP_TOOL ~/.zshenv  # Should show: export ENABLE_LSP_TOOL=0

# 2. Config file
ls ~/.claude/cclsp-config.json  # Should not exist (or .disabled)

# 3. Plugin setting
grep pyright-lsp ~/.claude/settings.json  # Should show: false
```

### To Re-enable LSP

```bash
# 1. ~/.zshenv
export ENABLE_LSP_TOOL=1

# 2. Restore config (if needed)
mv ~/.claude/cclsp-config.json.disabled ~/.claude/cclsp-config.json

# 3. ~/.claude/settings.json
"pyright-lsp@claude-plugins-official": true
```

**Verify**: `ps aux | grep -c '[p]yright'` (should be 0 when disabled)

## Cargo TTY Suspension Prevention (2026-02-23)

**Problem**: Running `cargo bench` or `cargo test` with backgrounding (`&`) in Claude Code causes immediate suspension with `suspended (tty input)`.

**Root Cause**: Cargo spawns subprocesses that inherit stdin. When backgrounded, TTY contention triggers SIGSTOP.

**Solution**: `pretooluse-cargo-tty-guard.ts` hook automatically redirects to PUEUE daemon (process-isolated, no stdin inheritance).

### Usage

**Automatic (default)**:

```bash
cargo bench --bench rangebar_bench &
# 🛡️ Cargo TTY Guard: Redirecting to PUEUE daemon
# ✓ PUEUE task 42 completed
```

**Override (opt-out)**:

```bash
cargo bench & # CARGO-TTY-SKIP
```

**Force (opt-in)**:

```bash
cargo bench # CARGO-TTY-WRAP
```

**Full Documentation**: [cargo-tty-suspension-prevention.md](../../docs/cargo-tty-suspension-prevention.md)

### Related GitHub Issues

- [#11898](https://github.com/anthropics/claude-code/issues/11898): TTY suspension on iTerm2
- [#12507](https://github.com/anthropics/claude-code/issues/12507): Subprocess stdin inheritance
- [#13598](https://github.com/anthropics/claude-code/issues/13598): Spurious /dev/tty reader

## SSoT/Dependency Injection Principles Hook

The `posttooluse-ssot-principles.ts` hook reminds Claude of SSoT/DI best practices on the first code edit per session, with ast-grep AST-based detection of anti-patterns.

### How It Works

1. Triggers on Write/Edit of code files (`.py`, `.ts`, `.rs`, `.go`, `.java`, `.kt`, `.rb`)
2. Skips test files (`test_*`, `*_test.*`, `*_spec.*`, `__tests__/`)
3. Gates once per session via atomic file in `/tmp/.claude-ssot-reminder/`
4. Runs ast-grep with rules from `hooks/ast-grep-ssot/` for AST-based detection
5. Outputs SSoT principles + any detected anti-patterns

### ast-grep Rules (9 rules, 4 languages)

| Language   | Rules | Detections                                                        |
| ---------- | ----- | ----------------------------------------------------------------- |
| Python     | 3     | Hardcoded string/int defaults, direct `os.environ`/`os.getenv`    |
| TypeScript | 2     | Hardcoded string defaults, direct `process.env` access            |
| Rust       | 2     | Direct `env::var`, hardcoded `unwrap_or` fallbacks                |
| Go         | 2     | Direct `os.Getenv`/`os.LookupEnv`, hardcoded `flag.*Var` defaults |

Rules location: `hooks/ast-grep-ssot/rules/` | Test: `cd hooks/ast-grep-ssot && ast-grep test`

### Escape Hatch

Add `# SSoT-OK` (or `// SSoT-OK`) comment to suppress findings. Same convention as `pretooluse-version-guard.mjs`.

### GitHub Issue

[#28](https://github.com/terrylica/cc-skills/issues/28)

## References

- [lifecycle-reference.md](skills/hooks-development/references/lifecycle-reference.md) - Hook lifecycle and best practices
- [bootstrap-monorepo.md](../itp/skills/mise-tasks/references/bootstrap-monorepo.md) - SR&ED commit conventions section
