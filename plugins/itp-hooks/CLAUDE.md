# itp-hooks Plugin

> Claude Code hooks for ITP workflow enforcement, code correctness, and commit validation.

## Overview

This plugin provides PreToolUse and PostToolUse hooks that enforce development standards, prevent common mistakes, and ensure compliance with project requirements.

## Hooks

### PreToolUse Hooks

| Hook                                 | Matcher           | Purpose                                           |
| ------------------------------------ | ----------------- | ------------------------------------------------- |
| `pretooluse-guard.sh`                | Write\|Edit       | Implementation standards enforcement              |
| `pretooluse-fake-data-guard.mjs`     | Write             | Prevents fake/placeholder data in production code |
| `pretooluse-version-guard.mjs`       | Write\|Edit       | Version consistency validation                    |
| `pretooluse-process-storm-guard.mjs` | Bash\|Write\|Edit | Prevents fork bomb patterns                       |
| `sred-commit-guard.ts`               | Bash              | SR&ED commit format enforcement                   |

### PostToolUse Hooks

| Hook                        | Matcher           | Purpose                                             |
| --------------------------- | ----------------- | --------------------------------------------------- |
| `posttooluse-reminder.sh`   | Bash\|Write\|Edit | Context-aware reminders                             |
| `code-correctness-guard.sh` | Bash\|Write\|Edit | Silent failure detection (ShellCheck, Ruff, Oxlint) |

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

## Skills

| Skill               | Purpose                                             |
| ------------------- | --------------------------------------------------- |
| `itp-hooks:setup`   | Check and install hook dependencies                 |
| `hooks-development` | Hook development reference (lifecycle-reference.md) |

## References

- [lifecycle-reference.md](skills/hooks-development/references/lifecycle-reference.md) - Hook lifecycle and best practices
- [bootstrap-monorepo.md](../itp/skills/mise-tasks/references/bootstrap-monorepo.md) - SR&ED commit conventions section
