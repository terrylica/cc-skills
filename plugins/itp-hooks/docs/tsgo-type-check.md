# tsgo-type-check

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-94 orchestrator)

tsgo type checker on .ts/.tsx files (~170ms project check, every edit). **Iter-94 second inlined PostToolUse subhook (2/15 in arc)** — async Bun.spawn from day one (no spawnSync legacy). Project-scoped: walks up to find nearest tsconfig.json, filters output to errors referencing the edited file's tsconfig-relative path (avoids basename collisions when two `index.ts` files live in different project subdirs). Algorithm encoded in `classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator`; alias `classifyTsgoTypeCheckForPostToolUseOrchestrator` preserves symmetric naming with sibling subhooks. Standalone hook still runnable via `import.meta.main` guard for direct CLI invocation.
