# ADR: Remove `autoloop` and `chronicle-share` plugins

**Status**: Accepted
**Date**: 2026-06-23
**Author**: Terry Li

## Context

A marketplace-maintenance pass removed two plugins that were no longer earning
their keep:

1. **`autoloop`** — packaged the self-revising `LOOP_CONTRACT.md` pattern on top
   of `ScheduleWakeup`/`Monitor` for long-horizon autonomous work, with
   `/autoloop:*` commands and a `~/.claude/loops/registry.json` machine registry.
   In practice the native Claude Code `/loop` + `ScheduleWakeup` flow now covers
   the same ground directly, without a per-campaign `CONTRACT.md` file, a machine
   registry, a launchd safety-net, or a Stop-hook stall enforcer. The plugin's
   surface (86 files, a dedicated `stop-loop-stall-guard` subhook wired into the
   `stop-orchestrator`, a statusline loop-status block, and `.autoloop/` runtime
   storage) had become carrying cost disproportionate to its use.

2. **`chronicle-share`** — a 6-file producer-side "bundle → sanitize → R2 →
   presigned URL" skeleton that was explicitly _"not yet functional"_ and had no
   dependents.

This follows the same reasoning and convention as
[2026-04-20-remove-ru-plugin](./2026-04-20-remove-ru-plugin.md) (native `/loop`
superseded a bespoke loop plugin).

## Decision

Remove both plugins entirely from cc-skills:

**`autoloop` (full purge):**

- Delete `plugins/autoloop/` and its `.claude-plugin/marketplace.json` entry.
- Remove the `stop-loop-stall-guard` subhook from `stop-orchestrator.ts` along
  with the `rewakeOnExit2` mechanism that existed solely for it; delete
  `hooks/stop-loop-stall-guard.ts` and its doc; the orchestrator now runs **4**
  Stop subhooks (subprocess-cleanup, error-summary, ty-check, markdown-lint). The
  orchestrator's own `asyncRewake` hook-entry flag is removed.
- Remove the statusline loop-status block (`~/.claude/loops/registry.json`
  lookup + `CONTRACT.md` rendering) from `custom-statusline.sh`.
- Retire the `LOOP_CONTRACT.md` pattern from active docs; scrub dangling
  `See plugins/autoloop/hooks/heartbeat-tick.sh` pointers from sibling hooks
  (inlining the bash-5.2 `patsub_replacement` rationale where it was cited).
- Delete the local `.autoloop/` runtime campaign storage.

**`chronicle-share`:**

- Delete `plugins/chronicle-share/` and its marketplace entry.

**Both:**

- Drop their listings from `README.md`, `plugins/CLAUDE.md`, and other hubs.
- **Keep historical records**: [2026-04-20-autonomous-loop.md](./2026-04-20-autonomous-loop.md),
  its design spec, and the `remove-ru-plugin` ADR document past decisions and are
  **not** rewritten.

Marketplace plugin count: 38 → **36**.

## Migration

Users of `/autoloop:*` should use the native **`/loop`** with dynamic
`ScheduleWakeup` self-pacing (and `Monitor` for long fallbacks). For a durable,
self-revising task spec, keep a plain working doc in the repo and re-read it each
firing — no plugin, registry, or launchd plist required.

`chronicle-share` had no users; nothing to migrate.
