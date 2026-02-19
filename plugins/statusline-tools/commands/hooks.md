---
name: hooks
description: "Install/uninstall statusline-tools Stop hook to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead, AskUserQuestion
argument-hint: "[install|uninstall|status]"
model: haiku
---

# Status Line Hooks Manager

Manage Stop hook installation for link validation and path linting.

The Stop hook runs at session end to:

1. Validate markdown links using lychee
2. Check for relative path violations using lint-relative-paths
3. Cache results for status line display

## Actions

| Action      | Description                         |
| ----------- | ----------------------------------- |
| `install`   | Add Stop hook to settings.json      |
| `uninstall` | Remove Stop hook from settings.json |
| `status`    | Show current hook configuration     |

## Coexistence Note

This hook can coexist with other Stop hooks (like check-links-hybrid.sh). Both will run on session end - statusline-tools caches results for display, while other hooks may take different actions.

## Execution

### Skip Logic

- If action provided (`install`, `uninstall`, `status`) -> execute directly
- If no arguments -> check current status, then use AskUserQuestion flow

### Workflow

1. **Check Current State**: Run `status` to show current hook configuration
2. **Action Selection**: Use AskUserQuestion to select action:
   - "Install hook" -> add Stop hook for link validation
   - "Uninstall hook" -> remove Stop hook
   - "Just show status" -> display and exit
3. **Execute**: Run the management script
4. **Verify**: Confirm changes applied

### AskUserQuestion Flow (No Arguments)

When invoked without arguments, guide the user interactively:

```
Question: "What would you like to do with the statusline-tools Stop hook?"
Options:
  - "Install" -> "Add Stop hook for link validation and path linting on session end"
  - "Uninstall" -> "Remove the Stop hook from settings.json"
  - "Status" -> "Show current hook configuration"
```

### Direct Execution (With Arguments)

Parse `$ARGUMENTS` and run the management script:

```bash
/usr/bin/env bash << 'HOOKS_SCRIPT_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-hooks.sh" $ACTION
HOOKS_SCRIPT_EOF
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

Hooks are loaded at session start. Modifications to settings.json require a restart.

## Examples

```bash
# Check current installation status
/statusline-tools:hooks status

# Install the Stop hook for link validation
/statusline-tools:hooks install

# Uninstall hooks
/statusline-tools:hooks uninstall
```

## Troubleshooting

| Issue                      | Cause                        | Solution                           |
| -------------------------- | ---------------------------- | ---------------------------------- |
| jq not found               | jq not installed             | `brew install jq`                  |
| lychee not found           | Link validator not installed | `brew install lychee`              |
| Hooks not working          | Session not restarted        | Restart Claude Code session        |
| lint-relative-paths errors | Invalid path patterns        | Check file paths in SKILL.md files |
| Cache stale                | Stop hook failed             | Check ~/.claude/statusline/ logs   |
