# Phase 1: Scaffold Plugin (Detailed)

## 1.1 Invoke plugin-structure Skill

**MANDATORY Skill tool call: `plugin-dev:plugin-structure`** -- activate NOW.

This skill provides:

- Directory structure patterns
- plugin.json template
- README.md template

## 1.2 Create Plugin Directory

```bash
# Create plugin directory structure
mkdir -p plugins/$PLUGIN_NAME

# If has-skills:
mkdir -p plugins/$PLUGIN_NAME/skills

# If has-hooks:
mkdir -p plugins/$PLUGIN_NAME/hooks

# If has-commands:
mkdir -p plugins/$PLUGIN_NAME/commands

# If has-agents:
mkdir -p plugins/$PLUGIN_NAME/agents
```

## 1.3 Generate plugin.json

Get version from marketplace for consistency:

```bash
/usr/bin/env bash << 'PLUGIN_ADD_SCRIPT_EOF_3'
MARKETPLACE_VERSION=$(jq -r .version .claude-plugin/marketplace.json)
PLUGIN_ADD_SCRIPT_EOF_3
```

Create `plugins/$PLUGIN_NAME/plugin.json`:

```json
{
  "name": "$PLUGIN_NAME",
  "version": "$MARKETPLACE_VERSION",
  "description": "TODO: Add description",
  "author": {
    "name": "Terry Li",
    "url": "https://github.com/terrylica"
  }
}
```

## 1.4 Create ADR and Design Spec

**MANDATORY Skill tool call: `itp:implement-plan-preflight`** -- activate NOW.

This skill:

- Creates ADR at `docs/adr/YYYY-MM-DD-$PLUGIN_NAME.md`
- Creates Design Spec at `docs/design/YYYY-MM-DD-$PLUGIN_NAME/spec.md`

**ADR ID Format:**

```bash
/usr/bin/env bash << 'PLUGIN_ADD_SCRIPT_EOF_4'
ADR_ID="$(date +%Y-%m-%d)-$PLUGIN_NAME"
PLUGIN_ADD_SCRIPT_EOF_4
```

## Phase 1 Gate

**STOP. Verify before proceeding to Phase 2:**

- [ ] Plugin directory exists: `plugins/$PLUGIN_NAME/`
- [ ] plugin.json created with marketplace version
- [ ] ADR exists: `docs/adr/$ADR_ID.md`
- [ ] Design spec exists: `docs/design/$ADR_ID/spec.md`
- [ ] Both diagrams in ADR (Before/After + Architecture)
