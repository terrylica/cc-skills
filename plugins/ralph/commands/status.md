---
description: Show current loop status and session metrics
allowed-tools: Read, Bash
argument-hint: ""
---

# Ralph Loop: Status

Display the current state of the Ralph Wiggum autonomous improvement loop.

## Execution

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "=== Ralph Loop Status ==="
echo ""

# Check if loop is enabled
if [[ -f "$PROJECT_DIR/.claude/loop-enabled" ]]; then
    echo "Status: ACTIVE"
else
    echo "Status: INACTIVE"
fi

# Check for kill switch
if [[ -f "$PROJECT_DIR/.claude/STOP_LOOP" ]]; then
    echo "Kill Switch: TRIGGERED"
fi

echo ""

# Show config if exists
if [[ -f "$PROJECT_DIR/.claude/loop-config.json" ]]; then
    echo "=== Configuration ==="
    cat "$PROJECT_DIR/.claude/loop-config.json" | python3 -m json.tool 2>/dev/null || cat "$PROJECT_DIR/.claude/loop-config.json"
    echo ""
fi

# Show session state if exists
if [[ -f "$PROJECT_DIR/.claude/loop-state.json" ]]; then
    echo "=== Session State ==="
    cat "$PROJECT_DIR/.claude/loop-state.json" | python3 -m json.tool 2>/dev/null || cat "$PROJECT_DIR/.claude/loop-state.json"
    echo ""
fi

# Show global config
GLOBAL_CONFIG="$HOME/.claude/automation/loop-orchestrator/config/loop_config.json"
if [[ -f "$GLOBAL_CONFIG" ]]; then
    echo "=== Global Defaults ==="
    cat "$GLOBAL_CONFIG" | python3 -m json.tool 2>/dev/null || cat "$GLOBAL_CONFIG"
fi
```

Run the bash script above to show status.
