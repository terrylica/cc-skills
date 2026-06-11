# Autoloop Stall Guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Autoloop Stall Guard

The `stop-loop-stall-guard.ts` hook enforces the autoloop skill's "Mandatory end-of-firing decision" rule at the harness level. Documentation in the skill describes the rule; this hook catches violations the model missed.

### How it works

Runs as a Stop hook with `asyncRewake: true`. When a stall is detected, the hook exits code 2 with a diagnostic on stderr. The Claude Code runtime wakes the just-stopped model with a system-reminder prefixed by the hook's `rewakeSummary` and containing the diagnostic body. The model responds by (per the reminder's instructions) running Phase 3 Revise + Phase 4 Persist with a proper waker — OR flipping `status: DONE`/`SATURATED` to stop honestly.

### Four gates (all must pass to fire stall)

| Gate | Check                                                  | Rationale                                                                                            |
| ---- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| 1    | `LOOP_CONTRACT.md` exists in session's `cwd`           | Narrows scope to autoloop projects                                                                   |
| 2    | Frontmatter `status` is NOT terminal                   | Terminal states: `done`, `saturated`, `paused`, `completed`, `stopped` — these are intentional stops |
| 3    | Last real user message contains `/loop` or `/autoloop` | Distinguishes loop firings from manual sessions in the same project                                  |
| 4    | Last assistant `tool_use` is NOT a valid waker         | Valid wakers: `ScheduleWakeup`, `Monitor`, `Agent`, `TeamCreate`, `SendMessage` (chain-in-turn)      |

Gate 3 specifically prevents false positives when the user opens Claude Code in a loop project for a quick manual task unrelated to the loop.

### Real-world incident caught

mql5 Campaign 4 firing on 2026-04-23 at 19:25 UTC — user manually triggered `/autoloop:start`, the model closed 2 GitHub issues + committed atomically, then ended with `PushNotification` and text-only "iter-22 already queued" rationalization. Observable as a 6+ minute idle gap with desynchronized state. The stall guard would have exit-2'd and rewakened the model to call a fresh `ScheduleWakeup` (or chain in-turn).

### Escape hatch

Set `CLAUDE_LOOP_STALL_GUARD_DISABLE=1` in the session's environment to skip the check entirely. Use when doing deliberately non-loop work in a loop project, or when manually winding down a loop.

### Design scope

This hook lives in itp-hooks (enforcement), not autoloop (skill doc). The skill stays declarative; itp-hooks holds the teeth. When the autoloop guidance evolves, this hook keeps enforcing the invariant.

