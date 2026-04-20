# autonomous-loop Plugin

> Self-revising LOOP_CONTRACT.md pattern for long-horizon autonomous work.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [ru CLAUDE.md](../ru/CLAUDE.md)

## Overview

Packages the _self-revising execution contract + dynamic pacing + Monitor fallback + saturation stop_ pattern into 3 skills. Designed to complement, not replace, Claude Code's built-in `/loop` and `/schedule`.

## When to prefer this over siblings

- **Native `/loop`** — use when you need pacing but no state persists between firings.
- **`ru` plugin** — use for Stop-hook-driven continuation within a single session.
- **Anthropic Routines** — use for cloud-scheduled unattended work.
- **autonomous-loop** — use when firings must READ past state + REVISE plans + PERSIST decisions across multi-day windows, ideally surviving auto-compact and session restarts.

## Skills

| Skill    | Purpose                                              |
| -------- | ---------------------------------------------------- |
| `start`  | Install `LOOP_CONTRACT.md` template + invoke `/loop` |
| `status` | Read contract frontmatter, report state concisely    |
| `stop`   | Mark contract completed, terminate loop, notify user |

## The contract file

`LOOP_CONTRACT.md` lives at the root of the target directory (or a sub-path the user chooses). Structure:

```yaml
---
name: <short-descriptive-name>
version: 1
iteration: 0
last_updated: <ISO 8601 UTC>
exit_condition: <human-readable termination rule>
max_iterations: 100
---
# Core Directive         # preserved verbatim
## Execution Contract    # Orient / Act / Revise / Persist
## Dynamic Wake-Up       # delay table
## Current State         # rewrite every firing
## Implementation Queue  # prioritized tasks
## Revision Log          # append-only ledger
## Non-Obvious Learnings # preserved across firings
```

## Dynamic wake-up policy table

| Situation                                        | Delay                                      | Why                                        |
| ------------------------------------------------ | ------------------------------------------ | ------------------------------------------ |
| Long-running task in flight (>10 min)            | 1200-1800s + Monitor                       | Event fires before heartbeat; cache saved  |
| Short task in flight (<5 min)                    | 60-300s + Monitor                          | Tight cap for fast turnaround              |
| Nothing in flight, self-directed work continues  | 60s (continue-now)                         | Don't idle; effectively the next iteration |
| Waiting on user decision                         | 3600s (max)                                | User will return; no wake-ups wasted       |
| Saturation detected (3 consecutive null rescues) | **omit ScheduleWakeup** + PushNotification | Honest stop, user notified                 |

Prompt cache TTL is 5 minutes. Delays ≤270s keep the cache warm; delays ≥300s pay one cache miss. The anti-pattern is picking 300s (cache miss without amortizing the wait).

## Monitor-primary + ScheduleWakeup-fallback

When an external event (build done, chain complete, log line matches) is the natural wake signal, arm a `Monitor` with `persistent: true`. Add a `ScheduleWakeup` as heartbeat safety net (1200-1800s) in case the Monitor filter misses.

## Saturation detection heuristic

Count consecutive firings where `CURRENT_STATE` reports a "null-rescue" outcome (no improvement, no new direction). At **3 in a row**, omit the next `ScheduleWakeup`, send a `PushNotification` summarizing the final state, and let the loop terminate naturally.

## Anti-patterns

- Never re-issue `/loop` with a new prompt each firing — use the short trigger pattern so the contract file is the SSoT.
- Never store state in memory (Claude's `auto memory`) — the contract file is the state. Memory is for cross-session preferences, not mid-loop state.
- Never rely on Opus 4.7 task budgets — [API-only](https://platform.claude.com/docs/en/build-with-claude/task-budgets), unavailable in Claude Code subscription.
- Never let the revision log grow unbounded — archive or summarize entries >100 in the template.

## Motivating real-world case study

See `docs/design/2026-04-20-autonomous-loop/spec.md` for a full walkthrough of a 37-iteration autonomous quant-research campaign that used a hand-authored version of this pattern.
