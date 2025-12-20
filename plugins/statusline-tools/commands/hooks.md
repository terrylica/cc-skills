---
description: "Install/uninstall statusline-tools Stop hook to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
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

Parse `$ARGUMENTS` and run the management script:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-hooks.sh" $ACTION
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

Hooks are loaded at session start. Modifications to settings.json require a restart.
