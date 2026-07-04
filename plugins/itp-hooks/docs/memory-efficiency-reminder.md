# Memory Efficiency Reminder

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Topic**: Once-per-session best-practices nudge

## Overview

The `posttooluse-memory-efficiency-reminder.ts` hook (inlined in iter-98 orchestrator) surfaces a once-per-session memory-efficiency reminder on the first eligible code-file Write/Edit.

Pure static reminder (no subprocess spawn, sub-ms gate-claim only).

## Iter-98 Critical Bug Fix

Pre-iter-98 the standalone hook emitted the reminder via plain `console.log` (raw text — transcript-only, NOT Claude-visible per iter-66/93 forensic finding + Anthropic PostToolUse schema).

Iter-98 orchestrator path emits proper `additional_context` decision (Claude-visible system reminder via aggregated `{decision: block, reason}` JSON); standalone CLI now also emits JSON not raw text.

Also remediated a pre-iter-98 race-unsafe `existsSync(...) + writeFileSync(...)` gate pattern (atomic O_EXCL via shared helper now).

## What It Covers

- Zero-copy patterns
- Pre-allocation strategies
- Cache-locality optimization
- Lazy-evaluation techniques

## Escape Hatch

Add `MEMORY-EFFICIENCY-OK` to suppress the reminder.

Algorithm encoded in `classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator`; alias `classifyMemoryEfficiencyReminderForPostToolUseOrchestrator`.

Standalone hook still runnable via `import.meta.main` guard.

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-98 orchestrator)

Surfaces a once-per-session memory-efficiency reminder (zero-copy, pre-allocation, cache-locality, lazy-evaluation patterns) on the first eligible code-file Write/Edit. **Iter-98 SEVENTH inlined PostToolUse subhook (7/15 in arc)** — pure static reminder (no subprocess spawn, sub-ms gate-claim only). **Iter-98 ALSO FIXED a long-standing silent context-drop bug**: pre-iter-98 the standalone hook emitted the reminder via plain `console.log` (raw text — transcript-only, NOT Claude-visible per iter-66/93 forensic finding + Anthropic PostToolUse schema). The iter-92 async-eligibility audit had classified this hook as `[M] MIXED` (couldn't statically pattern-match the silent-drop), so the bug was in plain sight without surfacing. Iter-98 orchestrator path emits proper `additional_context` decision (Claude-visible system reminder via aggregated `{decision: block, reason}` JSON); standalone CLI now also emits JSON not raw text. Also remediated a pre-iter-98 race-unsafe `existsSync(...) + writeFileSync(...)` gate pattern (atomic O_EXCL via shared helper now). Algorithm encoded in `classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator`; alias `classifyMemoryEfficiencyReminderForPostToolUseOrchestrator`. Standalone hook still runnable via `import.meta.main` guard.
