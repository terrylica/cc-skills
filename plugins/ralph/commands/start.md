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
SETTINGS="$HOME/.claude/settings.json"
MARKER="ralph/hooks/"

# Check if hooks are installed
HOOKS_INSTALLED=false
if command -v jq &>/dev/null && [[ -f "$SETTINGS" ]]; then
    HOOK_COUNT=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>/dev/null || echo "0")
    if [[ "$HOOK_COUNT" -gt 0 ]]; then
        HOOKS_INSTALLED=true
    fi
fi

# Warn if hooks not installed
if [[ "$HOOKS_INSTALLED" == "false" ]]; then
    echo "╔══════════════════════════════════════════╗"
    echo "║  ⚠️  WARNING: Hooks not installed!        ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "The loop will NOT work without hooks registered."
    echo ""
    echo "To fix:"
    echo "  1. Run: /ralph:hooks install"
    echo "  2. Restart Claude Code"
    echo "  3. Run: /ralph:start again"
    echo ""
    exit 1
fi

# Create loop-enabled marker
mkdir -p "$PROJECT_DIR/.claude"
touch "$PROJECT_DIR/.claude/loop-enabled"

# Apply POC config if requested
if [[ "$ARGUMENTS" == *"--poc"* ]]; then
    echo '{"min_hours": 0.083, "max_hours": 0.167, "min_iterations": 10, "max_iterations": 20}' > "$PROJECT_DIR/.claude/loop-config.json"
    echo "╔══════════════════════════════════════════╗"
    echo "║  Ralph Loop: POC MODE                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo "Time limits: 5 min minimum / 10 min maximum"
    echo "Iterations: 10 minimum / 20 maximum"
else
    echo "╔══════════════════════════════════════════╗"
    echo "║  Ralph Loop: PRODUCTION MODE             ║"
    echo "╚══════════════════════════════════════════╝"
    echo "Time limits: 4h minimum / 9h maximum"
    echo "Iterations: 50 minimum / 99 maximum"
fi

echo ""
echo "Status: ACTIVATED"
echo "Marker: $PROJECT_DIR/.claude/loop-enabled"
echo ""
echo "To stop: /ralph:stop or create $PROJECT_DIR/.claude/STOP_LOOP"
echo ""
echo "────────────────────────────────────────────"
echo "Note: If you just installed hooks, restart"
echo "Claude Code for them to take effect."
echo "────────────────────────────────────────────"
```

Run the bash script above to enable loop mode.
