# oxlint-check

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-95 orchestrator)

oxlint correctness+suspicious lint on JS/TS files (~50ms, every edit). **Iter-95 third inlined PostToolUse subhook (3/15 in arc)** — async Bun.spawn via the new shared lib helpers (`executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail`). Only correctness + suspicious categories enabled — these catch RUNTIME bugs (const reassignment, duplicate keys, debugger statements) rather than style preferences (best handled by config-level enforcement). Algorithm encoded in `classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`; alias `classifyOxlintCheckForPostToolUseOrchestrator`. Standalone hook still runnable via `import.meta.main` guard.
