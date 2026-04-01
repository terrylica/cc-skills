---
name: setup
description: "Configure statusline-tools status line and dependencies. TRIGGERS - statusline setup, install statusline, configure status bar, statusline deps."
allowed-tools: Read, Bash, TodoWrite, TodoRead, AskUserQuestion
argument-hint: "[install|uninstall|status]"
model: haiku
disable-model-invocation: false
---

# Status Line Setup

Manage custom status line installation and dependencies.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Actions

| Action      | Description                                 |
| ----------- | ------------------------------------------- |
| `install`   | Install status line to settings.json        |
| `uninstall` | Remove status line from settings.json       |
| `status`    | Show current configuration and dependencies |

## Execution

### Skip Logic

- If action provided (`install`, `uninstall`, `status`) -> execute directly
- If no arguments -> check current status, then use AskUserQuestion flow

### Workflow

1. **Check Current State**: Run `status` to show current configuration
2. **Action Selection**: Use AskUserQuestion to select action:
   - "Install status line" -> configure settings.json
   - "Uninstall status line" -> remove configuration
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

| Issue                 | Cause                   | Solution                                |
| --------------------- | ----------------------- | --------------------------------------- |
| Status line not shown | Session not restarted   | Exit and restart Claude Code            |
| Settings file missing | ~/.claude doesn't exist | Create with `mkdir -p ~/.claude`        |
| Install fails         | Invalid settings.json   | Validate JSON with `jq . settings.json` |
| Script not found      | Plugin not installed    | Reinstall plugin from marketplace       |


## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
