# autonomous-loop

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../../LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

**Self-revising execution contract for long-horizon autonomous work.** Packages the _LOOP_CONTRACT.md + dynamic pacing + Monitor fallback + saturation stop_ pattern as a reusable skill suite.

## When to use this plugin vs alternatives

| Tool                | Scope                                                         | Pick it when                                                              |
| ------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Native `/loop`      | Built-in pacing; no contract file                             | Ad-hoc "keep checking this every X" without state continuity              |
| `ru` plugin         | Ralph Wiggum + Stop-hook continuation                         | Short autonomous bursts (<9 hours) on a single machine                    |
| Anthropic Routines  | Cloud-scheduled fire-and-forget                               | Unattended overnight work, machine can be off                             |
| **autonomous-loop** | Self-revising contract + dynamic wake + multi-session handoff | Multi-day research/ops where each firing must revise plans based on state |

## Installation

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install autonomous-loop@cc-skills
```

## Quick start

```bash
# Initialize a contract in the current project
/autonomous-loop:start

# Check progress after restart / compaction
/autonomous-loop:status

# Clean terminate (writes completion promise, sends PushNotification)
/autonomous-loop:stop
```

## What it installs

A single file in your project — `LOOP_CONTRACT.md` — with YAML frontmatter + canonical sections (STATUS, CURRENT_STATE, NEXT_ACTIONS, REVISION_LOG, NON_OBVIOUS_LEARNINGS). Each `/loop` firing reads the file, acts, rewrites it, then schedules the next wake-up with a cache-aware delay.

## The core pattern

```
/loop  →  read LOOP_CONTRACT.md  →  execute one iteration  →  rewrite contract
                ↑                                                      ↓
                └─ ScheduleWakeup(delay) OR Monitor(event) ────────────┘
```

Three features distinguish this pattern from a plain `/loop`:

1. **Pointer trigger** — short stable `/loop` invocation re-reads the evolving contract each firing (Cursor/Aider idiom).
2. **Dynamic wake-up policy table** — picks 60s / 270s / 1200s / 1800s / 3600s based on whether work is in flight, cache state, and saturation detection.
3. **Saturation stop** — three consecutive null-rescue iterations → omit `ScheduleWakeup`, send `PushNotification`, loop terminates cleanly.

## Motivating example

This plugin was extracted from a 37-iteration autonomous quant-research campaign on Open Deviation Bars (ODB). See [docs/design/2026-04-20-autonomous-loop/spec.md](../../docs/design/2026-04-20-autonomous-loop/spec.md) for the full case study with verbatim contract snapshots.

## Skills

| Skill                    | Invocation                | Purpose                                                |
| ------------------------ | ------------------------- | ------------------------------------------------------ |
| `autonomous-loop:start`  | `/autonomous-loop:start`  | Install `LOOP_CONTRACT.md` template + kick off `/loop` |
| `autonomous-loop:status` | `/autonomous-loop:status` | Report current iteration, last update, next wake ETA   |
| `autonomous-loop:stop`   | `/autonomous-loop:stop`   | Mark contract completed, send `PushNotification`, stop |

## Subscription-safe

This plugin deliberately avoids the Opus 4.7 **task budget** feature because [that's API-only](https://platform.claude.com/docs/en/build-with-claude/task-budgets) and unavailable in Claude Code subscription sessions. All pacing decisions use subscription-available primitives: `ScheduleWakeup`, `Monitor`, `CronCreate`, `PushNotification`, `AskUserQuestion`.

## Credits / prior art

The pattern synthesizes several FOSS conventions:

- **Ralph Wiggum** loop + completion-promise ([anthropics/claude-code](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md))
- **Living Documentation** revision logs
- **LangGraph checkpoint** state serialization vocabulary
- **Voyager skill library** pattern for iteration ledgers
- **Cursor/Aider pointer trigger** (short trigger + long contract)
