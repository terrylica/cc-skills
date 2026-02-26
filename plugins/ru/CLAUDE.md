# ru Plugin

> RU - autonomous loop mode for any project. Commands: /ru:start, /ru:stop, /ru:status.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp CLAUDE.md](../itp/CLAUDE.md)

## Overview

Autonomous improvement loop for any project. Short name for quick invocation. Runs tasks → pivots to exploration → finds new improvements → repeats until limits reached.

## Commands

| Command         | Purpose                                     |
| --------------- | ------------------------------------------- |
| `/ru:start`     | Start loop with interactive guidance setup  |
| `/ru:stop`      | Stop the loop immediately                   |
| `/ru:status`    | Show current state                          |
| `/ru:wizard`    | Interactive wizard for forbidden/encouraged |
| `/ru:forbid`    | Add item to forbidden list                  |
| `/ru:encourage` | Add item to encouraged list                 |
| `/ru:config`    | View or modify configuration                |
| `/ru:audit-now` | Force immediate validation round            |
| `/ru:hooks`     | Install/uninstall hooks                     |

## Hooks

Activation-gated design — hooks only fire when the loop is active (`ru-state.json` has `"state": "running"`).

| Hook                               | Event      | Matcher     | Purpose                              |
| ---------------------------------- | ---------- | ----------- | ------------------------------------ |
| `loop-until-done-wrapper.sh`       | Stop       | (all)       | Continues loop if state is `running` |
| `archive-plan.sh`                  | PreToolUse | Write\|Edit | Archives plan file before overwrite  |
| `pretooluse-loop-guard-wrapper.sh` | PreToolUse | Bash        | Enforces loop boundaries             |

## State Files

| File                     | Purpose                      |
| ------------------------ | ---------------------------- |
| `.claude/ru-state.json`  | Current loop state           |
| `.claude/ru-config.json` | Configuration and guidance   |
| `.claude/STOP_LOOP`      | Kill switch (emergency stop) |

## Architecture

```
Stop Event → wrapper.sh (activation gate, <1ms if inactive) → loop-until-done.ts (Bun)
  → State machine: RUNNING → DRAINING → STOPPED
  → Template rendering (LiquidJS) with forbidden[]/encouraged[]
```
