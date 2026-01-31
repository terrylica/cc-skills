---
description: Add item to forbidden list mid-loop
allowed-tools: Bash, AskUserQuestion
argument-hint: "<phrase> | --list | --clear | --remove (live: HARD BLOCKS next iteration)"
---

# Ralph Loop: Forbid

Add items to the forbidden list during an active loop session.
Forbidden items are HARD BLOCKED from opportunity discovery (not just skipped).

**Runtime configurable**: Works with or without active Ralph loop. Changes apply on next iteration.

## Usage

- `/ralph:forbid documentation updates` - Add "documentation updates" to forbidden list
- `/ralph:forbid --list` - Show current forbidden items
- `/ralph:forbid --clear` - Clear all forbidden items
- `/ralph:forbid --remove` - Interactive picker to remove specific items
- `/ralph:forbid --remove <phrase>` - Remove item matching phrase (fuzzy)

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility
/usr/bin/env bash << 'RALPH_FORBID_SCRIPT'
# RALPH_FORBID_SCRIPT marker - required for PreToolUse hook bypass
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
        echo "Current forbidden items (HARD BLOCKED):"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        COUNT=$(jq -r '.guidance.forbidden | length' "$CONFIG_FILE")
        echo ""
        echo "Total: $COUNT items"
        ;;
    "--clear"|"-c")
        if ! jq '.guidance.forbidden = []' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
            echo "ERROR: Failed to clear forbidden items (jq error)" >&2
            rm -f "$CONFIG_FILE.tmp"
            exit 1
        fi
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Cleared all forbidden items"
        ;;
    "--remove"|"-r")
        # Interactive removal - list items for AUQ picker
        COUNT=$(jq -r '.guidance.forbidden | length' "$CONFIG_FILE")
        if [[ "$COUNT" -eq 0 ]]; then
            echo "No forbidden items to remove."
            exit 0
        fi
        echo "REMOVE_MODE=interactive"
        echo "Select items to remove from forbidden list:"
        echo ""
        INDEX=0
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "[$INDEX] $item"
            INDEX=$((INDEX + 1))
        done
        echo ""
        echo "Use AskUserQuestion with multiSelect to let user pick items to remove."
        echo "Then call: /ralph:forbid --remove-by-index <indices>"
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
                '.guidance.forbidden |= (to_entries | map(select(.key != $idx)) | map(.value)) | .guidance.timestamp = $ts' \
                "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
                echo "ERROR: Failed to remove item at index $IDX (jq error)" >&2
                rm -f "$CONFIG_FILE.tmp"
                exit 1
            fi
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        done
        echo "Removed items at indices: $INDICES"
        echo ""
        echo "Remaining forbidden items:"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        ;;
    --remove\ *)
        # Fuzzy removal by phrase
        PHRASE="${ARGS#--remove }"
        # Find best match using case-insensitive substring
        MATCH=$(jq -r --arg phrase "$PHRASE" \
            '.guidance.forbidden[] | select(. | ascii_downcase | contains($phrase | ascii_downcase))' \
            "$CONFIG_FILE" | head -1)
        if [[ -z "$MATCH" ]]; then
            echo "No forbidden item matches: $PHRASE"
            echo ""
            echo "Current forbidden items:"
            jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
                echo "  ✗ $item"
            done
            exit 1
        fi
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        if ! jq --arg match "$MATCH" --arg ts "$TS" \
            '.guidance.forbidden |= map(select(. != $match)) | .guidance.timestamp = $ts' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
            echo "ERROR: Failed to remove forbidden item (jq error)" >&2
            rm -f "$CONFIG_FILE.tmp"
            exit 1
        fi
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Removed from forbidden list: $MATCH"
        echo "(matched phrase: $PHRASE)"
        echo ""
        echo "Remaining forbidden items:"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        ;;
    "")
        echo "Usage: /ralph:forbid <phrase> | --list | --clear | --remove [phrase]"
        echo ""
        echo "Current forbidden items (HARD BLOCKED):"
        jq -r '.guidance.forbidden[]?' "$CONFIG_FILE" | while read -r item; do
            echo "  ✗ $item"
        done
        ;;
    *)
        # Add item to forbidden list (deduplicated) with timestamp
        # ADR: /docs/adr/2026-01-02-ralph-guidance-freshness-detection.md
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        if ! jq --arg item "$ARGS" --arg ts "$TS" \
            '.guidance.forbidden = ((.guidance.forbidden // []) + [$item] | unique) | .guidance.timestamp = $ts' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
            echo "ERROR: Failed to add forbidden item (jq error)" >&2
            rm -f "$CONFIG_FILE.tmp"
            exit 1
        fi
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
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
3. **All phases**: Guidance appears in both implementation and exploration phases (unified template)
4. **HARD BLOCK**: User-forbidden items get `FilterResult.BLOCK` (not SKIP)
5. **Cannot be fallback**: Unlike built-in busywork, user-forbidden items cannot be chosen as fallback
6. **Persistent**: Settings persist until cleared or session ends

## Interactive Removal (--remove)

When the user runs `/ralph:forbid --remove` without a phrase, use `AskUserQuestion` with `multiSelect: true`:

1. Run the bash script to get the list of items with indices
2. Parse the output to extract items
3. Present items as options in AskUserQuestion
4. After user selects, run `/ralph:forbid --remove-by-index <comma-separated-indices>`

**Example AskUserQuestion**:

```json
{
  "question": "Which forbidden items do you want to remove?",
  "header": "Remove items",
  "options": [
    { "label": "documentation updates", "description": "Index 0" },
    { "label": "refactoring", "description": "Index 1" }
  ],
  "multiSelect": true
}
```

**Fuzzy matching** (`--remove <phrase>`): Finds first item containing the phrase (case-insensitive).

## Template Rendering (v8.7.0+)

The unified Ralph template (`ralph-unified.md`) renders forbidden items in the `## USER GUIDANCE` section:

```markdown
### FORBIDDEN (User-Defined)

**YOU SHALL NOT work on:**

- Your first forbidden item
- Your second forbidden item

⚠️ These are user-specified constraints.
```

This section appears **regardless of phase** (implementation or exploration), ensuring your constraints are always enforced.

## Difference from Built-in Busywork

| Type              | Filter Result    | Behavior                             |
| ----------------- | ---------------- | ------------------------------------ |
| Built-in busywork | SKIP             | Soft-skip, can be chosen as fallback |
| User-forbidden    | BLOCK            | Hard-block, cannot be chosen at all  |
| User-encouraged   | ALLOW (priority) | Always allowed, overrides forbidden  |

## Troubleshooting

| Issue                  | Cause                    | Solution                              |
| ---------------------- | ------------------------ | ------------------------------------- |
| jq error on add        | Config file malformed    | Run `/ralph:config reset` to recreate |
| Item not appearing     | Typo or different casing | Use `--list` to verify exact text     |
| Forbidden not enforced | Ralph not running        | Start with `/ralph:start`             |
| Remove by phrase fails | No match found           | Use `--list` to see exact item names  |
| Config file not found  | .claude dir missing      | Create with `mkdir -p .claude`        |
