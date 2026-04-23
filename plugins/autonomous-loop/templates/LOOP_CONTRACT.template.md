---
name: <SHORT_DESCRIPTIVE_NAME>
version: 1
iteration: 0
last_updated: <ISO_8601_UTC>
exit_condition: "saturation OR user-stop OR max_iterations OR explicit DONE section"
max_iterations: 100
trigger: "/loop — reads this file verbatim each firing"
dispatch_policy:
  enabled: false              # set true to allow Phase 2a multi-agent dispatch on opt-in items
  budget_per_firing: 40000    # hard token ceiling per firing; stop dispatching when hit
  require_experimental_teams: false  # set true only if using TeamCreate/SendMessage (needs CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)
---

# <PROJECT OR CAMPAIGN TITLE>

**This file IS the /loop prompt.** It is versioned, self-updates each firing, and git history tells the evolution story.

## How to invoke this loop

Put this in `/loop` (or `ScheduleWakeup.prompt`):

```
/loop

Read and execute the latest autonomous work contract at:
  <RELATIVE_PATH_TO_LOOP_CONTRACT_MD>

Follow its instructions verbatim. That file self-updates; this trigger stays fixed.
```

That's the entire `/loop` command going forward. The short trigger is stable; the contract below evolves.

---

## Core Directive (preserve verbatim across revisions)

<ONE PARAGRAPH describing the long-horizon goal. This section is the campaign's north star and must NOT be rewritten each firing. It describes WHAT + WHY, not HOW. Examples: "Find OOD-robust positively-yielding OOS trading rules across 4 FX symbols" or "Maintain green CI on main branch by investigating flaky tests as they surface".>

---

## Execution Contract

Each firing must:

1. **Orient** — read this file's Current State, ledger, last action in flight.
2. **Act** — execute the single highest-value next step from the Implementation Queue.
3. **Revise** — rewrite Current State + append to Revision Log + update Queue.
4. **Persist** — atomic commit(s), then schedule next wake-up with dynamic pacing.

### Phase 1 — Orient (never blind-execute)

```bash
tail -10 <LEDGER_FILE>              # what's been done
<status command e.g. pueue status>  # what's running in flight
git status --short | head -20       # working tree cleanliness
git log --oneline -5                # recent commits
```

Form a one-sentence assessment: _"Last firing finished X with Y result; next logical step is Z from the queue."_

### Phase 2 — Act (fill available time, not just one step)

Priority order (stop at the first match that has actionable work; then
continue to rule 6 if time/tokens remain):

1. If a long-running task is **in flight**: verify `Monitor` is armed on its output stream so the turn reacts as events arrive. Only arm a `ScheduleWakeup(1200-1800s)` heartbeat as a _safety net_ (redundant in the happy path). If the queue has other non-conflicting items, keep working in the same turn — don't sleep.
2. If a Monitor event **just fired** (chain done): archive artifacts, write verdict, append ledger, commit atomically, pick next iteration.
3. If **uncommitted research artifacts** exist (git status dirty): commit as logical atomic group before starting new work.
4. If a **major milestone** just landed (cross-asset validation, composability proof, tier complete): consider `mise run release:full` per release rules.
5. If **nothing in flight + tree clean**: pick the next pending item from Implementation Queue; build, deploy, monitor.
6. **Continue filling available time** — after the primary step above, if a long-running task was merely launched (not blocked-waiting) and tokens remain, ALSO pop the next non-conflicting secondary queue item and make progress on it in the same firing. Idle waiting is the exception, not the norm. Suitable secondary items:
   - Documentation / CLAUDE.md updates triggered by the primary work
   - Refactors / lint fixes unrelated to the in-flight code path
   - Auditing commands (non-mutating) whose output informs the next primary step
   - Spawning independent `Agent` subtasks (in parallel) for research or validation that doesn't touch the mutating code path
7. If the **Implementation Queue is empty AND the only remaining work is an in-flight task you can't accelerate**: choose the cheapest waker tier that fits (see Phase 4 table). Prefer `Monitor` over `ScheduleWakeup`. If there is no in-flight task and the queue is empty, the loop's exit condition is met — do not schedule; stop honestly.

