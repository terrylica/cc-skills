---
adr: 2025-12-06-pretooluse-posttooluse-hooks
source: ~/.claude/plans/modular-crafting-acorn.md
implementation-status: completed
phase: phase-1
last-updated: 2025-12-06
---

# PreToolUse and PostToolUse Hooks

**ADR**: [PreToolUse and PostToolUse Hooks](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)

## Problem Statement

Claude Code has no built-in enforcement for:

1. Requiring skill invocation for graph-easy diagrams
2. Preventing manual ASCII art in markdown
3. Reminding about ADR↔Spec synchronization

## Solution Overview

Two consolidated Bash + jq hooks:

| Hook                      | Event       | Purpose          |
| ------------------------- | ----------- | ---------------- |
| `pretooluse-guard.sh`     | PreToolUse  | Block violations |
| `posttooluse-reminder.sh` | PostToolUse | Sync reminders   |

## Implementation

### File Structure

```
hooks/
├── hooks.json              # Configuration (points to scripts)
├── pretooluse-guard.sh     # Blocks: graph-easy CLI, manual ASCII
└── posttooluse-reminder.sh # Reminds: ADR↔Spec, Code→ADR
```

### hooks.json

```json
{
  "description": "cc-skills implementation standards enforcement",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/posttooluse-reminder.sh"
          }
        ]
      }
    ]
  }
}
```

### PreToolUse Guard Logic

| Tool       | Check                      | Action                                            |
| ---------- | -------------------------- | ------------------------------------------------- |
| Bash       | Contains `graph-easy`      | Block unless skill invoked (transcript check)     |
| Write/Edit | Box-drawing chars in `.md` | Block unless `<details>graph-easy source` present |

### PostToolUse Reminder Logic

| File Pattern                   | Reminder                              |
| ------------------------------ | ------------------------------------- |
| `docs/adr/*.md`                | "Check if Design Spec needs updating" |
| `docs/design/*/spec.md`        | "Check if ADR needs updating"         |
| `src/**`, `*.py`, `*.ts`, etc. | "Consider ADR traceability"           |

## Performance

| Metric      | Python   | Bash + jq       |
| ----------- | -------- | --------------- |
| Execution   | ~46ms    | ~18ms           |
| Improvement | baseline | **2.5x faster** |

## Validation

```bash
# Test PreToolUse - should block
echo '{"tool_name":"Bash","tool_input":{"command":"graph-easy"}}' | ./hooks/pretooluse-guard.sh

# Test PostToolUse - should remind
echo '{"tool_name":"Write","tool_input":{"file_path":"docs/adr/test.md"}}' | ./hooks/posttooluse-reminder.sh
```

## Success Criteria

- [x] Graph-easy CLI blocked without skill context
- [x] Manual ASCII art blocked in markdown
- [x] ADR modification triggers spec sync reminder
- [x] Spec modification triggers ADR sync reminder
- [x] Code modification triggers traceability reminder
- [x] Bash + jq implementation (no Python dependency)
- [x] <20ms execution time per hook
