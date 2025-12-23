---
description: Show current loop status and session metrics
allowed-tools: Read, Bash
argument-hint: ""
---

# Ralph Loop: Status

Display the current state of the Ralph Wiggum autonomous improvement loop.

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_STATUS_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SETTINGS="$HOME/.claude/settings.json"
MARKER="ralph/hooks/"

echo "=== Ralph Loop Status ==="
echo ""

# Check hook registration in settings.json
HOOKS_REGISTERED=false
if command -v jq &>/dev/null && [[ -f "$SETTINGS" ]]; then
    HOOK_COUNT=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>/dev/null || echo "0")
    if [[ "$HOOK_COUNT" -gt 0 ]]; then
        HOOKS_REGISTERED=true
    fi
fi

# Check if loop is enabled (marker file)
LOOP_ENABLED=false
if [[ -f "$PROJECT_DIR/.claude/loop-enabled" ]]; then
    LOOP_ENABLED=true
fi

# Determine overall status
if [[ "$HOOKS_REGISTERED" == "true" ]] && [[ "$LOOP_ENABLED" == "true" ]]; then
    echo "Status: ACTIVE"
    echo "Hooks are registered and loop enabled"
elif [[ "$HOOKS_REGISTERED" == "true" ]] && [[ "$LOOP_ENABLED" == "false" ]]; then
    echo "Status: READY (not started)"
    echo "Run /ralph:start to begin loop"
elif [[ "$HOOKS_REGISTERED" == "false" ]] && [[ "$LOOP_ENABLED" == "true" ]]; then
    echo "Status: ENABLED (hooks not installed)"
    echo "Run /ralph:hooks install, then restart Claude Code"
elif [[ "$HOOKS_REGISTERED" == "false" ]] && [[ "$LOOP_ENABLED" == "false" ]]; then
    echo "Status: INACTIVE"
    echo "Run /ralph:hooks install first"
fi
echo ""

# Show component status
echo "Components:"
if [[ "$HOOKS_REGISTERED" == "true" ]]; then
    echo "  [x] Hooks registered in settings.json ($HOOK_COUNT entries)"
else
    echo "  [ ] Hooks NOT registered - run /ralph:hooks install"
fi

if [[ "$LOOP_ENABLED" == "true" ]]; then
    echo "  [x] Loop enabled (marker file exists)"
else
    echo "  [ ] Loop not enabled - run /ralph:start"
fi

# Check for kill switch
if [[ -f "$PROJECT_DIR/.claude/STOP_LOOP" ]]; then
    echo "  [!] Kill Switch: TRIGGERED"
fi

echo ""

# Show config if exists
if [[ -f "$PROJECT_DIR/.claude/loop-config.json" ]]; then
    echo "=== Configuration ==="
    cat "$PROJECT_DIR/.claude/loop-config.json" | python3 -m json.tool 2>/dev/null || cat "$PROJECT_DIR/.claude/loop-config.json"
    echo ""
fi

# Show session state if exists (ralph-state.json is canonical, loop-state.json is legacy)
if [[ -f "$PROJECT_DIR/.claude/ralph-state.json" ]]; then
    echo "=== Session State ==="
    cat "$PROJECT_DIR/.claude/ralph-state.json" | python3 -m json.tool 2>/dev/null || cat "$PROJECT_DIR/.claude/ralph-state.json"
    echo ""
fi

# Show last stop reason if exists
STOP_CACHE="$HOME/.claude/ralph-stop-reason.json"
if [[ -f "$STOP_CACHE" ]]; then
    echo "=== Last Stop Reason ==="
    LAST_STOP=$(jq -r '.reason // "Unknown"' "$STOP_CACHE")
    STOP_TIME=$(jq -r '.timestamp // "Unknown"' "$STOP_CACHE")
    STOP_TYPE=$(jq -r '.type // "normal"' "$STOP_CACHE")
    STOP_SESSION=$(jq -r '.session_id // "Unknown"' "$STOP_CACHE")

    if [[ "$STOP_TYPE" == "hard" ]]; then
        echo "Type: HARD STOP"
    else
        echo "Type: Normal"
    fi
    echo "Reason: $LAST_STOP"
    echo "Time: $STOP_TIME"
    echo "Session: ${STOP_SESSION:0:8}..."
    echo ""
fi

# Reminder about restart
if [[ "$HOOKS_REGISTERED" == "true" ]]; then
    echo "Note: If you just installed hooks, restart Claude Code for them to take effect."
fi
RALPH_STATUS_SCRIPT
```

Run the bash script above to show status.
