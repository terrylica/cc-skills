# RU

Autonomous loop mode for **any project** - short name for quick invocation.

## Quick Start

```bash
# Start with interactive guidance setup
/ru:start

# Or skip guidance setup
/ru:start --poc --quick

# Stop the loop
/ru:stop
```

## Commands

| Command         | Description                                 |
| --------------- | ------------------------------------------- |
| `/ru:start`     | Start loop with interactive guidance setup  |
| `/ru:stop`      | Stop the loop immediately                   |
| `/ru:status`    | Show current state                          |
| `/ru:configure` | Interactive wizard for forbidden/encouraged |
| `/ru:forbid`    | Add item to forbidden list                  |
| `/ru:encourage` | Add item to encouraged list                 |
| `/ru:config`    | View or modify configuration                |
| `/ru:audit-now` | Force immediate validation round            |
| `/ru:hooks`     | Install/uninstall hooks                     |

## Interactive Guidance Setup

When you run `/ru:start`, you'll see AskUserQuestion prompts:

1. **Mode Selection** - POC (5-10 min) or Production (4-9 hours)
2. **Forbidden Items** - What should RU avoid? (multiselect)
3. **Encouraged Items** - What should RU prioritize? (multiselect)

Use `--quick` to skip guidance and use existing config.

## Manual Guidance

```bash
# Add items to work on
/ru:encourage bug fixes
/ru:encourage performance

# Block certain work
/ru:forbid documentation
/ru:forbid dependency upgrades

# List current configuration
/ru:forbid --list
/ru:encourage --list

# Interactive reconfiguration
/ru:configure
```

## State Files

| File                     | Purpose                      |
| ------------------------ | ---------------------------- |
| `.claude/ru-state.json`  | Current loop state           |
| `.claude/ru-config.json` | Configuration and guidance   |
| `.claude/STOP_LOOP`      | Kill switch (emergency stop) |

## What It Does

RU runs an autonomous improvement loop on your project:

1. Works on tasks until complete
2. Pivots to exploration when done
3. Finds new improvement opportunities
4. Repeats until time/iteration limits reached
