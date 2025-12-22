---
description: "Install/uninstall itp-hooks to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
---

# ITP Hooks Manager

Manage ITP workflow hooks installation in `~/.claude/settings.json`.

Claude Code only loads hooks from settings.json, not from plugin hooks.json files. This command installs/uninstalls the ITP PreToolUse and PostToolUse hooks.

## Actions

| Action      | Description                         |
| ----------- | ----------------------------------- |
| `status`    | Show current installation state     |
| `install`   | Add itp-hooks to settings.json      |
| `uninstall` | Remove itp-hooks from settings.json |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
/usr/bin/env bash << 'HOOKS_SCRIPT_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-hooks.sh" $ACTION
HOOKS_SCRIPT_EOF
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.
