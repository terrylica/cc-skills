---
description: Show current loop state
allowed-tools: Bash
argument-hint: ""
---

# Ralph Universal: Status

```bash
/usr/bin/env bash << 'RALPH_UNIVERSAL_STATUS'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "========================================"
echo "  RALPH UNIVERSAL STATUS"
echo "========================================"
echo ""

STATE_FILE="$PROJECT_DIR/.claude/ralph-universal-state.json"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-universal-config.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "State: NOT STARTED"
    echo "       Run /ralph-universal:start to begin"
    exit 0
fi

STATE=$(jq -r '.state // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
echo "State: $STATE"
echo "Project: $PROJECT_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "Configuration:"
    jq -r '.loop_limits | "  Time: \(.min_hours)h - \(.max_hours)h\n  Iterations: \(.min_iterations) - \(.max_iterations)"' "$CONFIG_FILE" 2>/dev/null || echo "  (unable to read config)"
fi

if [[ -f "$PROJECT_DIR/.claude/ralph-universal-start-timestamp" ]]; then
    START_TS=$(cat "$PROJECT_DIR/.claude/ralph-universal-start-timestamp")
    NOW_TS=$(date +%s)
    ELAPSED_SECS=$((NOW_TS - START_TS))
    ELAPSED_MINS=$((ELAPSED_SECS / 60))
    echo ""
    echo "Elapsed: ${ELAPSED_MINS} minutes"
fi
RALPH_UNIVERSAL_STATUS
```
