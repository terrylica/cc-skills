# Design Spec: autonomous-loop plugin

**ADR**: [docs/adr/2026-04-20-autonomous-loop.md](../../adr/2026-04-20-autonomous-loop.md)
**Date**: 2026-04-20

## Motivating case study

A 37-iteration autonomous quant-research campaign in `opendeviationbar-patterns` demonstrated the pattern. Highlights:

- **Campaign scope**: GPU-accelerated evolutionary genetic programming + LightGBM meta-labeling on Open Deviation Bars across 4 FX symbols (EUR/XAU/XAG/GBP)
- **Duration**: 37 iterations over ~12 hours of wall-clock, multiple user `/loop` invocations + autonomous `ScheduleWakeup` firings
- **Contract file**: `findings/evolution/audits/2026-04-19-gp-gpu/LOOP_PROMPT.md` — evolved from iter-15 through iter-37, ~280 lines final, revision log tracks 10+ explicit state changes
- **Outcomes**:
  - 6 walk-forward-validated deployment rules surfaced (2 Tier A + 4 Tier B)
  - Three composition-layer "null-rescue" findings (PCCVE, DEUP, ensemble cost) that correctly steered the queue away from dead ends
  - Three campaign-pivotal findings that materially revised prior claims (DSR/PSR XAG-only, walk-forward Sharpe deflation, top-10 re-ranking)
  - Clean saturation stop after iter-37 with `PushNotification` delivered to the user

The campaign's effectiveness rested entirely on the contract file being the living source of truth. Every `/loop` firing ended with a contract revision, every finding changed the queue, every dead-end pivot was captured in the revision log.

## Skill contracts

### `autonomous-loop:start`

**Inputs** (via `AskUserQuestion`):

- `name` (slug) — short descriptive name for this loop
- `scope` (one-liner) — the Core Directive
- `contract_path` (default: `./LOOP_CONTRACT.md`) — where to write the contract
- `max_iterations` (default: 100) — soft cap

**Behavior**:

1. Verify `contract_path` does not already exist (or confirm overwrite)
2. Copy `templates/LOOP_CONTRACT.template.md` to `contract_path`
3. Substitute `<SHORT_DESCRIPTIVE_NAME>`, `<ISO_8601_UTC>`, `<RELATIVE_PATH_TO_LOOP_CONTRACT_MD>`, `<CORE DIRECTIVE>` fields
4. Print pointer-trigger snippet the user can paste into `/loop`
5. Optionally pre-invoke `/loop` with that pointer via the built-in loop skill

**Allowed tools**: `Bash`, `Read`, `Write`, `AskUserQuestion`, `Skill`

### `autonomous-loop:status`

**Inputs**: `contract_path` (auto-detect `./LOOP_CONTRACT.md` by default)

**Behavior**:

1. Parse YAML frontmatter — read `name`, `iteration`, `last_updated`, `exit_condition`, `max_iterations`
2. Extract last 3 entries from Revision Log section
3. Report: iteration count, minutes since last update, next queue item, active monitors
4. If `exit_condition` matches a DONE signal, print completion summary

**Allowed tools**: `Bash`, `Read`

### `autonomous-loop:stop`

**Behavior**:

1. Verify `LOOP_CONTRACT.md` exists
2. Append `## DONE` section with timestamp + reason (user-provided or "user-requested stop")
3. Send `PushNotification` with final state summary
4. Do NOT schedule a wake-up (loop terminates naturally on next firing when it sees the DONE marker)

**Allowed tools**: `Bash`, `Read`, `Edit`, `AskUserQuestion`, `Skill` (for PushNotification if needed via ToolSearch)

## Template file

`templates/LOOP_CONTRACT.template.md` ships the canonical structure. Sections in order:

1. **YAML frontmatter** — `name`, `version`, `iteration`, `last_updated`, `exit_condition`, `max_iterations`, `trigger`
2. **How to invoke** — pointer-trigger snippet
3. **Core Directive** — preserved verbatim
4. **Execution Contract** — Orient / Act / Revise / Persist
5. **Dynamic Wake-Up Policy** — the table with cache-TTL reasoning
6. **Commit Conventions** — scope tags + template
7. **Release Decision Rule** — 6 triggers
8. **Current State** — rewritten each firing
9. **Implementation Queue** — T1/T2/T3/T4 tiers
10. **Non-Obvious Learnings** — preserved across firings
11. **Revision Log** — append-only, one line per firing

## Test plan

Manual validation steps for v1:

1. `claude plugin install autoloop@cc-skills` in a fresh dir
2. `/autoloop:start` — confirm `LOOP_CONTRACT.md` created with placeholders substituted
3. `/loop "<pointer trigger>"` — confirm Claude reads the contract + acts + rewrites
4. `/autoloop:status` — confirm concise state report
5. `/autoloop:stop` — confirm DONE section appended, `PushNotification` sent
6. Restart session (auto-compact) and `/loop "<pointer trigger>"` — confirm loop resumes cleanly from contract state

## Non-goals

- Automated enforcement of the 4-phase contract (Orient/Act/Revise/Persist)
- Automatic log rotation / archiving (document, don't enforce)
- Cross-machine synchronization of contract files (user responsibility via git)
- Live dashboard / TUI (out of scope)
- Interaction with `pueue-job-orchestration` beyond documentation (Monitor is the ecosystem interop point)

## Dependencies

- Claude Code 2.1.101+ (for `ScheduleWakeup` dynamic-pacing mode)
- No Python, no Node, no external binaries — pure markdown + Bash
- Optional: `PushNotification` tool (surfaced via ToolSearch when needed by stop skill)
