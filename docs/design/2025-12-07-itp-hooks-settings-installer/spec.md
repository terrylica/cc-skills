---
adr: 2025-12-07-itp-hooks-settings-installer
source: ~/.claude/plans/proud-doodling-penguin.md
implementation-status: completed
phase: released
last-updated: 2025-12-20
---

# ITP Hooks Settings Installer - Implementation Spec

**ADR**: [ITP Hooks Settings Installer ADR](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)

## Overview

Create `/itp hooks` slash command to install/uninstall itp-hooks to/from `~/.claude/settings.json`.

**Root Cause**: Claude Code only loads hooks from `~/.claude/settings.json`, NOT from plugin.json files.

## Files to Create

| File                                  | Purpose                      |
| ------------------------------------- | ---------------------------- |
| `plugins/itp/commands/hooks.md`       | Slash command entry point    |
| `plugins/itp/scripts/manage-hooks.sh` | Idempotent JSON manipulation |

## Design Principles

1. **Idempotency**: Check state before acting
2. **Atomic writes**: Use temp file + mv pattern
3. **Validation**: Verify JSON validity after modification
4. **Backup with restore**: Timestamped backups
5. **Defensive coding**: Fail fast, never corrupt settings.json

## Command Design

### Arguments

```
/itp hooks [install|uninstall|status|restore [latest|<n>]]
```

| Action           | Description                               |
| ---------------- | ----------------------------------------- |
| `status`         | Show current installation state (default) |
| `install`        | Add itp-hooks to settings.json            |
| `uninstall`      | Remove itp-hooks from settings.json       |
| `restore`        | List available backups with numbers       |
| `restore latest` | Restore most recent backup                |
| `restore <n>`    | Restore backup by number                  |

### Hook Definitions

```json
{
  "PreToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/pretooluse-guard.sh",
          "timeout": 15
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Bash|Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/posttooluse-reminder.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
```

## Implementation Tasks

- [x] Create `manage-hooks.sh` with all functions
- [x] Create `hooks.md` slash command
- [ ] Test install action
- [ ] Test uninstall action
- [ ] Test status action
- [ ] Test restore action

## Script Features

### Core Functions

| Function         | Purpose                                  |
| ---------------- | ---------------------------------------- |
| `do_status()`    | Check if itp-hooks installed, show count |
| `do_install()`   | Add hooks with idempotency check         |
| `do_uninstall()` | Remove hooks by marker pattern           |
| `do_restore()`   | List or restore from backup              |

### Safety Features

| Feature             | Implementation                      |
| ------------------- | ----------------------------------- |
| JSON validation     | `jq empty` before and after         |
| Atomic write        | `mktemp` + `mv`                     |
| Backup              | Timestamped in `~/.claude/backups/` |
| Idempotency         | Check state before action           |
| Script verification | Check `-x` on hook scripts          |

## Success Criteria

- [ ] Install twice = no duplicates
- [ ] Uninstall twice = no error
- [ ] Invalid JSON = fails fast
- [ ] Restore lists backups with numbers
- [ ] `restore latest` works
- [ ] Restart reminder shown after changes
