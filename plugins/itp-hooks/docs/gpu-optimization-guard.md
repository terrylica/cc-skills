# gpu-optimization-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-87 orchestrator)

GPU optimization enforcement (AMP, batch-sizing, torch.compile, DataLoader optim, device-availability, cudnn.benchmark — 6 policy checks). Standalone hook still runnable for direct CLI invocation; the Write\|Edit hooks.json entry now points to the iter-84/85/86/87 orchestrator which imports `classifyGpuOptimizationGuardForOrchestrator` from this file. Iter-87 also refactored the orchestrator's per-subhook cooperative timeout from Symbol-sentinel + setTimeout to idiomatic `AbortSignal.timeout()` (Web Platform API; Node 17.3+ / Bun 1.0+).
