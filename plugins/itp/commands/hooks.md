---
description: "Install/uninstall itp-hooks to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status|restore [latest|<n>]]"
---

<!--
ADR: 2025-12-07-itp-hooks-settings-installer
-->

# ITP Hooks Manager

Manage itp-hooks installation in `~/.claude/settings.json`.

Claude Code only loads hooks from settings.json, not from plugin.json files. This command installs/uninstalls the itp-hooks (PreToolUse guard and PostToolUse reminder) to your settings.

## Actions

| Action           | Description                         |
| ---------------- | ----------------------------------- |
| `status`         | Show current installation state     |
| `install`        | Add itp-hooks to settings.json      |
| `uninstall`      | Remove itp-hooks from settings.json |
| `restore`        | List available backups with numbers |
| `restore latest` | Restore most recent backup          |
| `restore <n>`    | Restore backup by number            |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
/usr/bin/env bash << 'HOOKS_SCRIPT_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-hooks.sh" $ACTION
HOOKS_SCRIPT_EOF
```

## Post-Action Reminder

After install/uninstall/restore operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.
