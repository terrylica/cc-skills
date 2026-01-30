# RU (Ralph Universal)

Autonomous loop mode for **any project** - short name for quick invocation.

## Quick Start

```bash
# Install hooks
/ru:hooks install

# Restart Claude Code (hooks only load at startup)

# Start the loop
/ru:start --poc

# Configure what to work on
/ru:encourage test coverage
/ru:forbid refactoring

# Stop the loop
/ru:stop
```

## Commands

| Command         | Description                                  |
| --------------- | -------------------------------------------- |
| `/ru:start`     | Enable loop mode (POC or Production presets) |
| `/ru:stop`      | Disable loop mode immediately                |
| `/ru:status`    | Show current state                           |
| `/ru:forbid`    | Add item to forbidden list                   |
| `/ru:encourage` | Add item to encouraged list                  |
| `/ru:config`    | View or modify configuration                 |
| `/ru:audit-now` | Force immediate validation round             |
| `/ru:hooks`     | Install/uninstall hooks                      |

## Configuring Guidance

Control what the loop works on:

```bash
# Add items to work on
/ru:encourage test coverage
/ru:encourage documentation

# Block certain work
/ru:forbid refactoring
/ru:forbid dependency updates

# List current configuration
/ru:forbid --list
/ru:encourage --list

# Clear all
/ru:forbid --clear
```

## Configuration

```bash
# Show current config
/ru:config show

# Set a value
/ru:config set loop_limits.min_hours=2

# Reset to defaults
/ru:config reset
```

## State Files

| File                     | Purpose                      |
| ------------------------ | ---------------------------- |
| `.claude/ru-state.json`  | Current loop state           |
| `.claude/ru-config.json` | Configuration and guidance   |
| `.claude/STOP_LOOP`      | Kill switch (emergency stop) |

## Why "RU"?

Short for "Ralph Universal" - designed for quick typing:

- `/ru:start` instead of `/ralph-universal:start`
- All commands are 2-4 keystrokes shorter

## What It Does

RU runs an autonomous improvement loop on your project:

1. Works on tasks until complete
2. Pivots to exploration when done
3. Finds new improvement opportunities
4. Repeats until time/iteration limits reached
