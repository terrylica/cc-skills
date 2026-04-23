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

### Common rationalizations that disguise the bug

Agents discover creative reasons to keep picking Tier 2. Flag these:

- **"Let CI / semantic-release finalize before next push."** `git push` returns immediately; the release workflow runs asynchronously on the server. Iter-N+1 can start as soon as iter-N commits — only wait if iter-N+1 literally reads the release tag or built artifact. Even then: `Monitor` on `gh run watch` (Tier 1), not a blind timer.
- **"Stays in cache (≤270s) for efficiency."** Cache efficiency is a tie-breaker between Tiers 2 and 3, not a reason to prefer Tier 2 over Tier 0. Tier 0 has zero cost on every dimension — cache, real-time, tokens.
- **"Fresh context will produce better work."** The cache TTL is 5 minutes; a 270s wait does not give you a "fresh context" — it gives you the same context on a slightly warmer cache. Only a full prompt-cache miss (≥1200s + compaction) produces different reasoning, and that's a cost, not a feature.
- **"Heartbeat in case the Monitor misses an event."** If you're relying on the heartbeat, your `Monitor` filter is wrong — fix the filter. Heartbeats should fire as no-ops in the happy path.
- **"A prior ScheduleWakeup is already queued — it'll handle the next iteration."** A stale wake re-reads the contract **at its own firing time**, but its context is frozen at the pre-interrupt state. If THIS firing did new work without updating the contract, the stale wake runs on stale state — iteration numbers desync, Current State lies, Revision Log has gaps. Always call a fresh `ScheduleWakeup` (or chain in-turn) after doing work, regardless of pending wakes. Real incident: `mql5/news-events-ingest` firing on 2026-04-23 at 19:25 UTC closed 2 GitHub issues + committed atomically, then ended with "iter-22 already queued" and skipped Phase 3 Revise. The 19:36 wake fired on a contract that still said "iter-21 monitoring" — a 6+ minute idle gap plus desynchronized state.

### Mandatory end-of-firing decision

Every firing MUST end with exactly one of these as its **literal final tool call** (not a text summary):

1. **Chain in-turn** — the next queue item's first tool call fires in the same turn.
2. **`Monitor(...)`** — reactive waker armed on a background stream.
3. **`ScheduleWakeup(...)`** — fresh wake. This supersedes any pending wake from a prior firing.
4. **Flip `status: SATURATED`** + `PushNotification(...)` — 3 consecutive null-rescues detected.
5. **Flip `status: DONE`** + no waker — exit condition met, loop terminates honestly.

A firing that ends with a text-only summary (no final tool call) and trusts a pending ScheduleWakeup from a prior firing is a bug. Reviewers: grep the transcript for the final `tool_use` event and verify one of 1-5 fired. Pattern to catch: final assistant turn is `type: "text"` with rationalization "already queued" or "will pick up automatically."

### Handling manual interrupts inside a pending wake window

