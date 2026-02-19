---
name: hooks
description: Install/uninstall hooks for auto-backup on session end. TRIGGERS - hooks, auto backup, session hooks.
allowed-tools: Bash, Read, Write, AskUserQuestion
argument-hint: "[install|uninstall|status] [--backup-on-stop] [--convert-on-stop] [-y|--yes]"
---

# /asciinema-tools:hooks

Manage Claude Code hooks for asciinema-tools automation.

## Arguments

| Argument            | Description                     |
| ------------------- | ------------------------------- |
| `install`           | Add hooks to settings.json      |
| `uninstall`         | Remove asciinema-tools hooks    |
| `status`            | Show current hook configuration |
| `--backup-on-stop`  | Auto-backup when session ends   |
| `--convert-on-stop` | Auto-convert on session end     |
| `-y, --yes`         | Skip confirmation prompts       |

## Hook Definitions

### PostToolUse Hook (backup-on-stop)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "command": "asciinema-backup-if-active"
      }
    ]
  }
}
```

## Execution

### Skip Logic

- If action provided -> execute directly
- If hook type flags provided -> use specific hooks

### Workflow

1. **Status**: Read current ~/.claude/settings.json
2. **Action**: AskUserQuestion for action type
3. **Hooks**: AskUserQuestion for hook selection
4. **Execute**: Modify settings.json
5. **Verify**: Confirm changes applied

## Examples

```bash
# Check current hook status
/asciinema-tools:hooks status

# Install auto-backup hook
/asciinema-tools:hooks install --backup-on-stop

# Install without prompts
/asciinema-tools:hooks install -y

# Remove all asciinema hooks
/asciinema-tools:hooks uninstall
```

## Troubleshooting

| Issue                   | Cause                    | Solution                          |
| ----------------------- | ------------------------ | --------------------------------- |
| jq not found            | jq not installed         | `brew install jq`                 |
| Settings file not found | ~/.claude/ doesn't exist | Create with `mkdir -p ~/.claude`  |
| Hooks not working       | Session not restarted    | Restart Claude Code session       |
| Backup not triggering   | No active recordings     | Start recording first with daemon |
