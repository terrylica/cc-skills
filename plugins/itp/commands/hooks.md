---
name: hooks
description: "Install/uninstall itp-hooks (ASCII guard, ADR sync reminder, fake-data-guard) to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status|restore [latest|<n>]]"
---

<!--
ADR: 2025-12-07-itp-hooks-settings-installer
-->

# ITP Hooks Manager

Manage itp-hooks installation in `~/.claude/settings.json`.

Claude Code only loads hooks from settings.json, not from plugin.json files. This command installs/uninstalls three itp-hooks:

- **PreToolUse guard** - Blocks ASCII diagrams without graph-easy source blocks
- **PostToolUse reminder** - Prompts ADR/spec sync after file modifications
- **Fake-data-guard** - Detects fake/synthetic data patterns (np.random, Faker, etc.) in new Python files

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

## Examples

```bash
# Check current installation status
/itp:hooks status

# Install all itp-hooks
/itp:hooks install

# Uninstall hooks
/itp:hooks uninstall

# List available backups
/itp:hooks restore

# Restore most recent backup
/itp:hooks restore latest
```

## Troubleshooting

| Issue             | Cause                    | Solution                           |
| ----------------- | ------------------------ | ---------------------------------- |
| jq not found      | jq not installed         | `brew install jq`                  |
| bun not found     | bun/node not installed   | `mise install bun`                 |
| Already installed | Hook already in settings | Run `uninstall` first to reinstall |
| Hooks not working | Session not restarted    | Restart Claude Code session        |
| Script not found  | Plugin not installed     | Re-install plugin via marketplace  |
| Invalid JSON      | Corrupted settings.json  | Use `restore latest` to recover    |
