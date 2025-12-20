# Ralph Plugin for Claude Code

Keep Claude Code working autonomously until tasks are complete - implements the Ralph Wiggum technique as Claude Code hooks.

## What This Plugin Does

This plugin adds autonomous loop mode to Claude Code through 5 commands and 2 hooks:

**Commands:**

- `/ralph:start` - Enable loop mode (Claude continues working)
- `/ralph:stop` - Disable loop mode immediately
- `/ralph:status` - Show current loop state and metrics
- `/ralph:config` - View/modify runtime limits
- `/ralph:hooks` - Install/uninstall hooks to settings.json

**Hooks:**

- **Stop hook** (`loop-until-done.py`) - Prevents Claude from stopping until task is complete
- **PreToolUse hook** (`archive-plan.sh`) - Archives `.claude/plans/*.md` files before overwrite

## Quick Start

```bash
# 1. Install hooks
/ralph:hooks install

# 2. Restart Claude Code (hooks load at startup)

# 3. Start the loop
/ralph:start

# Claude will now continue working until:
# - [x] TASK_COMPLETE marker is checked in plan file
# - Maximum time limit reached (default: 9 hours)
# - Maximum iterations reached (default: 99)
# - You run /ralph:stop
```

## How It Works

The plugin implements autonomous operation through hooks:

1. **Stop Hook Logic:**
   - Checks elapsed time and iteration count
   - Detects completion markers (`[x] TASK_COMPLETE`)
   - Prevents infinite loops (similarity detection via RapidFuzz)
   - Blocks premature stops until minimum thresholds are met

2. **PreToolUse Hook:**
   - Archives plan files before modification
   - Preserves investigation history and decision trail
   - Enables recovery from dead ends

3. **Configuration:**
   - Project-level: `.claude/loop-config.json`
   - Global defaults: `~/.claude/automation/loop-orchestrator/config/loop_config.json`
   - POC mode: `--poc` flag for short test runs (5-10 min, 10-20 iterations)

## Files

```
ralph/
├── README.md                   # This file
├── commands/                   # Slash commands
│   ├── start.md
│   ├── stop.md
│   ├── status.md
│   ├── config.md
│   └── hooks.md
├── hooks/                      # Hook implementations
│   ├── hooks.json              # Hook registration
│   ├── loop-until-done.py      # Stop hook
│   └── archive-plan.sh         # PreToolUse hook
└── scripts/
    └── manage-hooks.sh         # Hook installation script
```

## Related

- [Geoffrey Huntley's Article](https://ghuntley.com/ralph/) - Original technique
