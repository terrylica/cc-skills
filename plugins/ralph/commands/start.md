---
description: Enable autonomous loop mode for long-running tasks
allowed-tools: Read, Write, Bash
argument-hint: "[--poc]"
---

# Ralph Loop: Start

Enable the Ralph Wiggum autonomous improvement loop. Claude will continue working until:

- Task is truly complete (respecting minimum time/iteration thresholds)
- Maximum time limit reached (default: 9 hours)
- Maximum iterations reached (default: 99)
- Kill switch activated (`.claude/STOP_LOOP` file created)

## Arguments

- `--poc`: Use proof-of-concept settings (5 min / 10 min limits, 10/20 iterations)

## Execution

```bash
# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Create loop-enabled marker
mkdir -p "$PROJECT_DIR/.claude"
touch "$PROJECT_DIR/.claude/loop-enabled"

# Apply POC config if requested
if [[ "$ARGUMENTS" == *"--poc"* ]]; then
    echo '{"min_hours": 0.083, "max_hours": 0.167, "min_iterations": 10, "max_iterations": 20}' > "$PROJECT_DIR/.claude/loop-config.json"
    echo "POC mode enabled (5/10 min limits, 10/20 iterations)"
else
    echo "Production mode enabled (4h/9h limits, 50/99 iterations)"
fi

echo "Ralph loop mode ACTIVATED"
echo "Marker: $PROJECT_DIR/.claude/loop-enabled"
echo ""
echo "To stop: /ralph:stop or create $PROJECT_DIR/.claude/STOP_LOOP"
```

Run the bash script above to enable loop mode.
