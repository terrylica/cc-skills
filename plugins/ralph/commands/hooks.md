---
description: "Install/uninstall ralph hooks to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
---

# Ralph Hooks Manager

Manage ralph loop hooks installation in `~/.claude/settings.json`.

Claude Code only loads hooks from settings.json, not from plugin hooks.json files. This command installs/uninstalls the ralph Stop and PreToolUse hooks that enable autonomous loop mode.

## Actions

| Action      | Description                           |
| ----------- | ------------------------------------- |
| `status`    | Show current installation state       |
| `install`   | Add ralph hooks to settings.json      |
| `uninstall` | Remove ralph hooks from settings.json |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-hooks.sh" $ACTION
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.
