# version-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-85 orchestrator)

Version consistency validation (hardcoded version blocker for markdown). Renamed from `.mjs` to `.ts` in iter-85 for full TypeScript type-checking when imported by the orchestrator. Standalone hook still runnable for direct CLI invocation; the Write\|Edit hooks.json entry now points to the iter-84/85 orchestrator which imports `classifyVersionGuardForOrchestrator` from this file. See [Iter-85 audit-driven hardening](../../../docs/HOOKS.md#iter-85-version-guard-migration--audit-driven-orchestrator-hardening).
