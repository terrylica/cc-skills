---
description: Disable autonomous loop mode immediately
allowed-tools: Bash
argument-hint: ""
---

# Ralph Universal: Stop

**EXECUTE IMMEDIATELY**: Use the Bash tool to run the following script.

```bash
/usr/bin/env bash << 'RALPH_UNIVERSAL_STOP'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "Stopping Ralph Universal loop..."

# Set state to stopped
STATE_FILE="$PROJECT_DIR/.claude/ralph-universal-state.json"
if [[ -d "$PROJECT_DIR/.claude" ]]; then
    echo '{"state": "stopped"}' > "$STATE_FILE"
fi

# Create kill switch for redundancy
touch "$PROJECT_DIR/.claude/STOP_LOOP"

# Update config if exists
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-universal-config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    jq '.state = "stopped"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Clean up markers
rm -f "$PROJECT_DIR/.claude/ralph-universal-start-timestamp"

# Create global stop signal
echo '{"state": "stopped", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$HOME/.claude/ralph-universal-global-stop.json"

echo ""
echo "Ralph Universal: STOPPED"
echo "Project: $PROJECT_DIR"
RALPH_UNIVERSAL_STOP
```

After execution, confirm the loop has been stopped.
