---
name: cc-skills-minimax-aggregation
version: 1
iteration: 0
last_updated: 2026-04-29T10:38:43Z
exit_condition: "saturation OR user-stop OR max_iterations OR explicit DONE section"
max_iterations: 100
trigger: "/loop — reads this file verbatim each firing"
dispatch_policy:
  enabled: false # set true to allow Phase 2a multi-agent dispatch on opt-in items
  require_experimental_teams: false # set true only if using TeamCreate/SendMessage (needs CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)
---

# cc-skills MiniMax Knowledge Aggregation — Autonomous Migration Loop

**This file IS the /loop prompt.** It is versioned, self-updates each firing, and git history tells the evolution story.

## How to invoke this loop

Put this in `/loop` (or `ScheduleWakeup.prompt`):

```
/loop

Read and execute the latest autonomous work contract at:
  plugins/minimax/LOOP_CONTRACT.md

Follow its instructions verbatim. That file self-updates; this trigger stays fixed.
```

That's the entire `/loop` command going forward. The short trigger is stable; the contract below evolves.

---

## Core Directive (preserve verbatim across revisions)

Aggregate the 41-iteration MiniMax M2.7-highspeed exploration campaign (located at `~/own/amonic/minimax/` — 40 verified pattern docs, 1 quirks consolidation, 1 retrospective, 1 OPS tool with launchd plist, ~50 fixtures) into a self-contained reusable cc-skills plugin at `~/eon/cc-skills/plugins/minimax/` so future Claude Code sessions across all repos can discover and apply MiniMax production wiring patterns without needing access to the source amonic repo. Two hard constraints from the user: (1) **CREATE FIRST, DO NOT MIGRATE** — the source knowledge in `~/own/amonic/minimax/` must remain untouched throughout this campaign; the cc-skills plugin is BUILT IN PLACE at `~/eon/cc-skills/plugins/minimax/` from copies/aggregations/distillations of the source, and only after the campaign closes does the user decide whether to retire the amonic copy. (2) **ITERATIVELY AUDIT** — each iter, check the source-of-truth against what's been aggregated to detect gaps; the campaign cannot close until coverage is provably complete (every pattern doc accounted for, every critical finding surfaced, every operational fact documented). The aggregated plugin must be SKILL-discoverable: the SKILL.md frontmatter must have a precise enough description that future Claude sessions auto-trigger it when working with MiniMax / OpenAI-compatible Chinese LLM providers / quant-finance LLM applications. Why this matters: amonic is one user's machine; cc-skills is the user's marketplace shared with future projects, future agents, and (potentially) other developers. Knowledge worth 41 iterations of investigation must be reusable across repos, not trapped in one. Success criteria: (a) every pattern doc from `amonic/minimax/api-patterns/` has a corresponding skill or skill-reference in the plugin; (b) the canonical Tier F agentic stack and the 11 documented failure modes are captured as SKILL.md primary content (the highest-discoverability layer); (c) the OPS tool (model-upgrade detection) is plug-and-play in the new repo without amonic-specific path assumptions; (d) a final audit pass confirms zero gaps between source and aggregate.

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

**Runs only if** `dispatch_policy.enabled: true` in frontmatter AND the current queue item has a non-empty `perspectives` list. Otherwise skip to Phase 3.

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
4. **Cleanup is coordinator-only.** Never let a teammate call `TeamDelete` or `ExitWorktree`.
5. **No MCP in background agents.** `run_in_background: true` disables MCP tool access. If a perspective needs MCP, run it foreground.
6. **Prefer `Agent` over `TeamCreate`** for one-shot perspectives. Reserve `TeamCreate` + `SendMessage` for teams that must persist across firings.

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

#### Pre-decision gate (REQUIRED before any `ScheduleWakeup` call)

Before the tier table is even consulted, answer **all three** questions in writing in your firing summary. If any answer is missing or vague, the only legal options are **Tier 0 (chain in-turn)** or **option 5 (DONE / exit honestly)**.

