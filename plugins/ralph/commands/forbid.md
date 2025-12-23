---
description: Add item to forbidden list mid-loop
allowed-tools: Bash, AskUserQuestion
argument-hint: "<phrase> | --list | --clear"
---

# Ralph Loop: Forbid

Add items to the forbidden list during an active loop session.
Forbidden items are HARD BLOCKED from opportunity discovery (not just skipped).

## Usage

- `/ralph:forbid documentation updates` - Add "documentation updates" to forbidden list
- `/ralph:forbid --list` - Show current forbidden items
- `/ralph:forbid --clear` - Clear all forbidden items

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility
/usr/bin/env bash << 'RALPH_FORBID_SCRIPT'
# RALPH_FORBID_SCRIPT marker - required for PreToolUse hook bypass
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
        echo "Current forbidden items (HARD BLOCKED):"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        COUNT=$(jq -r '.guidance.forbidden | length' "$CONFIG_FILE")
        echo ""
        echo "Total: $COUNT items"
        ;;
    "--clear"|"-c")
        jq '.guidance.forbidden = []' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Cleared all forbidden items"
        ;;
    "")
        echo "Usage: /ralph:forbid <phrase> | --list | --clear"
        echo ""
        echo "Current forbidden items (HARD BLOCKED):"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        ;;
    *)
        # Add item to forbidden list (deduplicated)
        jq --arg item "$ARGS" '.guidance.forbidden = ((.guidance.forbidden // []) + [$item] | unique)' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Added to forbidden list: $ARGS"
        echo ""
        echo "Effect: Will HARD BLOCK on next iteration (Stop hook reads config fresh)"
        echo "Note: User-forbidden items get FilterResult.BLOCK, not SKIP"
        echo ""
        echo "Current forbidden items:"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        ;;
esac
RALPH_FORBID_SCRIPT
```

Run the bash script above to manage forbidden items.

## How It Works

1. **Immediate config update**: Changes are written to `.claude/ralph-config.json`
2. **Next iteration applies**: The Stop hook reads config fresh on each message end
3. **HARD BLOCK**: User-forbidden items get `FilterResult.BLOCK` (not SKIP)
4. **Cannot be fallback**: Unlike built-in busywork, user-forbidden items cannot be chosen as fallback
5. **Persistent**: Settings persist until cleared or session ends

## Difference from Built-in Busywork

| Type              | Filter Result    | Behavior                             |
| ----------------- | ---------------- | ------------------------------------ |
| Built-in busywork | SKIP             | Soft-skip, can be chosen as fallback |
| User-forbidden    | BLOCK            | Hard-block, cannot be chosen at all  |
| User-encouraged   | ALLOW (priority) | Always allowed, overrides forbidden  |
