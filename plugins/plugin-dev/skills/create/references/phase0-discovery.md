# Phase 0: Discovery & Validation (Detailed)

## 0.1 Verify Marketplace Root

First, confirm we're in a marketplace directory:

```bash
/usr/bin/env bash << 'PLUGIN_ADD_SCRIPT_EOF'
# Must have .claude-plugin/marketplace.json
ls -la .claude-plugin/marketplace.json

# Extract marketplace info
MARKETPLACE_NAME=$(jq -r .name .claude-plugin/marketplace.json)
MARKETPLACE_VERSION=$(jq -r .version .claude-plugin/marketplace.json)
echo "Marketplace: $MARKETPLACE_NAME v$MARKETPLACE_VERSION"
PLUGIN_ADD_SCRIPT_EOF
```

## 0.2 Interactive Prompts

Use AskUserQuestion to gather plugin details:

**Q1: Plugin Name** (if not provided as argument)

```
AskUserQuestion with questions:
- question: "What should this plugin be called? Use kebab-case (e.g., 'my-plugin-name')"
  header: "Plugin Name"
  options:
    - label: "Custom name"
      description: "Enter a kebab-case plugin name"
  multiSelect: false
```

**Q2: Category**

```
AskUserQuestion with questions:
- question: "What category does this plugin belong to?"
  header: "Category"
  options:
    - label: "development (Recommended)"
      description: "Tools for developers"
    - label: "productivity"
      description: "Workflow automation"
    - label: "devops"
      description: "Infrastructure & operations"
    - label: "documents"
      description: "Documentation tools"
  multiSelect: false
```

**Q3: Components**

```
AskUserQuestion with questions:
- question: "What components will this plugin include?"
  header: "Components"
  options:
    - label: "Skills"
      description: "Domain knowledge & capabilities (SKILL.md files)"
    - label: "Hooks"
      description: "Event-driven automation (hooks.json)"
    - label: "Commands"
      description: "Slash commands (commands/*.md)"
    - label: "Agents"
      description: "Autonomous subagents (agents/*.md)"
  multiSelect: true
```

**Store responses:**

```bash
/usr/bin/env bash << 'PLUGIN_ADD_SCRIPT_EOF_2'
PLUGIN_NAME="${ARGUMENTS:-<from-q1>}"
PLUGIN_CATEGORY="<from-q2>"
HAS_SKILLS=<true|false>
HAS_HOOKS=<true|false>
HAS_COMMANDS=<true|false>
HAS_AGENTS=<true|false>
PLUGIN_ADD_SCRIPT_EOF_2
```

## 0.3 Confirm Plugin Doesn't Exist

```bash
# Check if plugin directory already exists
if [ -d "plugins/$PLUGIN_NAME" ]; then
  echo "❌ Plugin already exists: plugins/$PLUGIN_NAME"
  exit 1
fi

# Check if already in marketplace.json
if jq -e ".plugins[] | select(.name == \"$PLUGIN_NAME\")" .claude-plugin/marketplace.json > /dev/null 2>&1; then
  echo "❌ Plugin already registered in marketplace.json: $PLUGIN_NAME"
  exit 1
fi

echo "✅ Plugin name '$PLUGIN_NAME' is available"
```

## Phase 0 Gate

**STOP. Verify before proceeding to Phase 1:**

- [ ] Marketplace root detected (`.claude-plugin/marketplace.json` exists)
- [ ] Plugin name collected (kebab-case, no spaces)
- [ ] Category selected
- [ ] Components selected (skills/hooks/commands/agents)
- [ ] Plugin directory does NOT exist
- [ ] Plugin NOT in marketplace.json