1. **Is the Implementation Queue empty?** (yes/no — name the next ready item if no)
2. **What specific external thing am I waiting for?** (must name a concrete external signal: a build PID, a CI run URL, a rate-limit window with a known ETA, a file-watch path, a webhook. _Not_ a valid answer: "the next iteration", "let cache stay warm", "pacing", "cogitation", "I want to think more", "in-flight task I started" — the last is your own work, not external state.)
3. **Could this work continue right now in-turn?** (if yes → Tier 0. `ScheduleWakeup` is forbidden.)

> **Anti-pattern recognized in the wild (iter-N example, ~2026-04-27)**:
> Queue had 4 actionable items; model wrote "Next wake at 08:29:00Z (~247s,
> cache-warm)" — the _only_ justification offered was "cache-warm". That is
> pacing, not waiting. Dead-time ratio for the firing: ~0.5, double the 0.25
> smell-check threshold. The legal move was Tier 0: pick item 2.1 and start it.

If you find yourself reaching for "cache-warm" as a reason to schedule a wake, stop. Cache-warmth is a side-property of Tier 2, not its purpose. The purpose is _waiting for an external signal_. Tier 0 is also cache-warm and is strictly cheaper when you have ready work.

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

**Last completed iteration**: iteration 0 — BOOTSTRAP (this firing). Scaffolded LOOP_CONTRACT.md from autonomous-loop template at `~/eon/cc-skills/plugins/minimax/LOOP_CONTRACT.md`. Loop registered (loop_id `909c5fc62d60`), launchd plist loaded (`com.user.claude.loop.909c5fc62d60`), 60s polling cadence. Plugin directory created. Source-of-truth survey: `~/own/amonic/minimax/` contains 40 pattern docs in api-patterns/, 1 quirks consolidation, 1 RETROSPECTIVE.md (the canonical orient doc), ~50 fixtures, the `bin/minimax-check-upgrade` OPS tool + mise task + locked snapshot + launchd plist (at `~/own/amonic/config/plists/`). Per user directive: CREATE FIRST, DO NOT MIGRATE — source stays untouched; this campaign builds an aggregated reusable plugin in place.

**Full current apex**: 0 plugin files committed. 0 of 40 pattern docs aggregated. 0 of 11 failure modes captured in skill content. 0 of 4 OPS-tool artifacts ported. SKILL.md does not exist yet. plugin.json does not exist yet. 100% of the source-of-truth knowledge remains exclusively at `~/own/amonic/minimax/` and is therefore inaccessible to future Claude sessions in other repos. Campaign at the absolute beginning.

**Active monitors**: none

**Outstanding housekeeping**:

