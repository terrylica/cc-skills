---
status: accepted
date: 2025-12-11
decision-maker: terrylica
consulted: [Claude Opus 4.5]
research-method: single-agent
clarification-iterations: 3
perspectives: [enforcement, developer-experience, performance]
---

# Ruff PostToolUse Linting

**Design Spec**: [Implementation Spec](/docs/design/2025-12-11-ruff-posttooluse-linting/spec.md)

## Context and Problem Statement

AI coding agents often hallucinate during implementation - they don't follow error handling principles, use outdated syntax, or introduce common bugs. The existing `impl-standards` skill relies on Claude's memory to enforce standards, which is not deterministic.

How can we enforce Python coding standards deterministically without relying on Claude's memory?

### Before State

```
                        ⏮️ Before: No Code Quality Checks

╭───────────────╮     ┌─────────────┐     ┌──────────────┐     ┌⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┐
│ Claude writes │     │ PostToolUse │     │ ADR reminder │     ⋮ Silent failures ⋮
│  Python code  │ ──> │    Hook     │ ──> │     only     │ ──> ⋮    possible     ⋮
╰───────────────╯     └─────────────┘     └──────────────┘     └⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯⋯┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: No Code Quality Checks"; flow: east; }
[ Claude writes\nPython code ] { shape: rounded; } -> [ PostToolUse\nHook ] -> [ ADR reminder\nonly ]
[ ADR reminder\nonly ] -> [ Silent failures\npossible ] { border: dotted; }
```

</details>

### After State

```
                               ⏭️ After: Ruff Linting Integrated

╭───────────────╮     ┌─────────────┐     ┌──────────────┐     ┌───────────┐     ╭──────────────╮
│ Claude writes │     │ PostToolUse │     │ Ruff linting │     │ Warnings  │     │ Claude fixes │
│  Python code  │ ──> │    Hook     │ ──> │ 9 categories │ ──> │ displayed │ ──> │    issues    │
╰───────────────╯     └─────────────┘     └──────────────┘     └───────────┘     ╰──────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Ruff Linting Integrated"; flow: east; }
[ Claude writes\nPython code ] { shape: rounded; } -> [ PostToolUse\nHook ] -> [ Ruff linting\n9 categories ]
[ Ruff linting\n9 categories ] -> [ Warnings\ndisplayed ] -> [ Claude fixes\nissues ] { shape: rounded; }
```

</details>

## Decision Drivers

- **Deterministic enforcement**: Static analysis vs relying on memory
- **Speed**: Must not slow down Claude's workflow (<100ms)
- **Comprehensive coverage**: Error handling, modern syntax, common bugs
- **Non-blocking**: Warnings only, Claude decides what to fix

## Considered Options

1. **Ruff only** - Fast, comprehensive, Rust-based
2. **Ruff + Pylint** - Ruff for speed, Pylint for W0707 (exception chaining)
3. **Semgrep** - Custom YAML rules for organization-specific patterns

## Decision Outcome

**Chosen option**: "Ruff only" with comprehensive rule set (warnings only, no auto-fix).

### Rationale

- **Speed**: Ruff is 10-100x faster than Pylint
- **Coverage**: 9 rule categories cover error handling + idiomatic Python
- **Simplicity**: Single tool, no custom rules to maintain
- **Non-invasive**: Warnings only - Claude sees issues and decides

### Rule Categories Enabled

| Category       | Code   | What It Catches                       |
| -------------- | ------ | ------------------------------------- |
| Error Handling | `BLE`  | Blind except (`except Exception:`)    |
| Error Handling | `S110` | try-except-pass (silent failures)     |
| Error Handling | `E722` | Bare `except:` without type           |
| Pyflakes       | `F`    | Unused imports, undefined names       |
| Pyupgrade      | `UP`   | Outdated syntax (`Union` → `\|`)      |
| Simplify       | `SIM`  | Unnecessary else, complex expressions |
| Bugbear        | `B`    | Mutable default args                  |
| Isort          | `I`    | Import ordering                       |
| Ruff-specific  | `RUF`  | Unused noqa, etc.                     |

## Architecture

```
         🏗️ PostToolUse Hook Architecture

                          ╭───────────────────────╮
                          │      PostToolUse      │
                          │      Hook Entry       │
                          ╰───────────────────────╯
                            │
                            │
                            ∨
┌──────────────┐          ┌───────────────────────┐
│ ADR reminder │  other   │      Check file       │
│     only     │ <─────── │       extension       │
└──────────────┘          └───────────────────────┘
  │                         │
  │                         │ .py
  │                         ∨
  │                       ┌───────────────────────┐
  │                       │       Run Ruff        │
  │                       │ --select BLE,S110,... │
  │                       └───────────────────────┘
  │                         │
  │                         │
  │                         ∨
  │                       ┌───────────────────────┐
  │                       │    Output warnings    │
  │                       │       to Claude       │
  │                       └───────────────────────┘
  │                         │
  │                         │
  │                         ∨
  │                       ╭───────────────────────╮
  └─────────────────────> │        Exit 0         │
                          ╰───────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ PostToolUse Hook Architecture"; flow: south; }
[ PostToolUse\nHook Entry ] { shape: rounded; } -> [ Check file\nextension ]
[ Check file\nextension ] -- .py --> [ Run Ruff\n--select BLE,S110,... ]
[ Check file\nextension ] -- other --> [ ADR reminder\nonly ]
[ Run Ruff\n--select BLE,S110,... ] -> [ Output warnings\nto Claude ]
[ ADR reminder\nonly ] -> [ Exit 0 ] { shape: rounded; }
[ Output warnings\nto Claude ] -> [ Exit 0 ]
```

</details>

## Consequences

### Positive

- Deterministic: Same violations always detected
- Fast: Ruff runs in <100ms
- Educational: Claude learns from warnings
- Non-invasive: No auto-fix, Claude maintains control

### Negative

- Pylint W0707 (exception chaining) not covered
- May generate noise on legacy code
- Requires Ruff installed in environment

### Neutral

- `impl-standards` skill remains for "what to do" guidance
- Hook provides "what not to do" enforcement

## Related Decisions

- [ADR: Shell Command Portability](/docs/adr/2025-12-06-shell-command-portability-zsh.md)
- GitHub Actions No Testing Policy (documented in global `~/.claude/CLAUDE.md`)

## Notes

Research conducted via DCTL agents examining Ruff, Pylint, Semgrep, and Bandit. Key finding: Bandit B110 is superseded by Ruff S110 (same check, 10-100x faster).
