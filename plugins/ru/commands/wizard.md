---
description: Interactive guidance setup with AskUserQuestion flow
allowed-tools: Bash, AskUserQuestion
argument-hint: ""
---

# RU: Wizard

Interactive configuration wizard using AskUserQuestion to set up forbidden and encouraged items.

## Step 1: Common Busywork Categories

Use AskUserQuestion to let user select common items to FORBID (things RU should avoid):

```yaml
questions:
  - question: "What should RU avoid working on? (Select all that apply)"
    header: "Forbid"
    multiSelect: true
    options:
      - label: "Documentation updates"
        description: "README, docstrings, comments"
      - label: "Dependency upgrades"
        description: "Version bumps, lock file updates"
      - label: "Code style/formatting"
        description: "Linting, prettier, whitespace"
      - label: "Test coverage expansion"
        description: "Adding tests for existing code"
```

## Step 2: Custom Forbidden Items

Use AskUserQuestion to get custom forbidden items:

```yaml
questions:
  - question: "Any specific topics to forbid? (e.g., 'database migrations', 'API changes')"
    header: "Custom"
    multiSelect: false
    options:
      - label: "No additional items"
        description: "Skip custom forbidden items"
      - label: "Add custom items"
        description: "I'll type specific items to forbid"
```

If user selects "Add custom items", prompt for text input.

## Step 3: Focus Areas (Encouraged)

Use AskUserQuestion to let user select what RU should PRIORITIZE:

```yaml
questions:
  - question: "What should RU prioritize? (Select all that apply)"
    header: "Encourage"
    multiSelect: true
    options:
      - label: "Bug fixes"
        description: "Fix errors, exceptions, crashes"
      - label: "Performance improvements"
        description: "Speed, memory, efficiency"
      - label: "Security hardening"
        description: "Input validation, auth, secrets"
      - label: "Error handling"
        description: "Try/catch, edge cases, validation"
```

## Step 4: Custom Encouraged Items

Use AskUserQuestion to get custom encouraged items:

```yaml
questions:
  - question: "Any specific topics to prioritize? (e.g., 'payment flow', 'user auth')"
    header: "Custom"
    multiSelect: false
    options:
      - label: "No additional items"
        description: "Skip custom encouraged items"
      - label: "Add custom items"
        description: "I'll type specific items to prioritize"
```

## Step 5: Save Configuration

After collecting all selections, run this script to save:

```bash
/usr/bin/env bash << 'RU_CONFIGURE_SAVE'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ru-config.json"

# Ensure config file exists with guidance structure
mkdir -p "$PROJECT_DIR/.claude"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"guidance": {"forbidden": [], "encouraged": []}}' > "$CONFIG_FILE"
fi

# Ensure guidance structure exists
if ! jq -e '.guidance' "$CONFIG_FILE" >/dev/null 2>&1; then
    jq '. + {guidance: {forbidden: [], encouraged: []}}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

echo "Configuration saved to: $CONFIG_FILE"
echo ""
echo "Current guidance:"
echo "  Forbidden: $(jq -r '.guidance.forbidden | length' "$CONFIG_FILE") items"
echo "  Encouraged: $(jq -r '.guidance.encouraged | length' "$CONFIG_FILE") items"
echo ""
echo "To view: /ru:config show"
echo "To modify: /ru:forbid or /ru:encourage"
RU_CONFIGURE_SAVE
```

## Execution Flow

1. **Execute Step 1** - Show multiSelect for common forbidden items
2. **Process selections** - Add each selected item to forbidden list via bash
3. **Execute Step 2** - Ask about custom forbidden items
4. **If custom selected** - Use text input to get items, add to forbidden list
5. **Execute Step 3** - Show multiSelect for common encouraged items
6. **Process selections** - Add each selected item to encouraged list via bash
7. **Execute Step 4** - Ask about custom encouraged items
8. **If custom selected** - Use text input to get items, add to encouraged list
9. **Execute Step 5** - Save and display summary

## Adding Items Helper

Use this bash snippet to add items from AskUserQuestion selections:

```bash
/usr/bin/env bash << 'ADD_GUIDANCE_ITEMS'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ru-config.json"
TYPE="${1:-forbidden}"  # "forbidden" or "encouraged"
ITEMS="${2:-}"          # Space-separated items

# Ensure file exists
mkdir -p "$PROJECT_DIR/.claude"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"guidance": {"forbidden": [], "encouraged": []}}' > "$CONFIG_FILE"
fi

# Add each item
for ITEM in $ITEMS; do
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg item "$ITEM" --arg ts "$TIMESTAMP" \
        ".guidance.${TYPE} = ((.guidance.${TYPE} // []) + [\$item] | unique) | .guidance.timestamp = \$ts" \
        "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
done

echo "Added $(echo $ITEMS | wc -w | tr -d ' ') items to $TYPE list"
ADD_GUIDANCE_ITEMS
```
