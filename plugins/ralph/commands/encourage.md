---
description: Add item to encouraged list mid-loop
allowed-tools: Bash, AskUserQuestion
argument-hint: "<phrase> | --list | --clear"
---

# Ralph Loop: Encourage

Add items to the encouraged list during an active loop session.
Encouraged items get priority in opportunity discovery and override forbidden patterns.

## Usage

- `/ralph:encourage Sharpe ratio` - Add "Sharpe ratio" to encouraged list
- `/ralph:encourage --list` - Show current encouraged items
- `/ralph:encourage --clear` - Clear all encouraged items

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility
/usr/bin/env bash << 'RALPH_ENCOURAGE_SCRIPT'
# RALPH_ENCOURAGE_SCRIPT marker - required for PreToolUse hook bypass
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"
STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"

# Get arguments (everything after the command)
ARGS="${1:-}"

# Ensure config file exists with guidance structure
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"guidance": {"forbidden": [], "encouraged": []}}' > "$CONFIG_FILE"
fi

# Ensure guidance structure exists
if ! jq -e '.guidance' "$CONFIG_FILE" >/dev/null 2>&1; then
    jq '. + {guidance: {forbidden: [], encouraged: []}}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Handle commands
case "$ARGS" in
    "--list"|"-l")
        echo "Current encouraged items:"
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  • $item"
        done
        COUNT=$(jq -r '.guidance.encouraged | length' "$CONFIG_FILE")
        echo ""
        echo "Total: $COUNT items"
        ;;
    "--clear"|"-c")
        jq '.guidance.encouraged = []' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Cleared all encouraged items"
        ;;
    "")
        echo "Usage: /ralph:encourage <phrase> | --list | --clear"
        echo ""
        echo "Current encouraged items:"
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  • $item"
        done
        ;;
    *)
        # Add item to encouraged list (deduplicated)
        jq --arg item "$ARGS" '.guidance.encouraged = ((.guidance.encouraged // []) + [$item] | unique)' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Added to encouraged list: $ARGS"
        echo ""
        echo "Effect: Will apply on next iteration (Stop hook reads config fresh)"
        echo ""
        echo "Current encouraged items:"
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  • $item"
        done
        ;;
esac
RALPH_ENCOURAGE_SCRIPT
```

Run the bash script above to manage encouraged items.

## How It Works

1. **Immediate config update**: Changes are written to `.claude/ralph-config.json`
2. **Next iteration applies**: The Stop hook reads config fresh on each message end
3. **Priority override**: Encouraged items override forbidden patterns during filtering
4. **Persistent**: Settings persist until cleared or session ends
