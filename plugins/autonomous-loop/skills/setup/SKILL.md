---
name: setup
description: "Manage hook installation and uninstallation for autonomous-loop heartbeat. Install or remove the PostToolUse hook from ~/.claude/settings.json."
allowed-tools: Bash, Read, Write, AskUserQuestion
argument-hint: "[install|uninstall|status]"
disable-model-invocation: false
---

# autonomous-loop: Setup

Manage the heartbeat hook installation for autonomous-loop. This skill allows explicit control over when the hook is installed or uninstalled from `~/.claude/settings.json`.

## Arguments

- Optional: `install`, `uninstall`, or `status`. Defaults to `status`.

## Step 1: Determine action

If no argument provided, use `AskUserQuestion` to present three options:

- **Check current status** — Display whether hook is installed
- **Install the hook** — Add heartbeat hook to settings.json (idempotent)
- **Uninstall the hook** — Remove heartbeat hook from settings.json (idempotent)

Otherwise, use the provided argument (`install`, `uninstall`, or `status`).

## Step 2: Check current install status

```bash
# Source the hook install library
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
source "$PLUGIN_ROOT/scripts/hook-install-lib.sh"

# Check installation status
SETTINGS_PATH="$HOME/.claude/settings.json"
INSTALLED=$(is_hook_installed "$SETTINGS_PATH")

if [ "$INSTALLED" = "yes" ]; then
  echo "✓ Hook is currently INSTALLED"
  echo "  Path: $SETTINGS_PATH"
else
  echo "✗ Hook is currently NOT INSTALLED"
  echo "  Path: $SETTINGS_PATH"
fi
```

## Step 3: Perform requested action

### If action is `install`

```bash
if [ "$(is_hook_installed "$SETTINGS_PATH")" = "yes" ]; then
  echo "Hook already installed; no action needed"
  exit 0
fi

if install_hook "$SETTINGS_PATH"; then
  echo "✓ Hook installed successfully"
  echo "  The heartbeat will now tick on each tool invocation"
else
  echo "✗ Failed to install hook"
  exit 1
fi
```

### If action is `uninstall`

```bash
if [ "$(is_hook_installed "$SETTINGS_PATH")" = "no" ]; then
  echo "Hook not installed; no action needed"
  exit 0
fi

if uninstall_hook "$SETTINGS_PATH"; then
  echo "✓ Hook uninstalled successfully"
  echo "  The heartbeat will no longer tick on tool invocations"
else
  echo "✗ Failed to uninstall hook"
  exit 1
fi
```

### If action is `status`

Report installation status (already done in Step 2). No further action.

## Anti-patterns

- Do NOT force-uninstall when there are active loops — recommend stopping the loop first
- Do NOT install the hook into a malformed settings.json — report the error and ask user to fix it manually

## Troubleshooting

| Symptom                      | Fix                                                        |
| ---------------------------- | ---------------------------------------------------------- |
| "settings.json is malformed" | Manually edit `~/.claude/settings.json` to fix JSON syntax |
| "Hook not found"             | Reinstall the autonomous-loop plugin                       |
| Lock contention error        | Wait a few seconds; another process is updating settings   |

## Implementation Notes

- All operations use `_with_settings_lock` internally for concurrency safety
- Install is idempotent; running twice in a row has no effect
- Uninstall is idempotent; no error if hook is not present
- Backup is created on first install to `~/.claude/.settings.backup.<timestamp>.json`