When `/loop`, `/autonomous-loop:start`, or a user prompt triggers a firing while a prior `ScheduleWakeup` is still pending (the pending wake hasn't fired yet):

1. **Treat the fresh firing as authoritative.** The pending wake is now stale — its `prompt` will re-read `LOOP_CONTRACT.md` at its firing time, but if THIS firing doesn't update the contract, the stale wake runs on pre-interrupt state.
2. **Supersede the pending wake at end-of-firing.** Either chain in-turn (best if the queue has ready work) OR call a fresh `ScheduleWakeup` that reflects the new state. Do not rely on the pending wake.
3. **Phase 3 Revise is mandatory.** Update iteration number, Current State, and Revision Log so any waker — fresh or stale — that fires next reads accurate state. A firing that committed new work but did not touch `LOOP_CONTRACT.md` has violated Phase 3, and Phase 4's waker decision runs on a lie.
4. **Never end with "the prior wake will handle it."** The prior wake's context is stale; the user's interrupt asked for work THIS firing addressed, not one scheduled minutes earlier.

### Empirical smell-check

Compute `dead_time = wait_seconds / total_cycle_seconds` across the last 3 firings (`wait_seconds` = `ScheduleWakeup.delaySeconds` from the prior firing; `total_cycle_seconds` = wall-clock gap between prior and current ScheduleWakeup timestamps). If `dead_time > 0.25` across 3+ consecutive firings, you are using the waker as pacing. **Action**: drop to Tier 0 or Tier 1 on the next firing and verify the dead-time ratio falls.

Real-world reference: the `mql5/session-calendar-v2` Campaign 3 loop hit `dead_time` of 55-69% for 5 straight firings with the rationalization "270s stays in cache and lets semantic-release finalize" — a textbook instance of this bug. The fix was to port the Phase 4 tier table into the contract.

## Monitor as the preferred reactive waker

When an external event (build done, chain complete, log line matches) is the natural wake signal, arm a `Monitor` with `persistent: true`. A `ScheduleWakeup` heartbeat (1200-1800s) is optional _safety net only_ — it should be redundant in the happy path. If you find yourself relying on the heartbeat to advance iterations, the Monitor filter is wrong.

## Multi-agent dispatch (Phase 2a, opt-in)

Long-horizon loops benefit from parallel multi-perspective review on _hard_ queue items — but only when gated. Published multi-agent post-mortems consistently fail on **over-orchestration** (spawning teams for tasks that don't decompose), not on under-use. The academic MAST-Data study (arxiv:2503.13657) shows 41-86.7% system failure when interface contracts between agents are unstructured; documented runaway cases burned $8K-$47K on 23-49 agent swarms. The rule: dispatch exactly when work decomposes, not by default.

### Core principle

`LOOP_CONTRACT.md` stays the SSoT. Dispatched subagents read the contract directly — the coordinator does **not** re-serialize state. Dispatch is declarative per queue item via an optional `perspectives` list. Empty/absent = in-turn (Tier 0). Non-empty = parallel dispatch.

### Native primitives to use

| Primitive                                   | Use for                                                                                     | Invocation                                                                                        |
| ------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Agent` tool with `run_in_background: true` | One-shot parallel perspective (default choice)                                              | `subagent_type: "general-purpose" \| "Explore" \| "Plan"` or a custom name from `.claude/agents/` |
| `TeamCreate` + `SendMessage`                | Persistent cross-firing team (experimental; needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | Only when perspectives must survive across multiple firings                                       |
| `EnterWorktree` / `ExitWorktree`            | Explicit worktree lifecycle when `isolation: "worktree"` isn't enough                       | v2.1.72+                                                                                          |
| `.claude/agents/*.md`                       | Persistent agent manifests with tool allowlists, model, memory                              | One per canonical perspective, scoped per-project                                                 |
| `teammateMode: "tmux"` in `~/.claude.json`  | Visualize teammates in iTerm2 native panes                                                  | Display layer only — does not change orchestration                                                |

Prefer `Agent(run_in_background: true)` over `TeamCreate` for one-shot perspectives. `TeamCreate` is worth the ceremony only when a perspective must persist across firings.

### Canonical perspectives

| Role           | Purpose                                          | Gate                                                 |
| -------------- | ------------------------------------------------ | ---------------------------------------------------- |
| `implementer`  | Executes the work                                | Required when any perspective listed                 |
| `critic`       | Veto on output quality / correctness             | Default pair with `implementer`                      |
| `researcher`   | Surface tradeoffs, prior art, hidden assumptions | Queue item has >2 plausible paths                    |
| `auditor`      | Threat model / security review                   | `security_sensitive: true` on item                   |
| `adversary`    | Red-team the plan; devil's-advocate stress test  | Releases, architectural pivots, irreversible changes |
| `budget-guard` | Tracks cumulative tokens, halts runaway          | Runs as a hook, not a perspective                    |

Minimum useful set: `[implementer, critic]`. Add others only when the gate condition fires. `researcher` is NOT a free add — it doubles token spend per item.

### State handoff (the spawn contract)

Every dispatched perspective gets this exact prompt shape:

```
Read the autonomous work contract at <absolute path to LOOP_CONTRACT.md>.

Role: <perspective>.
Task: <queue item identifier + one-line objective>.
Allowed write paths: <explicit list; empty means read-only>.
Report format: <structured output spec — e.g. "verdict: approve|flag|reject; rationale ≤ 200 words; risks as bulleted list">.

Do not read this conversation. The contract is your only source of truth.
```

Subagents never see the parent conversation. The contract file is the interface contract (the absence of one is what drives the 41-86.7% failure rate in MAST-Data). Each perspective writes its report to a `## Subagent Reports` subsection before returning.

### Conflict resolution

When perspectives disagree:

1. **Weighted vote by domain fit**: implementer 2× on feasibility, researcher 2× on tradeoffs, auditor 2× on risk. Critic is always 1× but carries a hard veto on correctness failures.
2. **Auditor hard veto** on `security_sensitive: true` items — flagged items revert to researcher's next-ranked option and re-run audit.
3. **User escalation**: after 2 tiebreaker reboots, emit `PushNotification` with all verdicts and stop. Never silently pick.

### Hard rules (inherited from failure-mode research)

1. **Never lead-implements.** If `perspectives` is non-empty, the main session aggregates reports only — it does not execute the task's write tool-calls. The most common multi-agent anti-pattern ("claudefa.st/blog/guide/agents/agent-teams-best-practices") is a capable lead that ignores delegate mode and writes files itself, leaving teammates idle.
2. **Deterministic worktree names.** Use `<queue_item_id>-<perspective>`. Collisions can delete parent session working directory (real bug: anthropics/claude-code issue #41010).
3. **Explicit file ownership per perspective.** Declare allowed write paths in the spawn prompt. Overlapping paths across parallel perspectives in the same firing are forbidden — this is the interface contract.
4. **Budget gate is a hard stop, not advisory.** When `dispatch_policy.budget_per_firing` is reached mid-firing, finish in-flight dispatch, then force Tier-0 for the rest of the firing. Do NOT continue dispatching.
5. **Cleanup is coordinator-only.** Teammates never call `TeamDelete` or `ExitWorktree` — context may not resolve correctly from inside a teammate.
6. **MCP tools unavailable in background agents.** `run_in_background: true` disables MCP access. If a perspective needs MCP, run it foreground.
7. **Don't replicate CLAUDE.md across N agents.** The contract has what they need — subagents read it on demand. A bloated CLAUDE.md injected per-agent is 7× setup cost before any work starts.

### Universality tradeoff (explicit)

- **Upside**: multi-perspective catches blind spots; parallel execution hides latency; git history captures reasoning from all perspectives.
- **Downside**: trivial tasks now cost 3+ invocations; budget balloons without strict gating; new failure modes (timeouts, orphans, worktree collisions).

**Mitigation stack** (all three, composable):

- **Structural**: `perspectives` field is empty by default (opt-in per item).
- **Economic**: `budget_per_firing` hard ceiling.
- **Semantic**: `cost_estimate: low` items skip dispatch regardless of perspectives.

If dispatch-rate metrics later show under-dispatch (perspectives catching things the coordinator missed), add an LLM classifier on queue items — but not before metrics show signal.

### Shipyard's warning (internalize it)

> "Multi-agent doesn't make sense for 95% of agent-assisted tasks."

Frame dispatch as **exceptional**, not routine. If a firing dispatches for every queue item, the dispatch decision rule is wrong.

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
