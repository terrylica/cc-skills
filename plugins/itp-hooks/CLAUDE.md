# itp-hooks Plugin

> Claude Code hooks for ITP workflow enforcement, code correctness, and commit validation.

## Overview

This plugin provides PreToolUse and PostToolUse hooks that enforce development standards, prevent common mistakes, and ensure compliance with project requirements.

## Hooks

### PreToolUse Hooks

| Hook                                        | Matcher           | Purpose                                           |
| ------------------------------------------- | ----------------- | ------------------------------------------------- |
| `pretooluse-guard.sh`                       | Write\|Edit       | Implementation standards enforcement              |
| `pretooluse-fake-data-guard.mjs`            | Write             | Prevents fake/placeholder data in production code |
| `pretooluse-time-weighted-sharpe-guard.mjs` | Write\|Edit       | Time-weighted Sharpe ratio enforcement            |
| `pretooluse-version-guard.mjs`              | Write\|Edit       | Version consistency validation                    |
| `pretooluse-process-storm-guard.mjs`        | Bash\|Write\|Edit | Prevents fork bomb patterns                       |
| `pretooluse-vale-claude-md-guard.ts`        | Write\|Edit       | **Rejects** CLAUDE.md edits with Vale violations  |
| `pretooluse-hoisted-deps-guard.mjs`         | Write\|Edit       | pyproject.toml root-only and path escape policies |
| `pretooluse-gpu-optimization-guard.ts`      | Write\|Edit       | GPU optimization enforcement (AMP, batch sizing)  |
| `sred-commit-guard.ts`                      | Bash              | SR&ED commit format enforcement                   |

### PostToolUse Hooks

| Hook                                            | Matcher           | Purpose                                                     |
| ----------------------------------------------- | ----------------- | ----------------------------------------------------------- |
| `posttooluse-reminder.ts`                       | Bash\|Write\|Edit | Context-aware reminders (UV, graph-easy, ADR sync)          |
| `code-correctness-guard.sh`                     | Bash\|Write\|Edit | Silent failure detection only (NO unused imports, NO style) |
| `posttooluse-time-weighted-sharpe-reminder.mjs` | Write\|Edit       | Time-weighted Sharpe ratio monitoring                       |
| `posttooluse-vale-claude-md.ts`                 | Write\|Edit       | Vale terminology check on CLAUDE.md files                   |
| `posttooluse-glossary-sync.ts`                  | Write\|Edit       | Auto-sync GLOSSARY.md to Vale vocabulary                    |
| `posttooluse-terminology-sync.ts`               | Write\|Edit       | Project CLAUDE.md to global GLOSSARY.md sync                |

### UserPromptSubmit Hooks

| Hook                                  | Matcher | Purpose                              |
| ------------------------------------- | ------- | ------------------------------------ |
| `userpromptsubmit-sharpe-context.mjs` | (all)   | Injects time-weighted Sharpe context |

### Stop Hooks

| Hook                                  | Matcher | Purpose                        |
| ------------------------------------- | ------- | ------------------------------ |
| `stop-time-weighted-sharpe-audit.mjs` | (all)   | Session-end Sharpe ratio audit |

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
