---
description: View or modify loop configuration
allowed-tools: Read, Write, Bash, AskUserQuestion
argument-hint: "[show|edit|reset]"
---

# Ralph Loop: Config

View or modify the Ralph Wiggum loop configuration.

## Arguments

- `show` (default): Display current configuration
- `edit`: Interactively modify settings
- `reset`: Reset to global defaults

## Configuration Options

| Setting                     | Default | Description                                |
| --------------------------- | ------- | ------------------------------------------ |
| `min_hours`                 | 4.0     | Minimum runtime before allowing completion |
| `max_hours`                 | 9.0     | Maximum runtime (hard stop)                |
| `min_iterations`            | 50      | Minimum iterations before completion       |
| `max_iterations`            | 99      | Maximum iterations (safety limit)          |
| `loop_similarity_threshold` | 0.90    | RapidFuzz threshold for loop detection     |

## Execution

Based on `$ARGUMENTS`:

### For `show` or empty

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_CONFIG_SHOW'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
echo "=== Project Config ==="
if [[ -f "$PROJECT_DIR/.claude/loop-config.json" ]]; then
    cat "$PROJECT_DIR/.claude/loop-config.json" | python3 -m json.tool
else
    echo "(using global defaults)"
fi

echo ""
echo "=== Global Config ==="
cat "$HOME/.claude/automation/loop-orchestrator/config/loop_config.json" | python3 -m json.tool 2>/dev/null || echo "(not found)"
RALPH_CONFIG_SHOW
```

### For `reset`

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_CONFIG_RESET'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rm -f "$PROJECT_DIR/.claude/loop-config.json"
echo "Project config reset. Using global defaults."
RALPH_CONFIG_RESET
```

### For `edit`

Use the AskUserQuestion tool to prompt for new values, then write to `$PROJECT_DIR/.claude/loop-config.json`.

Example config:

```json
{
  "min_hours": 4.0,
  "max_hours": 9.0,
  "min_iterations": 50,
  "max_iterations": 99,
  "loop_similarity_threshold": 0.9
}
```
