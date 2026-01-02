---
description: Add item to encouraged list mid-loop
allowed-tools: Bash, AskUserQuestion
argument-hint: "<phrase> | --list | --clear | --remove (live: applies next iteration)"
---

# Ralph Loop: Encourage

Add items to the encouraged list during an active loop session.
Encouraged items get priority in opportunity discovery and override forbidden patterns.

**Runtime configurable**: Works with or without active Ralph loop. Changes apply on next iteration.

## Usage

- `/ralph:encourage Sharpe ratio` - Add "Sharpe ratio" to encouraged list
- `/ralph:encourage --list` - Show current encouraged items
- `/ralph:encourage --clear` - Clear all encouraged items
- `/ralph:encourage --remove` - Interactive picker to remove specific items
- `/ralph:encourage --remove <phrase>` - Remove item matching phrase (fuzzy)

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility
/usr/bin/env bash << 'RALPH_ENCOURAGE_SCRIPT'
# RALPH_ENCOURAGE_SCRIPT marker - required for PreToolUse hook bypass
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"
STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"

# Get arguments (everything after the command)
ARGS="${ARGUMENTS:-}"

# Ensure config file exists with guidance structure
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"guidance": {"forbidden": [], "encouraged": []}}' > "$CONFIG_FILE"
fi

# Ensure guidance structure exists
if ! jq -e '.guidance' "$CONFIG_FILE" >/dev/null 2>&1; then
    if ! jq '. + {guidance: {forbidden: [], encouraged: []}}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
        echo "ERROR: Failed to initialize guidance structure (jq error)" >&2
        rm -f "$CONFIG_FILE.tmp"
        exit 1
    fi
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
        if ! jq '.guidance.encouraged = []' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
            echo "ERROR: Failed to clear encouraged items (jq error)" >&2
            rm -f "$CONFIG_FILE.tmp"
            exit 1
        fi
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Cleared all encouraged items"
        ;;
    "--remove"|"-r")
        # Interactive removal - list items for AUQ picker
        COUNT=$(jq -r '.guidance.encouraged | length' "$CONFIG_FILE")
        if [[ "$COUNT" -eq 0 ]]; then
            echo "No encouraged items to remove."
            exit 0
        fi
        echo "REMOVE_MODE=interactive"
        echo "Select items to remove from encouraged list:"
        echo ""
        INDEX=0
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "[$INDEX] $item"
            INDEX=$((INDEX + 1))
        done
        echo ""
        echo "Use AskUserQuestion with multiSelect to let user pick items to remove."
        echo "Then call: /ralph:encourage --remove-by-index <indices>"
        ;;
    --remove-by-index\ *)
        # Remove by comma-separated indices (e.g., --remove-by-index 0,2,3)
        INDICES="${ARGS#--remove-by-index }"
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        # Convert comma-separated to jq array deletion
        # Build jq filter to delete indices in reverse order (to preserve index validity)
        SORTED_INDICES=$(echo "$INDICES" | tr ',' '\n' | sort -rn | tr '\n' ' ')
        for IDX in $SORTED_INDICES; do
            if ! jq --argjson idx "$IDX" --arg ts "$TS" \
                '.guidance.encouraged |= (to_entries | map(select(.key != $idx)) | map(.value)) | .guidance.timestamp = $ts' \
                "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
                echo "ERROR: Failed to remove item at index $IDX (jq error)" >&2
                rm -f "$CONFIG_FILE.tmp"
                exit 1
            fi
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        done
        echo "Removed items at indices: $INDICES"
        echo ""
        echo "Remaining encouraged items:"
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  • $item"
        done
        ;;
    --remove\ *)
        # Fuzzy removal by phrase
        PHRASE="${ARGS#--remove }"
        # Find best match using case-insensitive substring
        MATCH=$(jq -r --arg phrase "$PHRASE" \
            '.guidance.encouraged[] | select(. | ascii_downcase | contains($phrase | ascii_downcase))' \
            "$CONFIG_FILE" | head -1)
        if [[ -z "$MATCH" ]]; then
            echo "No encouraged item matches: $PHRASE"
            echo ""
            echo "Current encouraged items:"
            jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
                echo "  • $item"
            done
            exit 1
        fi
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        if ! jq --arg match "$MATCH" --arg ts "$TS" \
            '.guidance.encouraged |= map(select(. != $match)) | .guidance.timestamp = $ts' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
            echo "ERROR: Failed to remove encouraged item (jq error)" >&2
            rm -f "$CONFIG_FILE.tmp"
            exit 1
        fi
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Removed from encouraged list: $MATCH"
        echo "(matched phrase: $PHRASE)"
        echo ""
        echo "Remaining encouraged items:"
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  • $item"
        done
        ;;
    "")
        echo "Usage: /ralph:encourage <phrase> | --list | --clear | --remove [phrase]"
        echo ""
        echo "Current encouraged items:"
        jq -r '.guidance.encouraged[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  • $item"
        done
        ;;
    *)
        # Add item to encouraged list (deduplicated) with timestamp
        # ADR: /docs/adr/2026-01-02-ralph-guidance-freshness-detection.md
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        if ! jq --arg item "$ARGS" --arg ts "$TS" \
            '.guidance.encouraged = ((.guidance.encouraged // []) + [$item] | unique) | .guidance.timestamp = $ts' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
            echo "ERROR: Failed to add encouraged item (jq error)" >&2
            rm -f "$CONFIG_FILE.tmp"
            exit 1
        fi
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
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
3. **All phases**: Guidance appears in both implementation and exploration phases (unified template)
4. **Priority override**: Encouraged items override forbidden patterns during filtering
5. **Persistent**: Settings persist until cleared or session ends

## Interactive Removal (--remove)

When the user runs `/ralph:encourage --remove` without a phrase, use `AskUserQuestion` with `multiSelect: true`:

1. Run the bash script to get the list of items with indices
2. Parse the output to extract items
3. Present items as options in AskUserQuestion
4. After user selects, run `/ralph:encourage --remove-by-index <comma-separated-indices>`

**Example AskUserQuestion**:
```json
{
  "question": "Which encouraged items do you want to remove?",
  "header": "Remove items",
  "options": [
    {"label": "Sharpe ratio optimization", "description": "Index 0"},
    {"label": "Risk-adjusted returns", "description": "Index 1"}
  ],
  "multiSelect": true
}
```

**Fuzzy matching** (`--remove <phrase>`): Finds first item containing the phrase (case-insensitive).

## Template Rendering (v8.7.0+)

The unified Ralph template (`ralph-unified.md`) renders guidance in the `## USER GUIDANCE` section:

```markdown
### ENCOURAGED (User Priorities)

**Focus your work on these high-value areas:**

1. **Your first encouraged item**
2. **Your second encouraged item**

✅ These override forbidden patterns.
```

This section appears **regardless of phase** (implementation or exploration), ensuring your priorities are always visible to Claude.
