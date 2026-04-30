# ADR: Remove `ru` plugin — superseded by `autonomous-loop`

**Status**: Accepted
**Date**: 2026-04-20
**Author**: Terry Li

## Context

The `ru` plugin (autonomous loop mode via Stop-hook + Ralph Wiggum continuation) shipped in cc-skills through v12.52.0 at version 11.93.0. It provided `/ru:start`, `/ru:stop`, `/ru:status`, and related commands, backed by activation-gated Stop/PreToolUse hooks.

Two 2026-04 developments changed the picture:

1. **Claude Code 2.1.101+** shipped native `/loop` with dynamic self-pacing via `ScheduleWakeup` — removing the primary reason `ru` existed (a way to "keep going" across Stop events).
2. **cc-skills v12.52.0** shipped the new `autonomous-loop` plugin, which packages the self-revising `LOOP_CONTRACT.md` pattern on top of the native `ScheduleWakeup`/`Monitor` primitives. It is host-agnostic, subscription-safe, and universally compatible.

`ru`'s Stop-hook mechanism conflicts with the model's own completion signal in some harnesses, and its `.claude/ru-state.json` activation file adds per-project state that `autonomous-loop`'s single-file `LOOP_CONTRACT.md` already covers more cleanly.

## Decision

Remove the `ru` plugin entirely from cc-skills:

- Delete `plugins/ru/` directory (all skills, hooks, scripts, tests)
- Remove the `ru` entry from `.claude-plugin/marketplace.json`
- Delete stale local state `.claude/ru-state.json`
- Keep historical ADRs referencing "ralph" (they document past decisions and must not be rewritten)

## Migration

Users of `/ru:*` commands should switch to `autonomous-loop`:

| Before          | After                                                                            |
| --------------- | -------------------------------------------------------------------------------- |
| `/ru:start`     | `/autoloop:start`                                                                |
| `/ru:status`    | `/autoloop:status`                                                               |
| `/ru:stop`      | `/autoloop:stop`                                                                 |
| `/ru:forbid`    | (not yet ported — add an entry to `LOOP_CONTRACT.md`'s "Current State" manually) |
| `/ru:encourage` | (same as above)                                                                  |
| `/ru:audit-now` | (handled via the contract's Implementation Queue)                                |

The behavioral shift: `autonomous-loop` uses a short `/loop` pointer + evolving `LOOP_CONTRACT.md` contract file instead of the ru-state.json activation model. Users should scaffold a contract and paste the provided pointer-trigger snippet into `/loop`.

## Consequences

### Positive

- One canonical autonomous-loop mechanism in cc-skills, aligned with native Claude Code primitives
- Removes ~100 KB of plugin code (skills, hooks, tests, templates) + the `ralph-guidance-freshness-detection` behavioral complexity
- Eliminates the Stop-hook interference risk for users who opt into `autonomous-loop`

### Negative

- **Breaking change**: downstream users who have `/ru:*` in workflows must migrate
- Advanced `ru` features (forbid/encourage lists, wizard, audit-now) have no one-to-one replacement in `autonomous-loop` v1 and require contract-editing instead

### Neutral

- Historical ADRs remain in `docs/adr/` as decision history; this ADR supersedes them for current intent only

## Alternatives Considered

1. **Keep `ru` alongside `autonomous-loop`** — rejected. Two overlapping autonomous-loop mechanisms confuse users and double-maintain.
2. **Port `ru` hooks to `autonomous-loop`** — rejected. The Stop-hook model is fundamentally different from the `ScheduleWakeup` model; merging would re-introduce the coupling we wanted to remove.
3. **Archive `ru` as deprecated, keep installable** — rejected. "Deprecated but still installable" increases surface area for users who don't read changelogs. Clean break is safer.
