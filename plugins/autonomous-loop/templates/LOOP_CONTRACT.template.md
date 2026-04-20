---
name: <SHORT_DESCRIPTIVE_NAME>
version: 1
iteration: 0
last_updated: <ISO_8601_UTC>
exit_condition: "saturation OR user-stop OR max_iterations OR explicit DONE section"
max_iterations: 100
trigger: "/loop — reads this file verbatim each firing"
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

### Phase 2 — Act (single highest-value step)

Priority order:

1. If a long-running task is **in flight**: verify Monitor armed, check progress, schedule fallback (1200-1800s).
2. If a Monitor event **just fired** (chain done): archive artifacts, write verdict, append ledger, commit atomically, pick next iteration.
3. If **uncommitted research artifacts** exist (git status dirty): commit as logical atomic group before starting new work.
4. If a **major milestone** just landed (cross-asset validation, composability proof, tier complete): consider `mise run release:full` per release rules.
5. If **nothing in flight + tree clean**: pick the next pending item from Implementation Queue; build, deploy, monitor.

### Phase 3 — Revise (this file)

Rewrite the **Current State** section. Remove completed queue items. Promote next-tier items when current tier empties. Preserve the Core Directive and Non-Obvious Learnings verbatim.

### Phase 4 — Persist with dynamic pacing

**Dynamic Wake-Up Delay Policy** (no magic numbers):

| Situation                                           | Delay                                    | Rationale                                     |
| --------------------------------------------------- | ---------------------------------------- | --------------------------------------------- |
| Long task in flight (>10 min)                       | 1200-1800s with Monitor armed            | Event fires before deadline; cache not wasted |
| Short task in flight (<5 min)                       | 60-300s with Monitor armed               | Tight cap for fast turnaround                 |
| **Nothing in flight, self-directed work continues** | **60s (minimum, continue-now)**          | **Effectively "continue now"; don't idle**    |
| Blocked on user input / decision                    | 3600s (max)                              | User will return; hold efficiently            |
| Release milestone just shipped                      | 60s                                      | Continue immediately to next build            |
| Saturation detected (3 consecutive null rescues)    | **omit ScheduleWakeup** + PushNotification | Loop terminates; user notified              |

**Key rule**: never `ScheduleWakeup(300s)`. 300s is the worst-of-both — pays a cache miss without amortizing it. Pick ≤270s (cache warm) or ≥1200s (cache miss + long wait).

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

| Scope                    | Use for                                                                                 |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `loop(iter-<N>)`         | Autonomous firing output — per-iteration meta commit                                    |
| `audit(<area>)`          | Verdict + artifact commits                                                              |
| `research(<topic>)`      | External-source research corpus                                                         |
| `ledger`                 | Append-only `evolution.jsonl` (or your equivalent) entries                              |
| `docs(<area>)`           | CLAUDE.md / README / summary updates                                                    |
| `chore(release)`         | Auto-generated by semantic-release — do not hand-write                                  |

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

### Tier 1 (start here — ready-to-build, 1-3 days each)

- [ ] <action 1>
- [ ] <action 2>

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