**Explicit rule — "continuation over idle":** a firing that produces
"scheduled next wake-up, did nothing else" is a regression whenever the
Implementation Queue has any non-blocked item. Reviewers should flag it.

### Phase 2a — Dispatch decision (opt-in multi-agent)

**Runs only if** `dispatch_policy.enabled: true` in frontmatter AND the current queue item has a non-empty `perspectives` list AND cumulative firing tokens < `dispatch_policy.budget_per_firing`. Otherwise skip to Phase 3.

**Default posture**: in-turn (Tier 0). Dispatch is the exception, not the norm. Shipyard's published warning stands: "multi-agent doesn't make sense for 95% of agent-assisted tasks."

**Dispatch procedure**:

1. For each perspective `p` in `queue_item.perspectives`, spawn one subagent:

   ```
   Agent(
     subagent_type: "general-purpose",        # or a custom name from .claude/agents/
     description: "<perspective> for <queue-item-id>",
     prompt: <spawn contract — see below>,
     isolation: "worktree",                    # only if this perspective writes code
     run_in_background: true                   # all perspectives in parallel
   )
   ```

2. **Spawn contract prompt** (use this shape verbatim — subagents don't see parent conversation):

   ```
   Read the autonomous work contract at <absolute path to LOOP_CONTRACT.md>.

   Role: <perspective name — implementer | critic | researcher | auditor | adversary>.
   Task: <queue item id + one-line objective>.
   Allowed write paths: <explicit list, empty = read-only>.
   Report format: <structured spec — e.g. "verdict: approve|flag|reject; rationale ≤ 200 words; risks as bulleted list">.

   Do not read this conversation. The contract is your only source of truth.
   Write your report to the `## Subagent Reports` section of the contract before returning.
   ```

3. **Await all responses** (`run_in_background` means they return as notifications).

4. **Aggregate**: read all reports from `## Subagent Reports`. Apply conflict resolution:
   - Weighted vote by domain fit (implementer 2× on feasibility, researcher 2× on tradeoffs, auditor 2× on risk, critic 1× with hard veto on correctness).
   - Auditor hard veto on `security_sensitive: true` items.
   - After 2 tiebreaker reboots → `PushNotification` + stop; never silently pick.

5. **Update queue item** with "approved by X, flagged by Y" annotations. Commit the contract revision (subagent reports included) as one atomic commit.

**Hard rules**:

1. **Never lead-implements.** If `perspectives` is non-empty, the main session aggregates reports only — it does NOT execute the task's write tool-calls. Delegate or skip. The most common multi-agent failure is a capable lead that writes files itself while teammates sit idle.
2. **Deterministic worktree names.** Use `<queue_item_id>-<perspective>` in the `Agent` invocation's worktree name. Collisions can delete the parent session's working directory.
3. **Explicit file ownership per perspective.** Declare allowed write paths in the spawn prompt. Overlapping paths across parallel perspectives in the same firing are forbidden — without this interface contract, MAST-Data showed 41-86.7% failure rates.
4. **Budget gate is a hard stop.** When `budget_per_firing` is reached, finish in-flight dispatch, then force Tier 0 for the rest of the firing. Do NOT continue dispatching, even for "just one more" item.
5. **Cleanup is coordinator-only.** Never let a teammate call `TeamDelete` or `ExitWorktree`.
6. **No MCP in background agents.** `run_in_background: true` disables MCP tool access. If a perspective needs MCP, run it foreground.
7. **Prefer `Agent` over `TeamCreate`** for one-shot perspectives. Reserve `TeamCreate` + `SendMessage` for teams that must persist across firings.

**When to add `## Subagent Reports` section** (inserted between `## Current State` and `## Implementation Queue` on first dispatch):

```markdown
## Subagent Reports (iter-<N>)

### <perspective> on <queue-item-id> — <ISO timestamp>

Verdict: approve | flag | reject
Rationale: <≤ 200 words>
Risks:
- <risk 1>
- <risk 2>
Allowed writes touched: <paths>
```

### Phase 3 — Revise (this file)

Rewrite the **Current State** section. Remove completed queue items. Promote next-tier items when current tier empties. Preserve the Core Directive and Non-Obvious Learnings verbatim.

### Phase 4 — Persist, then choose a waker (cheapest tier that fits)

**Core principle**: every waker exists solely to make the main session resume. If the next iteration is ready right now, do not call a waker at all — chain in-turn.

**Mandatory end-of-firing decision**: every firing MUST end with exactly one of these as its **literal final tool call** (not a text summary):

1. **Chain in-turn** — the next queue item's first tool call fires in the same turn.
2. **`Monitor(...)`** — reactive waker armed on a background stream.
3. **`ScheduleWakeup(...)`** — fresh wake. This supersedes any pending wake from a prior firing.
4. **Flip `status: SATURATED`** (in frontmatter) + `PushNotification(...)` — 3 consecutive null-rescues detected.
5. **Flip `status: DONE`** (in frontmatter) + no waker — exit condition met, loop terminates honestly.

A firing that ends with a text-only summary, no final tool call, and a pending ScheduleWakeup from a prior firing is a bug — the pending wake's context is frozen at pre-interrupt state and will fire on a stale contract. Never rely on "already queued" — call a fresh waker or chain in-turn.

**Handling manual interrupts inside an active wake window**: when `/loop`, `/autonomous-loop:start`, or a user prompt triggers this firing while a prior `ScheduleWakeup` is still pending, treat the fresh firing as authoritative and supersede the pending wake with option 1, 2, 3, 4, or 5 above. Phase 3 Revise is mandatory even on interrupt firings — update the contract so the (now-stale) pending wake, if it still fires, reads accurate state.

| Tier                                                 | Mechanism                                                                                                         | When to use                                                                                          | Cost                              |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------- |
| **0 — In-turn continuation (default)**               | No waker. Just start the next iteration in the same turn.                                                         | Implementation Queue has a ready item AND tokens remain.                                             | Zero                              |
| **1 — `Monitor`**                                    | Arm a `Monitor` on a background stream (build output, file-watch, log tail). The turn wakes on each emitted line. | An external event is the natural readiness signal, and you're still in-session.                      | Near-zero; cache warm             |
| **2 — `ScheduleWakeup` (≤270s)**                     | Timer fires within the 5-min prompt-cache TTL.                                                                    | Genuinely timed external blocker: API rate-limit window, deployment ETA, polled API with no webhook. | One warm turn of real-time wait   |
| **3 — `ScheduleWakeup` (≥1200s)**                    | Long-sleep timer. Pay one prompt-cache miss on resume.                                                            | User away for a while; no sooner signal expected.                                                    | Cache miss + long wall-clock wait |
| **4 — External waker** (watchexec / systemd.timer)   | Something outside Claude Code launches a fresh `claude --continue`.                                               | Session has fully ended and we need to resume automatically across restarts.                         | Full cold-start of a new session  |
| **Saturation detected (3 consecutive null rescues)** | **Omit the waker entirely** + `PushNotification`.                                                                 | Loop has stalled. Stop honestly; user resumes manually.                                              | —                                 |

**Hard rules**:

1. **Never use `ScheduleWakeup` as pacing.** If the next iteration is queued and non-blocked, fire it in the same turn. `ScheduleWakeup` is strictly for _external_ blockers.
2. **CI / semantic-release after push is NOT a Tier-2 blocker** by default. `git push` returns immediately; the release workflow runs asynchronously. Iter-N+1 can start as soon as iter-N commits — only wait if iter-N+1 literally reads the release tag or built artifact. Even then: `Monitor` on `gh run watch` (Tier 1), not a blind 270s timer.
3. **Never pick `ScheduleWakeup(300s)`** — worst of both (cache miss without amortizing). Stay ≤270s or jump ≥1200s.
4. **Heartbeats are safety nets, not triggers.** If `Monitor` is doing its job, the heartbeat fires as a no-op. If you rely on the heartbeat to advance, the `Monitor` filter is wrong.
5. **Smell-check**: if the last 3 firings show `wait_seconds / total_cycle_seconds > 0.25`, you are using the waker as pacing. Drop to Tier 0 or Tier 1 on the next firing and verify the ratio falls.

A firing that produces "scheduled next wake-up, did nothing else" while the Implementation Queue has ready work is a regression. Reviewers should flag it.

```bash
git add <LOOP_CONTRACT_PATH> <artifacts>
git commit -m "$(cat <<'EOF'
loop(iter-<N>): <one-line what this firing did>

<2-4 lines on decision + outcome + what next firing will do>
EOF
)"
```

Then schedule next firing with the pointer-trigger prompt above.

---

## Commit Conventions

Scope-tag first; body explains WHY.

| Scope               | Use for                                                    |
| ------------------- | ---------------------------------------------------------- |
| `loop(iter-<N>)`    | Autonomous firing output — per-iteration meta commit       |
| `audit(<area>)`     | Verdict + artifact commits                                 |
| `research(<topic>)` | External-source research corpus                            |
| `ledger`            | Append-only `evolution.jsonl` (or your equivalent) entries |
| `docs(<area>)`      | CLAUDE.md / README / summary updates                       |
| `chore(release)`    | Auto-generated by semantic-release — do not hand-write     |

Commit template:

```
<scope>: <one-line summary>

Why: <motivation or signal that triggered this work>
What: <concrete changes>
Next: <what the next firing should pick up>
```

A reviewer reading `git log --oneline` should reconstruct the campaign from commit messages alone.

---

## Release Decision Rule

Trigger a release after ANY of:

1. **Tier completion** — all T1 items complete
2. **Cross-asset / cross-domain validation** — result reproduces across targets
3. **Composability proof** — a new layer compounds with existing layers
4. **Architectural pivot** — fundamental methodology change
5. **Research digest integrated** — external research landed into an implementation
6. **Explicit user ask** — "release" / "/mise:run-full-release"

If none apply, stay on the same version and keep committing atomic artifacts.

---

## Current State (auto-maintained — rewrite each firing)

**Last completed iteration**: <brief description of what just landed>

**Full current apex**: <the current best / summary of what's validated>

**Active monitors**: <none | monitor-id + description>

**Outstanding housekeeping**:

- [ ] <item 1>
- [x] <completed item>

---

## Implementation Queue

Queue items support optional fields that gate Phase 2a multi-agent dispatch. When `dispatch_policy.enabled: false` in frontmatter, these fields are ignored and all items run in-turn (Tier 0).

Per-item schema (all optional except the checkbox line):

```markdown
- [ ] <action>
      id: <stable-identifier-for-worktree-naming>    # required if perspectives set
      cost_estimate: low | medium | high             # low = skip dispatch regardless of perspectives
      perspectives: [implementer, critic]            # empty/absent = in-turn (Tier 0)
      security_sensitive: true                       # triggers auditor hard veto
      allowed_writes:                                # per-perspective file-ownership (anti-collision)
        implementer: [path/to/dir/, another/file.py]
        critic: []                                   # read-only
```

### Tier 1 (start here — ready-to-build, 1-3 days each)

- [ ] <simple action — in-turn, no dispatch>
- [ ] <complex action>
      id: <slug>
      cost_estimate: high
      perspectives: [implementer, critic]
      allowed_writes:
        implementer: [<paths>]
        critic: []

### Tier 2 (1-2 weeks, production libraries available)

- [ ] <action>

### Tier 3 (2-4 weeks, academic prototypes)

- [ ] <action>

### Tier 4 (theoretical — defer to post-MVP)

- [ ] <action>

---

## Non-Obvious Learnings (preserve across revisions)

<Bulleted list of observations that would not be obvious to a fresh reader. Each entry includes the _why_ (the reason, often a past incident or strong preference) and the _how to apply_ (when/where this kicks in). Knowing _why_ lets you judge edge cases instead of blindly following the rule.>

- <learning 1>
- <learning 2>

---

## Revision Log (append-only, one line per firing)

- <YYYY-MM-DD HH:MM UTC> — <one-line summary of the firing, what it decided, next intent>
