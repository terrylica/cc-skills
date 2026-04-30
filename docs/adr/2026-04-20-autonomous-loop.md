# ADR: autonomous-loop plugin — self-revising execution contract for long-horizon autonomous work

**Status**: Proposed
**Date**: 2026-04-20
**Author**: Terry Li
**Context ID**: autonomous-loop

## Context

Claude Code already ships several mechanisms for recurring or autonomous execution:

- `/loop` (native) — dynamic or fixed pacing via `ScheduleWakeup` (2.1.101+)
- `/schedule` / Anthropic Routines — cloud-scheduled cron agents
- `ru` plugin (cc-skills) — Ralph-Wiggum Stop-hook continuation, activation-gated
- `pueue-job-orchestration` (cc-skills devops-tools) — disk-backed batch queue

None of these centralize the **self-revising execution contract** pattern where a single markdown file is both the plan AND the ledger AND the trigger, rewritten each firing and survived across auto-compact / session restart.

A 37-iteration autonomous quant-research campaign (`opendeviationbar-patterns`, April 2026) hand-authored this pattern and demonstrated its value:

- Contract file `LOOP_PROMPT.md` with YAML frontmatter + canonical sections
- Short `/loop` pointer trigger + long evolving contract (Cursor/Aider idiom)
- Dynamic wake-up table keyed on cache-TTL + work-in-flight state
- Monitor-primary + ScheduleWakeup-fallback wake signaling
- Saturation-stop heuristic (3 consecutive null-rescues → clean terminate)
- Atomic scope-tagged commits so `git log --oneline` reconstructs the campaign

## Decision

Package the pattern as a cc-skills plugin (`plugins/autoloop/`) with three skills:

| Skill    | Role                                                         |
| -------- | ------------------------------------------------------------ |
| `start`  | Scaffold `LOOP_CONTRACT.md` in target dir + kick off `/loop` |
| `status` | Parse contract frontmatter + report concise state            |
| `stop`   | Mark contract `DONE`, send `PushNotification`, let loop exit |

Plus a template `LOOP_CONTRACT.template.md` with idiomatic structure (YAML frontmatter + sections in canonical order).

## Before / After

```
Before: /loop <my-prompt>               # paste full prompt each invocation
                      ↓
                  Claude does one iteration
                      ↓
                  Schedule wake with new prompt?
                  (same-prompt replay, or craft new each time)

After:  /loop "read LOOP_CONTRACT.md"   # short stable trigger
                      ↓
                  Read evolving contract
                      ↓
                  Execute + revise contract + commit
                      ↓
                  ScheduleWakeup(dynamic delay) / Monitor
                      ↓
                  (next firing reads the revised contract)
```

```
autonomous-loop architecture

┌─────────────────────────────────────────────────────────────────┐
│ Target project                                                  │
│                                                                 │
│  LOOP_CONTRACT.md  ◀──── /autoloop:start scaffolds       │
│    │                                                            │
│    │ read each firing                                           │
│    ▼                                                            │
│  Claude Code session ────▶ acts on Implementation Queue         │
│    │                       writes verdict + ledger              │
│    │                       atomic commit                        │
│    ▼                                                            │
│  rewrite LOOP_CONTRACT.md (Current State + Queue + Revision Log)│
│    │                                                            │
│    ├──▶ ScheduleWakeup(60s / 270s / 1200s / 1800s / 3600s)     │
│    └──▶ Monitor(event) ← primary wake signal when applicable   │
│                                                                 │
│  /autoloop:status  ◀──── anytime: read frontmatter      │
│  /autoloop:stop    ◀──── mark DONE, send PushNotification│
└─────────────────────────────────────────────────────────────────┘
```

## Consequences

### Positive

- Single skill packages a proven pattern → new users get the full playbook (dynamic pacing, saturation detection, Monitor-fallback) without rediscovering it
- Pointer-trigger architecture means `/loop` inputs stay stable while logic evolves — no more stale prompts on manual `/loop` re-issue
- Contract file is a first-class git artifact — `git log LOOP_CONTRACT.md` shows the campaign story
- Subscription-safe — no dependency on the API-only Opus 4.7 task-budget feature
- Idiomatic to the FOSS ecosystem — borrows vocabulary from Ralph Wiggum (completion promise), LangGraph (checkpoint), Voyager (skill library), Cursor/Aider (pointer trigger), Living Documentation (revision log)

### Negative

- Adds one more autonomous-execution option to the ecosystem; users must choose between `/loop`, `ru`, Routines, autonomous-loop
- Contract file grows with iterations — requires the revision-log archiving discipline documented in CLAUDE.md
- Depends on user discipline to follow the 4-phase contract (Orient / Act / Revise / Persist) — skill can't fully enforce

### Neutral

- No new tools added to the Claude Code surface; plugin is pure-skill (no hooks, no MCP servers, no binaries)

## Alternatives Considered

1. **Extend `ru` plugin** — rejected. `ru`'s mental model is Stop-hook continuation; autonomous-loop's is `ScheduleWakeup` + contract. Different enough to live separately.
2. **Patch native `/loop`** — not in scope; `/loop` is shipped by Claude Code itself.
3. **Fold into `crucible` plugin** — rejected. `crucible` is research methodology; this is execution orchestration.

## Open Questions

- Should the `start` skill also seed a `.autonomous-loop/` directory for per-run metadata? For now: no — keep everything in the single contract file.
- Should we ship a GitHub Action that validates `LOOP_CONTRACT.md` structure? Deferred post-v1.
