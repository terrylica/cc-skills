---
description: "Configure statusline-tools status line and dependencies"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status|deps|sync]"
---

# Status Line Setup

Manage custom status line installation and dependencies.

## Actions

| Action      | Description                                              |
| ----------- | -------------------------------------------------------- |
| `install`   | Install status line to settings.json                     |
| `uninstall` | Remove status line from settings.json                    |
| `status`    | Show current configuration and dependencies              |
| `deps`      | Install lychee via mise                                  |
| `sync`      | Create symlink at ~/.config/ccstatusline/ (auto-updates) |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-statusline.sh" $ACTION
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The statusLine is loaded at session start. Modifications to settings.json require a restart.
