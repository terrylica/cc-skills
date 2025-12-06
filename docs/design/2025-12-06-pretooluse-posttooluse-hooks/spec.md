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
├── pretooluse-guard.sh     # Hard blocks: manual ASCII art (exit 2)
└── posttooluse-reminder.sh # Reminds: graph-easy skill, ADR↔Spec, Code→ADR
```

### hooks.json

```json
{
  "description": "cc-skills implementation standards enforcement",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
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
        "matcher": "Bash|Write|Edit",
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

### Exit Code 2 vs Permission Decisions

| Approach                   | Bypass-able?                           | Use Case         |
| -------------------------- | -------------------------------------- | ---------------- |
| `permissionDecision: deny` | Yes (with bypass permissions)          | Soft warnings    |
| `exit 2` + stderr          | **No** (runs before permission system) | Hard enforcement |

### PreToolUse Guard Logic

Uses **exit code 2** (hard block that cannot be bypassed):

| Tool       | Check                      | Action                                          |
| ---------- | -------------------------- | ----------------------------------------------- |
| Write/Edit | Box-drawing chars in `.md` | Block unless `<details>graph-easy source` block |

### PostToolUse Reminder Logic

Non-blocking reminders that work regardless of bypass permissions:

| Tool/Pattern                   | Reminder                              |
| ------------------------------ | ------------------------------------- |
| Bash with `graph-easy`         | "Prefer the graph-easy skill"         |
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
# Test PreToolUse - should block ASCII art without source (exit 2)
echo '{"tool_name":"Write","tool_input":{"file_path":"test.md","content":"┌──┐\\n└──┘"}}' | ./hooks/pretooluse-guard.sh
echo "Exit code: $?"  # Should be 2

# Test PreToolUse - should allow ASCII art with source block (exit 0)
echo '{"tool_name":"Write","tool_input":{"file_path":"test.md","content":"┌──┐<summary>graph-easy source</summary>"}}' | ./hooks/pretooluse-guard.sh
echo "Exit code: $?"  # Should be 0

# Test PostToolUse - graph-easy reminder
echo '{"tool_name":"Bash","tool_input":{"command":"graph-easy"}}' | ./hooks/posttooluse-reminder.sh

# Test PostToolUse - ADR sync reminder
echo '{"tool_name":"Write","tool_input":{"file_path":"docs/adr/2025-01-01-test.md"}}' | ./hooks/posttooluse-reminder.sh
```

## Success Criteria

- [x] Manual ASCII art blocked with exit code 2 (hard block, cannot be bypassed)
- [x] ASCII art with `<details>graph-easy source` allowed
- [x] Graph-easy CLI triggers PostToolUse skill reminder
- [x] ADR modification triggers spec sync reminder
- [x] Spec modification triggers ADR sync reminder
- [x] Code modification triggers traceability reminder
- [x] Bash + jq implementation (no Python dependency)
- [x] <20ms execution time per hook
