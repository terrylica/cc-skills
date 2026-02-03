# RU

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Commands](https://img.shields.io/badge/Commands-9-green.svg)]()
[![Hooks](https://img.shields.io/badge/Hooks-3-orange.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Autonomous loop mode for **any project** - short name for quick invocation.

## Installation

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install ru@cc-skills
```

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
| `/ru:wizard`    | Interactive wizard for forbidden/encouraged |
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
/ru:wizard
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

## Hooks

RU uses an **activation-gated design** - hooks only fire when the loop is active.

| Hook                               | Event      | Matcher     | Purpose                              |
| ---------------------------------- | ---------- | ----------- | ------------------------------------ |
| `loop-until-done-wrapper.sh`       | Stop       | (all)       | Continues loop if state is `running` |
| `archive-plan.sh`                  | PreToolUse | Write\|Edit | Archives plan file before overwrite  |
| `pretooluse-loop-guard-wrapper.sh` | PreToolUse | Bash        | Enforces loop boundaries             |

### Activation Check

All hooks check for `$PROJECT/.claude/ru-state.json`:

```json
{ "state": "running", "iteration": 36, "startTime": "2026-01-30T..." }
```

If state is not `running`, hooks exit silently (no-op).

### Stop Hook: Loop Continuation

When Claude reaches a natural stop point:

1. Hook checks `ru-state.json` for `state: running`
2. If running, increments iteration counter
3. Injects continuation prompt with guidance context
4. Loop continues until time/iteration limits or `/ru:stop`

### Installing Hooks

```bash
# Check hook status
/ru:hooks status

# Install hooks
/ru:hooks install

# Restart Claude Code for hooks to take effect
```

## Troubleshooting

| Issue                      | Cause                           | Solution                                           |
| -------------------------- | ------------------------------- | -------------------------------------------------- |
| Loop not starting          | Hooks not installed             | Run `/ru:hooks install` and restart Claude Code    |
| Loop stops unexpectedly    | STOP_LOOP file created          | Remove `.claude/STOP_LOOP` to allow continuation   |
| Guidance not loading       | ru-config.json missing or empty | Run `/ru:wizard` to configure guidance             |
| State file corrupted       | Interrupted during write        | Delete `.claude/ru-state.json` and restart         |
| Hooks fire outside loop    | State check failing             | Verify `ru-state.json` has `"state": "running"`    |
| Wrong iteration count      | State not persisting            | Check `.claude/` directory permissions             |
| Loop ignores forbidden     | Guidance not loaded at start    | Use `/ru:start` without `--quick` to load guidance |
| Emergency stop not working | STOP_LOOP not in right location | Create file at `.claude/STOP_LOOP` (project root)  |

## Architecture (Developer Reference)

The Stop hook uses a multi-layer architecture for activation gating and template rendering:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Claude Code Stop Event                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  loop-until-done-wrapper.sh (Bash)                              │
│  ├── Activation gate: checks ru-state.json for "running"        │
│  ├── Fast exit if not active (< 1ms, no Python/Bun deps)        │
│  └── Finds Bun executable and invokes TypeScript                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  loop-until-done.ts (TypeScript/Bun)                            │
│  ├── State machine: RUNNING → DRAINING → STOPPED                │
│  ├── Kill switch detection (.claude/STOP_LOOP)                  │
│  ├── Runtime/iteration tracking                                 │
│  ├── Template rendering (LiquidJS)                              │
│  ├── Task completion detection                                  │
│  ├── File discovery                                             │
│  └── Pattern learning                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  templates/ralph-unified.md (LiquidJS)                          │
│  ├── Hardcoded: AUTONOMOUS MODE, TASK ORCHESTRATION,            │
│  │   COMMIT STRATEGY, ERROR RECOVERY, TESTING PHILOSOPHY,       │
│  │   CONSTRAINTS                                                │
│  └── User-customizable: forbidden[], encouraged[] from config   │
└─────────────────────────────────────────────────────────────────┘
```

### File Status

| File                         | Status | Purpose                              |
| ---------------------------- | ------ | ------------------------------------ |
| `loop-until-done-wrapper.sh` | Active | Bash activation gate                 |
| `loop-until-done.ts`         | Active | TypeScript entry point (Bun runtime) |
| `pretooluse-loop-guard.ts`   | Active | PreToolUse guard (Valibot schema)    |
| `core/config-schema.ts`      | Active | Configuration schema (Valibot)       |
| `templates/ralph-unified.md` | Active | LiquidJS template                    |

### Why This Architecture?

1. **Bash wrapper** - Activation check without Bun dependencies (fast exit for inactive projects)
2. **TypeScript entry** - Type safety, easier validation, modern tooling
3. **LiquidJS templates** - JavaScript-native templating (no Python required)
4. **Valibot schema** - 38x faster than Zod for create+parse-once pattern

## License

MIT