- [x] LOOP_CONTRACT.md scaffolded
- [x] Loop registered in machine registry
- [x] Launchd plist loaded
- [x] Plugin directory created at `~/eon/cc-skills/plugins/minimax/`
- [ ] Initial commit of LOOP_CONTRACT.md (this iter's git work)
- [ ] First Phase A item (plugin.json scaffold) — iter-1
- [ ] Audit checklist established with concrete coverage criteria — iter-2 or iter-3

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

**Source-of-truth inventory** (snapshot at iter-0; verify against `~/own/amonic/minimax/` each audit):

| Source artifact                                                      | Files | Aggregate destination (in this plugin)                      |
| -------------------------------------------------------------------- | ----- | ----------------------------------------------------------- |
| `~/own/amonic/minimax/CLAUDE.md`                                     | 1     | Distill into `SKILL.md` frontmatter description + intro     |
| `~/own/amonic/minimax/RETROSPECTIVE.md`                              | 1     | Primary source for `SKILL.md` body (top 10 rules + stack)   |
| `~/own/amonic/minimax/quirks/CLAUDE.md`                              | 1     | `references/quirks.md` (use-case-organized)                 |
| `~/own/amonic/minimax/api-patterns/CLAUDE.md`                        | 1     | `references/api-patterns/INDEX.md`                          |
| `~/own/amonic/minimax/api-patterns/*.md`                             | 40    | `references/api-patterns/<name>.md` (mirror)                |
| `~/own/amonic/minimax/api-patterns/fixtures/*.json`                  | ~50   | Selective subset → `references/fixtures/` (diagnostic only) |
| `~/own/amonic/bin/minimax-check-upgrade`                             | 1     | `scripts/minimax-check-upgrade` (path-portable)             |
| `~/own/amonic/.mise/tasks/minimax/check-upgrade`                     | 1     | Plugin-aware mise task or doc only                          |
| `~/own/amonic/config/plists/com.terryli.minimax-check-upgrade.plist` | 1     | `templates/launchd-check-upgrade.plist` (parameterized)     |
| `~/own/amonic/minimax/api-patterns/fixtures/models-list-locked.json` | 1     | `references/models-list-locked.json`                        |
| `~/own/amonic/minimax/LOOP_CONTRACT.md`                              | 1     | NOT migrated (campaign archaeology, source-only)            |

**Audit principle**: each iter that touches a destination file must ALSO update an audit-coverage matrix tracking which source files have been aggregated. The campaign cannot close until coverage = 100% and a final fresh-Claude simulation proves the SKILL.md auto-triggers correctly.

### Tier 1 — Phase A: Plugin scaffold (iters 1-4)

- [ ] iter-1 — Scaffold `plugin.json` (cc-skills marketplace metadata: name `minimax`, description, version 0.1.0, author, license). Reference: `~/eon/cc-skills/plugins/quant-research/.claude-plugin/plugin.json` for shape.
- [ ] iter-2 — Scaffold `skills/minimax/SKILL.md` with the canonical orient-first content. Frontmatter description must be discoverability-tuned (triggers: "MiniMax", "OpenAI-compatible Chinese LLM provider", "M-series reasoning model", "MiniMax-M2.7", quant LLM applications). Body: TL;DR + top 10 production rules drawn from `~/own/amonic/minimax/RETROSPECTIVE.md`.
- [ ] iter-3 — Create `references/` directory structure: `api-patterns/`, `fixtures/`, plus `INDEX.md` navigable TOC.
- [ ] iter-4 — Create `scripts/` directory + plugin `README.md` (high-level: what this plugin does, how to use, how to install OPS tooling).

### Tier 2 — Phase B: Reference content aggregation (iters 5-15)

- [ ] iter-5 — Aggregate `RETROSPECTIVE.md` → `references/RETROSPECTIVE.md` (mostly verbatim copy; adjust internal cross-refs to plugin-relative paths).
- [ ] iter-6 — Aggregate `quirks/CLAUDE.md` → `references/quirks.md`. Verify all 5 critical findings carry over.
- [ ] iter-7 — Aggregate `api-patterns/CLAUDE.md` index → `references/api-patterns/INDEX.md`. Verify table integrity (40 rows).
- [ ] iter-8 to iter-12 — Aggregate `api-patterns/*.md` (40 files). Batch ~8 per iter. Each file: copy verbatim, then translate cross-references from amonic-relative to plugin-relative.
- [ ] iter-13 — Aggregate selected fixtures (the diagnostic ones from key probes: cache-discovery, models-list-locked, errors catalogue). Skip bulky fixtures (long-context, code-generation runs).
- [ ] iter-14 — Aggregate `models-list-locked.json` (the OPS tool's data contract). Update path references.
- [ ] iter-15 — Cross-reference audit: every internal `[link](path)` resolves; every iter-N reference still points to a real iter doc.

### Tier 3 — Phase C: OPS tool migration (iters 16-18) + Phase D: Audit (iters 19-22)

- [ ] iter-16 — Port `bin/minimax-check-upgrade` to `scripts/minimax-check-upgrade`. Replace amonic-specific paths with portable defaults; document required env (`MINIMAX_LOCKED_SNAPSHOT`, `MINIMAX_API_KEY_OP_PATH`).
- [ ] iter-17 — Port the launchd plist to a parameterized template at `templates/launchd-check-upgrade.plist`. Document install in skill content.
- [ ] iter-18 — Document the mise-task pattern in skill content (don't ship a mise task — too repo-specific; instead show how to wire one in any consuming repo).
- [ ] iter-19 — Audit pass 1 (mechanical): for each row of source-of-truth inventory, check destination file exists + non-empty. Produce `AUDIT.md` with COVERED / PARTIAL / MISSING per row.
- [ ] iter-20 — Audit pass 2 (semantic): re-read RETROSPECTIVE.md's top 10 rules, verify each is surfaced in SKILL.md (not buried in references/). Critical rules belong in primary skill content.
- [ ] iter-21 — Audit pass 3 (failure modes): all 11 documented failure modes from the source must have a clear home — either in SKILL.md (the 6 hallucination + 4 saturation defenses) or in references/ (the 1 cross-language asymmetry).
- [ ] iter-22 — Audit pass 4 (cross-references): no broken links, no dangling iter-N citations, no amonic-only paths in final aggregate.

### Tier 4 — Phase E: Skill refinement + discoverability (iters 23-27) + Phase F: Close (iter ~28)

- [ ] iter-23 — Refine SKILL.md frontmatter description for max discoverability. Test by simulating: would a Claude session with the prompt "I need to wire MiniMax embeddings into Karakeep" auto-trigger this skill?
- [ ] iter-24 — Decide skill split: should this be ONE skill or MULTIPLE (e.g., `minimax-wiring`, `minimax-tier-f-quant`, `minimax-caching`)? If split, partition references/ and update plugin.json.
- [ ] iter-25 — Add reproducer / verification: the `mise run minimax:check-upgrade` pattern needs to be runnable from any consuming repo without modification.
- [ ] iter-26 — Add "discovery breadcrumbs": ensure cc-skills marketplace top-level CLAUDE.md lists this plugin, plugin's own CLAUDE.md exists with quick-start.
- [ ] iter-27 — Final fresh-Claude simulation: spawn an Explore agent in a fresh prompt context, ask "wire up MiniMax with caching", verify it lands on the new plugin's content.
- [ ] iter-28 — Write `RETROSPECTIVE.md` for THIS campaign. Append DONE section to LOOP_CONTRACT.md. Suggest user commit + run `mise run release:full` if cc-skills uses semantic-release.

---

## Non-Obvious Learnings (preserve across revisions)

- **Source-of-truth lives at `~/own/amonic/minimax/`; never modify it from this campaign.** **Why**: the user explicitly directed "Create first, do not migrate." Source must remain intact for safe rollback if the aggregation goes sideways. **How to apply**: read amonic; write cc-skills. Never the reverse. If any iter discovers an error in the source content, fix it in BOTH places (source via a separate amonic commit; aggregate via this campaign's commits). Don't cross the streams.
- **The aggregation TARGET is a discoverable cc-skills plugin, not a knowledge dump.** **Why**: the user's stated goal is "future Claude Code sessions can discover and apply MiniMax production wiring patterns." A skill is only valuable if its frontmatter description triggers it from natural-language prompts like "wire up MiniMax embeddings" or "MiniMax-M2.7 caching." A flat copy of the 40 source docs would not auto-trigger. **How to apply**: each iter that touches SKILL.md must consider: would a Claude session NOT working with MiniMax skip it? Would a session that NEEDS MiniMax knowledge be drawn to it? The frontmatter description carries that load.
- **Iter cadence: 60s snappy waker, but actual work cadence is dynamic per ScheduleWakeup.** **Why**: per the user's "snappy" cadence choice in bootstrap. The 60s launchd waker is a SAFETY NET (reclaim if session dies). Actual iter pacing is via ScheduleWakeup — short delays (60-270s) for quick work, longer (1200-1800s) for content-heavy iters that need cache misses to amortize. **How to apply**: each iter ends with ScheduleWakeup; pick delay based on what's NEXT, not a fixed cadence.
- **Iter-0 is bootstrap; iter-1 is the first real work iter.** **Why**: matches the precedent set by the amonic minimax-m27-explore campaign (iter-0 = scaffold + queue seed; iter-1 = first probe). Frontmatter `iteration: 0` after this firing means "0 work iters completed; bootstrap done." Future firings increment. **How to apply**: don't try to do Phase A iter-1 work in this same firing. Bootstrap is contained: scaffold, queue, commit, schedule iter-1, stop.
- **The audit-coverage matrix is the campaign's exit criterion, not iteration count.** **Why**: 28 iters is a working estimate; the campaign closes when the source-of-truth inventory shows 100% COVERED, not after iter-28 specifically. If aggregation is faster, close earlier. If audits reveal gaps, extend. **How to apply**: each iter that produces a destination file MUST update the inventory matrix in Current State. Each audit pass writes its findings to AUDIT.md. Tooling exists (campaign-closure-protocol from amonic iter-42 retrospective) to enforce this.

---

## Revision Log (append-only, one line per firing)

> **Time discipline (CRITICAL)**: every time you write or speak a timestamp
> related to this loop — `last_updated`, revision-log entries, "next firing
> scheduled at X", chat summaries, anywhere — use **UTC computed from
> `date -u`**. Never use bare `date` (local time) and label it UTC. The
> statusline shows UTC; the contract field name is `last_updated: 2026-04-29T10:38:43Z`;
> the registry's `started_at_us` / `last_wake_us` are UTC microseconds-since-epoch.
> A wake-up labeled "01:11 UTC" computed from local PDT 01:11 is actually
> 08:11 UTC and silently mismatches every other clock — including the
> heartbeat's freshness check. When the autonomous-loop sees a stale
> heartbeat from a wrong-clock entry, it can spuriously trigger reclaim.
>
> Quick reference:
>
> ```bash
> date -u +"%Y-%m-%dT%H:%M:%SZ"        # for last_updated frontmatter
> date -u +"%Y-%m-%d %H:%M UTC"        # for revision-log lines
> echo "next firing at $(date -u -v +273S +"%H:%M UTC") (~273s)"   # macOS
> echo "next firing at $(date -u -d '+273 seconds' +"%H:%M UTC") (~273s)"  # GNU
> ```

- 2026-04-29 10:40 UTC — iter-0 BOOTSTRAP. Scaffolded LOOP_CONTRACT.md from autonomous-loop template at `~/eon/cc-skills/plugins/minimax/LOOP_CONTRACT.md`. Loop registered in machine registry as `loop_id=909c5fc62d60`; launchd plist generated and loaded (`com.user.claude.loop.909c5fc62d60`, 60s polling); plugin directory created at `~/eon/cc-skills/plugins/minimax/`. Locked Core Directive (28-iter estimate to aggregate 41-iter MiniMax campaign from `~/own/amonic/minimax/` into a discoverable cc-skills plugin; user-directed "create first, do not migrate" + "iteratively audit"). Seeded Implementation Queue across 4 tiers: Tier 1 = Phase A plugin scaffold (iters 1-4: plugin.json, SKILL.md, references/, scripts/+README); Tier 2 = Phase B reference content aggregation (iters 5-15: RETROSPECTIVE, quirks, api-patterns INDEX, 40 pattern docs in batches, fixtures, models-list-locked, cross-ref audit); Tier 3 = Phase C OPS tool migration (iters 16-18: minimax-check-upgrade port, plist template, mise pattern docs) + Phase D audit (iters 19-22: mechanical / semantic / failure-modes / cross-references); Tier 4 = Phase E refinement (iters 23-27: frontmatter discoverability, skill-split decision, reproducer, breadcrumbs, fresh-Claude simulation) + Phase F close (iter ~28: retrospective + DONE marker). Source-of-truth inventory captured (10 row-types, ~95 files total). Seeded 5 Non-Obvious Learnings (source-untouched-rule, target-is-discoverable-skill-not-dump, dynamic-pacing-with-launchd-safety-net, iter-0-is-bootstrap-only, audit-coverage-matrix-is-exit-criterion). Next intent: iter-1 picks Phase A item 1 — scaffold `plugin.json` (cc-skills marketplace metadata). Reference: `~/eon/cc-skills/plugins/quant-research/.claude-plugin/plugin.json` for shape. Cumulative API budget: 0 calls (this campaign uses no MiniMax API; pure aggregation work).
