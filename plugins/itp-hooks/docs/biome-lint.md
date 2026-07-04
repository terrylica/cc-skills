# biome-lint

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-95 orchestrator)

biome complementary lint on JS/TS (~40-80ms). **Iter-95 fourth inlined PostToolUse subhook (4/15 in arc)** — async Bun.spawn via shared lib helpers. COMPLEMENTARY-TO-OXLINT (not a replacement): catches rules oxlint misses with default config — useConst, noDoubleEquals, useNodejsImportProtocol, noImplicitAnyLet, noAssignInExpressions. 6 noisy rules suppressed via the `BIOME_LINT_RULES_SUPPRESSED_AT_HOOK_TIME_BECAUSE_TOO_NOISY_FOR_REAL_CODEBASES` constant (noExplicitAny, useNodejsImportProtocol, noUnusedVariables, noNonNullAssertion, useTemplate, noUnusedImports — 67% false-positive rate on real codebases). Algorithm encoded in `classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`; alias `classifyBiomeLintForPostToolUseOrchestrator`. Standalone hook still runnable via `import.meta.main` guard.
