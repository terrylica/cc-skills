---
description: "Install/uninstall git-account-validator hooks to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
---

# Git Account Validator Hooks Manager

Manage git push validation hooks installation in `~/.claude/settings.json`.

Claude Code only loads hooks from settings.json, not from plugin hooks.json files. This command installs/uninstalls the PreToolUse hook that validates git push operations for multi-account authentication.

## Actions

| Action      | Description                                     |
| ----------- | ----------------------------------------------- |
| `status`    | Show current installation state                 |
| `install`   | Add git-account-validator hook to settings.json |
| `uninstall` | Remove hook from settings.json                  |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/git-account-validator}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-hooks.sh" $ACTION
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.
