---
status: implemented
date: 2025-12-06
decision-maker: Terry Li
consulted: [claude-code-guide, Explore-Agent]
research-method: multi-agent
---

# ADR: PreToolUse and PostToolUse Hooks for Implementation Standards

**Design Spec**: [Implementation Spec](/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md)

## Context and Problem Statement

When Claude Code executes tools, there's no enforcement mechanism to prevent:

1. **Direct graph-easy CLI usage** without invoking the skill (leads to wrong `\n` escaping, missing `<details>` blocks)
2. **Manual ASCII art** in markdown files (misaligned diagrams, no reproducible source)
3. **ADR/Spec desynchronization** when one is modified without updating the other

These issues were discovered during the shell-command-portability ADR work where manual diagrams had alignment issues.

### Before/After

**Before**: No enforcement - manual diagrams and desync go unnoticed

```
Before: No Implementation Standards Enforcement

┌─────────────────────┐     ┌───────────────────────┐     ┌──────────────────┐
│   Claude executes   │     │   No validation or    │     │  Manual ASCII    │
│    Write/Edit/Bash  │ ──> │      reminders        │ ──> │  Desync issues   │
└─────────────────────┘     └───────────────────────┘     └──────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Before: No Implementation Standards Enforcement"; flow: east; }

[exec] { label: "Claude executes\\nWrite/Edit/Bash"; }
[no-check] { label: "No validation or\\nreminders"; }
[issues] { label: "Manual ASCII\\nDesync issues"; }

[exec] -> [no-check] -> [issues]
```

</details>

**After**: Hooks enforce standards and provide sync reminders

```
After: Hooks Enforce Standards

┌─────────────────────┐     ┌───────────────────────┐     ┌──────────────────┐
│   Claude executes   │     │   PreToolUse blocks   │     │  Clean diagrams  │
│    Write/Edit/Bash  │ ──> │  PostToolUse reminds  │ ──> │   Synced docs    │
└─────────────────────┘     └───────────────────────┘     └──────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "After: Hooks Enforce Standards"; flow: east; }

[exec] { label: "Claude executes\\nWrite/Edit/Bash"; }
[hooks] { label: "PreToolUse blocks\\nPostToolUse reminds"; }
[clean] { label: "Clean diagrams\\nSynced docs"; }

[exec] -> [hooks] -> [clean]
```

</details>

## Decision Drivers

- Manual ASCII diagrams created during ADR work had alignment issues
- ADR and Design Spec can get out of sync when only one is updated
- Code changes may not reference related ADRs (traceability gap)
- Need enforcement without blocking legitimate operations

## Considered Options

- **Option A**: Documentation-only guidelines (no enforcement)
- **Option B**: PreToolUse hooks to block violations
- **Option C**: PreToolUse + PostToolUse hooks (block + remind)

## Decision Outcome

Chosen option: **Option C (PreToolUse + PostToolUse)**, because:

1. PreToolUse can **block** dangerous patterns before they execute
2. PostToolUse can **remind** about sync without blocking operations
3. Bash + jq implementation is 2.5x faster than Python (~18ms vs ~46ms)
4. Consolidated architecture: 2 scripts instead of 3+ individual ones

## Architecture

```
Hooks Architecture

   ┌────────────────────────────┐
   │       hooks/hooks.json     │
   │     (Configuration)        │
   └────────────────────────────┘
     │
     │ defines
     ∨
   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
   ┃   pretooluse-guard.sh      ┃
   ┃   (Blocks violations)      ┃
   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
     │
     │ complements
     ∨
   ┌────────────────────────────┐
   │  posttooluse-reminder.sh   │
   │   (Sync reminders)         │
   └────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Hooks Architecture"; flow: south; }

[config] { label: "hooks/hooks.json\\n(Configuration)"; }
[guard] { label: "pretooluse-guard.sh\\n(Blocks violations)"; border: bold; }
[remind] { label: "posttooluse-reminder.sh\\n(Sync reminders)"; }

[config] -- defines --> [guard]
[guard] -- complements --> [remind]
```

</details>

## Consequences

### Positive

- Graph-easy skill usage enforced automatically
- Manual ASCII art blocked with clear guidance
- ADR↔Spec sync reminders on every modification
- Code→ADR traceability reminders for implementation files
- Fast execution (~18ms per hook)

### Negative

- Requires jq dependency (standard on most systems)
- Hooks loaded at session start (changes require restart)
- May produce false positives for legitimate box-drawing usage

## References

- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Shell Command Portability ADR](/docs/adr/2025-12-06-shell-command-portability-zsh.md) - Triggered this work
