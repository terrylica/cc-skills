---
status: accepted
date: 2026-02-05
decision-maker: Terry Li
consulted:
  - Claude Code Guide Agent (hook input structure)
  - Explore Agent (existing plan exemption patterns)
research-method: multi-agent
clarification-iterations: 1
perspectives: [Workflow Continuity, Developer Experience, Extensibility]
---

# Plan Mode Detection in PreToolUse Hooks

## Context and Problem Statement

PreToolUse hooks enforce code quality rules (version SSoT, ASCII diagrams, secrets detection) that are valuable for production code but disruptive during Claude Code's planning phase. When Claude enters plan mode via `EnterPlanMode`, it writes plan files and explores the codebase. Blocking these operations with validation hooks creates a poor developer experience:

1. Plan files get blocked by version-guard when they contain example version strings
2. Plan files get blocked by ASCII diagram enforcement when containing tables
3. Users must manually add escape hatches (`# SSoT-OK`) to ephemeral plan files

The previous solution (ADR 2025-12-09) used path-based exemptions for `/plans/*.md` files. This approach has limitations:

- Only exempts files in plan directories, not plan mode itself
- Doesn't help when Claude writes to non-plan files during planning exploration
- Requires each hook to implement its own path matching

## Decision Drivers

- **Workflow continuity**: Planning should flow without enforcement interruptions
- **Centralized detection**: Single utility for all hooks to use
- **Multiple signals**: Combine permission_mode, file paths, and active plan detection
- **Extensibility**: Easy to add new detection signals as Claude Code evolves
- **Fail-safe**: If detection fails, default to allowing (fail-open)

## Considered Options

1. **Path-based exemption only** (status quo): Each hook checks `/plans/` paths
2. **permission_mode detection only**: Check `permission_mode: "plan"` in hook input
3. **Multi-signal detection utility**: Combine permission_mode + path patterns + active plan files
4. **Environment variable from Claude Code**: Request Claude Code team add explicit signal

## Decision Outcome

**Chosen option**: "Multi-signal detection utility" - Create a shared `plan-mode-detector.ts` utility that hooks can import to detect plan mode through multiple signals.

### Detection Signals (Priority Order)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Plan Mode Detection                          │
├─────────────────────────────────────────────────────────────────┤
│  Signal 1 (Primary): permission_mode === "plan"                 │
│  ─────────────────────────────────────────────────────────────  │
│  Most reliable. Set by Claude Code when EnterPlanMode active.   │
│                                                                 │
│  Signal 2 (Secondary): file_path matches /plans/*.md            │
│  ─────────────────────────────────────────────────────────────  │
│  Catches writes to plan directories even if permission_mode     │
│  not set (edge cases, backward compatibility).                  │
│                                                                 │
│  Signal 3 (Tertiary): ~/.claude/plans/ has active files         │
│  ─────────────────────────────────────────────────────────────  │
│  Expensive (filesystem check). Disabled by default.             │
│  Useful for debugging or when other signals unavailable.        │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { flow: south; }
[ Plan Mode Detection ] { class: title; }
[ Signal 1 (Primary): permission_mode === "plan"\n─────────────────────────────────────────────────────────────\nMost reliable. Set by Claude Code when EnterPlanMode active. ]
[ Signal 2 (Secondary): file_path matches /plans/*.md\n─────────────────────────────────────────────────────────────\nCatches writes to plan directories even if permission_mode\nnot set (edge cases, backward compatibility). ]
[ Signal 3 (Tertiary): ~/.claude/plans/ has active files\n─────────────────────────────────────────────────────────────\nExpensive (filesystem check). Disabled by default.\nUseful for debugging or when other signals unavailable. ]

[ Plan Mode Detection ] -> [ Signal 1 (Primary): permission_mode === "plan"\n─────────────────────────────────────────────────────────────\nMost reliable. Set by Claude Code when EnterPlanMode active. ]
[ Signal 1 (Primary): permission_mode === "plan"\n─────────────────────────────────────────────────────────────\nMost reliable. Set by Claude Code when EnterPlanMode active. ] -> [ Signal 2 (Secondary): file_path matches /plans/*.md\n─────────────────────────────────────────────────────────────\nCatches writes to plan directories even if permission_mode\nnot set (edge cases, backward compatibility). ]
[ Signal 2 (Secondary): file_path matches /plans/*.md\n─────────────────────────────────────────────────────────────\nCatches writes to plan directories even if permission_mode\nnot set (edge cases, backward compatibility). ] -> [ Signal 3 (Tertiary): ~/.claude/plans/ has active files\n─────────────────────────────────────────────────────────────\nExpensive (filesystem check). Disabled by default.\nUseful for debugging or when other signals unavailable. ]
```

</details>

### Implementation

**New files**:

- `plugins/itp-hooks/hooks/lib/plan-mode-detector.ts` - Detection utility
- `docs/adr/2026-02-05-plan-mode-detection-hooks.md` - This ADR

**Modified files**:

- `plugins/itp-hooks/hooks/pretooluse-helpers.ts` - Extended input types, re-exports
- `plugins/itp-hooks/hooks/pretooluse-version-guard.mjs` - Uses plan mode detection
- `plugins/itp-hooks/hooks/pretooluse-mise-hygiene-guard.ts` - Uses plan mode detection

### API

```typescript
import { isPlanMode, isQuickPlanMode } from "./pretooluse-helpers.ts";

// Full detection with context
const ctx = isPlanMode(input, {
  checkPermission: true, // Check permission_mode (default: true)
  checkPath: true, // Check file path patterns (default: true)
  checkActiveFiles: false, // Check ~/.claude/plans/ (default: false, expensive)
});

if (ctx.inPlanMode) {
  logger.debug("Skipping check", { reason: ctx.reason });
  return allow();
}

// Quick boolean check (primary signals only)
if (isQuickPlanMode(input)) {
  return allow();
}
```

### Hook Input Fields

Claude Code provides these fields in hook input JSON:

| Field             | Type                                                                       | Description                              |
| ----------------- | -------------------------------------------------------------------------- | ---------------------------------------- |
| `permission_mode` | `"default" \| "plan" \| "acceptEdits" \| "dontAsk" \| "bypassPermissions"` | Current permission mode                  |
| `session_id`      | `string`                                                                   | Session identifier for state tracking    |
| `transcript_path` | `string`                                                                   | Path to conversation transcript JSONL    |
| `hook_event_name` | `string`                                                                   | Always "PreToolUse" for PreToolUse hooks |

### Consequences

**Good**:

- Plan mode edits flow without blocking
- Centralized detection logic - update once, all hooks benefit
- Detailed context for debugging (`PlanModeContext.reason`)
- Backward compatible - hooks that don't use it work unchanged
- Extensible - easy to add new signals

**Neutral**:

- Small overhead for plan mode check (~1ms)
- Additional import in each hook that uses it

**Bad**:

- Plan files won't be validated (acceptable for ephemeral docs)
- If Claude Code changes how it signals plan mode, detector needs update

## More Information

- **Prior art**: ADR 2025-12-09 (plan file exemption via path patterns)
- **Claude Code docs**: <https://code.claude.com/docs/en/hooks>
- **Hooks updated**: version-guard, mise-hygiene-guard
- **Future hooks** should import `isPlanMode` from `pretooluse-helpers.ts`
