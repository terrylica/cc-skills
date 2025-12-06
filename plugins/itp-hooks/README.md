# ITP Hooks

Claude Code plugin for ITP (Implement The Plan) workflow enforcement via PreToolUse and PostToolUse hooks.

## Installation

```bash
# From cc-skills marketplace
/plugin install itp-hooks@cc-skills
```

## Features

### Hard Blocks (PreToolUse - Cannot be bypassed)

| Check            | Trigger                                         | Action            |
| ---------------- | ----------------------------------------------- | ----------------- |
| Manual ASCII art | Box-drawing chars in `.md` without source block | Exit code 2 block |

### Non-blocking Reminders (PostToolUse)

| Check                 | Trigger                        | Reminder                            |
| --------------------- | ------------------------------ | ----------------------------------- |
| Graph-easy skill      | Direct `graph-easy` CLI usage  | Prefer skill for reproducibility    |
| ADR→Spec sync         | Modify `docs/adr/*.md`         | Check if Design Spec needs updating |
| Spec→ADR sync         | Modify `docs/design/*/spec.md` | Check if ADR needs updating         |
| Code→ADR traceability | Modify implementation files    | Consider ADR reference              |

## Requirements

- `jq` - JSON processor (standard on most systems)
- Claude Code 1.0.0+

## How It Works

### Exit Code 2 vs Permission Decisions

| Approach                   | Bypass-able? | Use Case         |
| -------------------------- | ------------ | ---------------- |
| `permissionDecision: deny` | Yes          | Soft warnings    |
| `exit 2` + stderr          | **No**       | Hard enforcement |

This plugin uses **exit code 2** for ASCII art blocking because:

- Runs before permission system
- Cannot be bypassed even with `dangerously-skip-permissions`
- No legitimate reason to add manual diagrams without source

### Why PostToolUse for Graph-easy?

- Users may legitimately need direct CLI for testing
- Transcript-based skill detection had false positives
- Reminders work regardless of bypass permissions

## Files

```
plugins/itp-hooks/
├── hooks/
│   ├── hooks.json              # Hook configuration
│   ├── pretooluse-guard.sh     # ASCII art blocking
│   └── posttooluse-reminder.sh # Sync reminders
├── README.md
└── LICENSE
```

## License

MIT
