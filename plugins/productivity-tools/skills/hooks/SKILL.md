---
name: hooks
description: "Install/uninstall productivity-tools hooks to ~/.claude/settings.json. TRIGGERS - productivity hooks, install productivity hook, calendar alarm hook."
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
model: haiku
---

# productivity-tools Hooks Manager

Manage productivity-tools hook installation in `~/.claude/settings.json`.

The calendar-reminder-sync hook validates sound alarm compliance on Calendar event creation and auto-creates paired Reminders.

## Actions

| Action      | Description                                        |
| ----------- | -------------------------------------------------- |
| `status`    | Check hook installation status and dependencies    |
| `install`   | Add productivity-tools hooks to settings.json      |
| `uninstall` | Remove productivity-tools hooks from settings.json |

## What the Hook Does

| Trigger          | Condition                      | Action                                             |
| ---------------- | ------------------------------ | -------------------------------------------------- |
| PostToolUse/Bash | `osascript` + `make new event` | Validates sound alarms, auto-creates 3 Reminders   |
| PostToolUse/Bash | Missing sound alarms           | Warns Claude to recreate with `sound alarm`        |
| PostToolUse/Bash | Banned short sounds used       | Warns Claude to use only approved sounds (>= 1.4s) |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
/usr/bin/env bash << 'PRODUCTIVITY_TOOLS_HOOKS_SCRIPT'
set -euo pipefail

ACTION="${ARGUMENTS:-status}"

# Auto-detect plugin root
detect_plugin_root() {
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi
    local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/productivity-tools"
    if [[ -d "$marketplace/hooks" ]]; then
        echo "$marketplace"
        return
    fi
    local cache_base="$HOME/.claude/plugins/cache/cc-skills/productivity-tools"
    if [[ -d "$cache_base" ]]; then
        local latest
        latest=$(ls -1 "$cache_base" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [[ -n "$latest" && -d "$cache_base/$latest/hooks" ]]; then
            echo "$cache_base/$latest"
            return
        fi
    fi
    echo ""
}

PLUGIN_DIR="$(detect_plugin_root)"
if [[ -z "$PLUGIN_DIR" ]]; then
    echo "ERROR: Cannot detect productivity-tools plugin installation" >&2
    exit 1
fi

bash "$PLUGIN_DIR/scripts/manage-hooks.sh" "$ACTION"
PRODUCTIVITY_TOOLS_HOOKS_SCRIPT
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.

## Examples

```bash
# Check current installation status
/productivity-tools:hooks status

# Install the calendar-reminder-sync hook
/productivity-tools:hooks install

# Uninstall hooks
/productivity-tools:hooks uninstall
```

## Troubleshooting

| Issue                   | Cause                  | Solution                                             |
| ----------------------- | ---------------------- | ---------------------------------------------------- |
| jq not found            | jq not installed       | `brew install jq`                                    |
| bun not found           | bun not installed      | `brew install bun`                                   |
| Plugin root not found   | Plugin not installed   | Re-install via marketplace                           |
| Hooks not working       | Session not restarted  | Restart Claude Code session                          |
| Reminders not created   | Hook not installed     | Run `/productivity-tools:hooks install`              |
| Sound alarm not playing | Notifications disabled | Enable in System Settings > Notifications > Calendar |
