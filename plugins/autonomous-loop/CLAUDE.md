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

## Core design principle

**Every waker mechanism exists for one reason only: to make the main Claude Code session resume.** There is no other point. The loop never executes work outside Claude Code — only inside it. So picking a waker reduces to: what is the cheapest, most honest way to signal "work is ready"?

Ranked by cost (lowest → highest). Always pick the earliest tier that fits.

| Tier                                               | Mechanism                                                                                                                    | When to use                                                                                                | Cost                                             |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **0 — In-turn continuation (default)**             | No waker at all. Just start the next iteration in the same turn.                                                             | Implementation Queue has a ready item AND tokens remain. This is 90% of the case.                          | Zero — no cache miss, no real-time gap           |
| **1 — `Monitor`**                                  | Arm a `Monitor` on a background script's stdout so the turn wakes on each emitted line (build output, file-watch, log tail). | External event is the natural readiness signal AND we're still in the same session.                        | Near-zero; cache stays warm                      |
| **2 — `ScheduleWakeup` (≤270s)**                   | Timer fires within the 5-min prompt cache TTL.                                                                               | Genuinely timed external blocker: API rate limit window, deployment known-ETA, polled API with no webhook. | One cached turn of real-time wait; no cache miss |
| **3 — `ScheduleWakeup` (≥1200s)**                  | Long-sleep timer (20 min – 1 hr). Expect to pay one prompt-cache miss on resume.                                             | User will be away for a while; external event is unlikely to fire sooner.                                  | Cache miss + longer wall-clock wait              |
| **4 — External waker (watchexec / systemd.timer)** | Cross-_session_ waker. Something outside Claude Code launches a fresh `claude --continue`.                                   | Session has fully ended (user closed terminal, machine rebooted) and we need to resume automatically.      | Full cold start of a new session                 |

**Key rule:** Never pick `ScheduleWakeup(300s)` — it's the worst of both (cache miss without amortizing the wait). Stay ≤270s or jump to ≥1200s.

## The classical bug: using a waker as pacing

If iter-N completes and iter-N+1 is ready, **do not** call `ScheduleWakeup(60s)`. Do not call it at all. Chain in-turn instead. `ScheduleWakeup` is for **external blockers**, not for pacing your own work. A firing that produces "scheduled next wake-up, did nothing else" while the Implementation Queue has ready work is a regression — reviewers should flag it.

## Monitor as the preferred reactive waker

When an external event (build done, chain complete, log line matches) is the natural wake signal, arm a `Monitor` with `persistent: true`. A `ScheduleWakeup` heartbeat (1200-1800s) is optional _safety net only_ — it should be redundant in the happy path. If you find yourself relying on the heartbeat to advance iterations, the Monitor filter is wrong.

## Saturation detection heuristic

Count consecutive firings where `CURRENT_STATE` reports a "null-rescue" outcome (no improvement, no new direction). At **3 in a row**, omit the next `ScheduleWakeup`, send a `PushNotification` summarizing the final state, and let the loop terminate naturally.

## Anti-patterns

- **Never use `ScheduleWakeup` as pacing.** It is strictly for external blockers (timed webhook, rate-limit window, user-return wait). If the next iteration can fire immediately, fire it — do not schedule.
- **Never leave dead air between completed iterations.** If iter-N commits and iter-N+1 is queued, iter-N+1 runs in the same turn. No 60s nap. No "fallback heartbeat" when nothing is blocking.
- Never re-issue `/loop` with a new prompt each firing — use the short trigger pattern so the contract file is the SSoT.
- Never store state in memory (Claude's `auto memory`) — the contract file is the state. Memory is for cross-session preferences, not mid-loop state.
- Never rely on Opus 4.7 task budgets — [API-only](https://platform.claude.com/docs/en/build-with-claude/task-budgets), unavailable in Claude Code subscription.
- Never let the revision log grow unbounded — archive or summarize entries >100 in the template.

## Motivating real-world case study

See `docs/design/2026-04-20-autonomous-loop/spec.md` for a full walkthrough of a 37-iteration autonomous quant-research campaign that used a hand-authored version of this pattern.
