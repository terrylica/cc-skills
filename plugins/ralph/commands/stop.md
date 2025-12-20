---
description: Disable autonomous loop mode immediately
allowed-tools: Bash
argument-hint: ""
---

# Ralph Loop: Stop

Immediately disable the Ralph Wiggum autonomous improvement loop.

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_STOP_SCRIPT'
# RALPH_STOP_SCRIPT marker - required for PreToolUse hook bypass
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"

# ===== STATE MACHINE TRANSITION =====
# State machine: RUNNING → DRAINING → STOPPED (async fire-and-forget)
CURRENT_STATE="stopped"
if [[ -f "$STATE_FILE" ]]; then
    CURRENT_STATE=$(jq -r '.state // "stopped"' "$STATE_FILE" 2>/dev/null || echo "stopped")
fi

echo "Current state: $CURRENT_STATE"

# Handle state transitions
case "$CURRENT_STATE" in
    "running")
        # Transition to DRAINING (async - Stop hook will complete to STOPPED)
        echo '{"state": "draining"}' > "$STATE_FILE"
        echo "State transition: RUNNING → DRAINING"
        ;;
    "draining")
        # Already draining, force to STOPPED
        echo '{"state": "stopped"}' > "$STATE_FILE"
        echo "State transition: DRAINING → STOPPED (forced)"
        ;;
    "stopped")
        echo "Loop already stopped"
        ;;
    *)
        echo "Unknown state '$CURRENT_STATE', resetting to STOPPED"
        echo '{"state": "stopped"}' > "$STATE_FILE"
        ;;
esac

# Create kill switch as backup (not blocked by PreToolUse guard)
# This ensures the Stop hook will see it and complete the transition
touch "$PROJECT_DIR/.claude/STOP_LOOP"
echo "Created kill switch signal"

# Update config state
if [[ -f "$CONFIG_FILE" ]]; then
    jq '.state = "stopped"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Remove legacy loop-enabled markers
if [[ -f "$PROJECT_DIR/.claude/loop-enabled" ]]; then
    rm "$PROJECT_DIR/.claude/loop-enabled"
    rm -f "$PROJECT_DIR/.claude/loop-start-timestamp"
    echo "Cleaned up legacy markers"
fi

# Final state
echo ""
echo "Final state: $(jq -r '.state' "$STATE_FILE" 2>/dev/null || echo 'stopped')"
echo "Loop stop requested. Session will terminate on next Stop hook check."
RALPH_STOP_SCRIPT
```

Run the bash script above to disable loop mode.
