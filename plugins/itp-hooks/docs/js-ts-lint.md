# JS/TS lint: oxlint-check + biome-lint

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hooks: [`posttooluse-oxlint-check.ts`](../hooks/posttooluse-oxlint-check.ts) and [`posttooluse-biome-lint.ts`](../hooks/posttooluse-biome-lint.ts), subhooks `oxlint-check` and `biome-lint` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 5000 ms each).

## What they do

After a Write or Edit of a `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts` or `.cts` file, both linters run concurrently on the edited file and show any diagnostics to Claude as additional context. Both are informational: a PostToolUse hook cannot undo the edit. Biome complements oxlint rather than replacing it.

| Check          | Command                                                                                                                       | Typical time | Catches                                                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `oxlint-check` | `oxlint -D correctness -D suspicious -A no-unused-vars -A no-empty-file -f unix <file>`                                       | 40–65 ms     | Runtime bugs: const reassignment, duplicate keys, `debugger` statements. Style is left to project config.                   |
| `biome-lint`   | `biome lint --no-errors-on-unmatched --max-diagnostics=20 --error-on-warnings --diagnostic-level=info <file>` + `--skip` list | 40–80 ms     | Rules oxlint's default config misses, such as `useConst`, `noDoubleEquals`, `noImplicitAnyLet` and `noAssignInExpressions`. |

oxlint reports on a non-zero exit, with its summary line (`Found N diagnostics` / `N problems`) stripped so only per-line diagnostics remain. Biome reports on a non-zero exit or when its stderr carries a `lint/` diagnostic.

## Biome's suppressed rules

Six rules are passed as `--skip` because they are too noisy at hook time on real codebases; enforce them in a project's `biome.json` instead. The list is the constant `BIOME_LINT_RULES_SUPPRESSED_AT_HOOK_TIME_BECAUSE_TOO_NOISY_FOR_REAL_CODEBASES`:

- `lint/suspicious/noExplicitAny`
- `lint/style/useNodejsImportProtocol`
- `lint/correctness/noUnusedVariables`
- `lint/style/noNonNullAssertion`
- `lint/style/useTemplate`
- `lint/correctness/noUnusedImports`

`useNodejsImportProtocol` is skipped, so the hook does not report it, even though the file header comment and the install reminder still list it among biome's unique catches.

## Skips and failure modes (both checks)

- Files under `node_modules/` and throwaway files in temp directories (the shared helper in [`lib/shared-temp-dir-edit-path-detection-iter124.ts`](../hooks/lib/shared-temp-dir-edit-path-detection-iter124.ts)) are not linted.
- If the linter is not installed, it shows an install reminder once per session: `bun add -g oxlint` or `bun add -g @biomejs/biome`.
- Each linter subprocess has its own 4000 ms timeout; on timeout or any error the subhook reports nothing.
- Output is truncated to stay below Claude Code's 10,000-character hook-output limit.

## Code

| Check          | Classifier                                                                                                       | Orchestrator alias                              |
| -------------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `oxlint-check` | `classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator` | `classifyOxlintCheckForPostToolUseOrchestrator` |
| `biome-lint`   | `classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`             | `classifyBiomeLintForPostToolUseOrchestrator`   |

Subprocesses go through the async helper `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail` in [`lib/posttooluse-subhook-async-helpers-iter95.ts`](../hooks/lib/posttooluse-subhook-async-helpers-iter95.ts). Both files also run standalone through their `import.meta.main` guard.

Related: [tsc-type-check.md](./tsc-type-check.md) (project-scoped type checking on the same `.ts`/`.tsx` edits).
