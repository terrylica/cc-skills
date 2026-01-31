---
description: "Configure statusline-tools status line and dependencies"
allowed-tools: Read, Bash, TodoWrite, TodoRead, AskUserQuestion
argument-hint: "[install|uninstall|status|deps]"
---

# Status Line Setup

Manage custom status line installation and dependencies.

## Actions

| Action      | Description                                 |
| ----------- | ------------------------------------------- |
| `install`   | Install status line to settings.json        |
| `uninstall` | Remove status line from settings.json       |
| `status`    | Show current configuration and dependencies |
| `deps`      | Install lychee via mise                     |

## Execution

### Skip Logic

- If action provided (`install`, `uninstall`, `status`, `deps`) -> execute directly
- If no arguments -> check current status, then use AskUserQuestion flow

### Workflow

1. **Check Current State**: Run `status` to show current configuration
2. **Action Selection**: Use AskUserQuestion to select action:
   - "Install status line" -> configure settings.json
   - "Uninstall status line" -> remove configuration
   - "Install dependencies" -> install lychee via mise
   - "Just show status" -> display and exit
3. **Execute**: Run the management script
4. **Verify**: Confirm changes applied

### AskUserQuestion Flow (No Arguments)

When invoked without arguments, guide the user interactively:

```
Question: "What would you like to do with statusline-tools?"
Options:
  - "Install" -> "Install the custom status line to settings.json"
  - "Uninstall" -> "Remove the status line configuration"
  - "Install deps" -> "Install lychee for link validation via mise"
  - "Status" -> "Show current configuration and dependencies"
```

### Direct Execution (With Arguments)

Parse `$ARGUMENTS` and run the management script:

```bash
/usr/bin/env bash << 'SETUP_SCRIPT_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
ACTION="${ARGUMENTS:-status}"
bash "$PLUGIN_DIR/scripts/manage-statusline.sh" $ACTION
SETUP_SCRIPT_EOF
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The statusLine is loaded at session start. Modifications to settings.json require a restart.

## Troubleshooting

| Issue                 | Cause                   | Solution                                 |
| --------------------- | ----------------------- | ---------------------------------------- |
| Status line not shown | Session not restarted   | Exit and restart Claude Code             |
| lychee not found      | mise not installed      | Install mise from <https://mise.jdx.dev> |
| Settings file missing | ~/.claude doesn't exist | Create with `mkdir -p ~/.claude`         |
| Install fails         | Invalid settings.json   | Validate JSON with `jq . settings.json`  |
| Script not found      | Plugin not installed    | Reinstall plugin from marketplace        |
