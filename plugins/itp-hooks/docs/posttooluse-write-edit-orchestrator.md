# PostToolUse Write/Edit Orchestrator (Iter-93→98)

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Topic**: Inlined context-injecting subhooks

## Overview

The iter-93 → iter-98 PostToolUse Write|Edit migration arc (Path B, orchestrator inlining) consolidated context-injecting subhooks into a single bun process via `posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts`.

**Path context**: Iter-92 audit ruled out Path A (async:true sweep via Anthropic's Jan-2026 schema flag) for context-injecting hooks because they must merge results; orchestrator inlining provides the merging capability.

## Core Design: Multi-Aggregation Semantics

Runs ALL subhooks in parallel via `Promise.all` (no short-circuit, unlike PreToolUse):

- Merges every non-empty `additional_context` payload into ONE consolidated `{decision: "block", reason: aggregate}` JSON
- Per-section `[orchestrator-subhook: <name>]` provenance prefix (iter-94 usability enhancement)
- Emits NOTHING when all subhooks return `noop` (preserves legacy silent-allow semantics)

## Cold-Start Savings

**Projection**: `(15-1) × 17ms ≈ 238ms` per Write|Edit cold-start savings (using iter-87's empirically-corrected 17ms per-subhook cost).

## Inlined Subhooks (7/15 complete as of iter-98)

1. **ty-type-check** (iter-93) → Python static type check (--python-version 3.14)
2. **tsgo-type-check** (iter-94) → TypeScript type check (project-scoped)
3. **oxlint-check** (iter-95) → Correctness + suspicious lint (JS/TS)
4. **biome-lint** (iter-95) → Complementary lint (catches oxlint gaps)
5. **vale-claude-md** (iter-96) → Vale terminology on CLAUDE.md (informational)
6. **ssot-principles** (iter-97) → SSoT/DI anti-pattern detection (ast-grep, once per session)
7. **memory-efficiency-reminder** (iter-98) → Once-per-session best-practices nudge

**Remaining (8 planned)**: lsp-diagnostic-collection, pylint-json, clippy-report, etc. (queue order TBD by iter-99+)

## Async Requirement (Iter-94 Critical Invariant)

Every inlined classifier MUST use `Bun.spawn` (async) — `Bun.spawnSync` halts the JS event loop and defeats `Promise.all` parallelism per [Bun docs](https://bun.com/docs/api/spawn) + 2026 community guidance.

The static audit task `.mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh` prevents regression.

## Contract & Isolation

Contract at [`lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts`](../hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts) enforces:

- Pure-function discipline per subhook
- Async via `Bun.spawn`
- Cooperative timeout via shared lib helpers
- Max buffer guardrails for concurrent stream drain

See [HOOKS.md "Iter-93: PostToolUse edit-time orchestrator kick-off"](../../../docs/HOOKS.md#iter-93-posttooluse-edit-time-orchestrator-kick-off--path-b-orchestrator-inlining-started-115-inlined).

## Per-Subhook Deep Dives

See individual spoke docs:

- [ty-type-check.md](./posttooluse-hooks-full-table.md)
- [tsgo-type-check.md](./posttooluse-hooks-full-table.md)
- [oxlint-check.md](./posttooluse-hooks-full-table.md)
- [biome-lint.md](./posttooluse-hooks-full-table.md)
- [vale-terminology-enforcement.md](./vale-terminology-enforcement.md)
- [ssot-principles.md](./ssot-principles.md)
- [memory-efficiency-reminder.md](./memory-efficiency-reminder.md)

## Migration Timeline

| Iter | Subhooks Inlined           | Count | Key Changes                                               |
| ---- | -------------------------- | ----- | --------------------------------------------------------- |
| 93   | ty-type-check              | 1     | **Arc kick-off** — Path B (orchestrator inlining)         |
| 94   | tsgo-type-check            | 2     | Project-scoped filtering; Bun.spawn-only invariant        |
| 95   | oxlint-check, biome-lint   | 4     | Shared lib helper hoists (async-spawn)                    |
| 96   | vale-claude-md             | 5     | Informational (not blocking); line-scoping ±3-line buffer |
| 97   | ssot-principles            | 6     | **FIRST real Promise.all parallel fan-out**               |
| 98   | memory-efficiency-reminder | 7     | Once-per-session gate via atomic claim helper             |

## Iter-98 Bug Fix: Silent Context Drop

Pre-iter-98 the standalone `memory-efficiency-reminder.ts` hook emitted the reminder via plain `console.log` (raw text — transcript-only, NOT Claude-visible per iter-66/93 forensic finding). Iter-98 orchestrator path emits proper `additional_context` decision (Claude-visible system reminder); standalone CLI now also emits JSON not raw text.

Also fixed a race-unsafe `existsSync(...) + writeFileSync(...)` gate pattern (atomic O_EXCL via shared helper now).
