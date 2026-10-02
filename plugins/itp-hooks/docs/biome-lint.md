# biome-lint

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`posttooluse-biome-lint.ts`](../hooks/posttooluse-biome-lint.ts), subhook `biome-lint` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 5000 ms).

## What it does

After a Write or Edit of a `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts` or `.cts` file, it runs `biome lint --no-errors-on-unmatched --max-diagnostics=20 --error-on-warnings --diagnostic-level=info <file>` (typically 40–80 ms) and shows any diagnostics to Claude as additional context. It is informational: a PostToolUse hook cannot undo the edit.

It complements [oxlint-check](./oxlint-check.md) rather than replacing it; both run in parallel on the same edit. Biome adds rules oxlint's default config misses, such as `useConst`, `noDoubleEquals`, `noImplicitAnyLet` and `noAssignInExpressions`.

## Suppressed rules

Six rules are passed as `--skip` because they are too noisy at hook time on real codebases; enforce them in a project's `biome.json` instead. The list is the constant `BIOME_LINT_RULES_SUPPRESSED_AT_HOOK_TIME_BECAUSE_TOO_NOISY_FOR_REAL_CODEBASES`:

- `lint/suspicious/noExplicitAny`
- `lint/style/useNodejsImportProtocol`
- `lint/correctness/noUnusedVariables`
- `lint/style/noNonNullAssertion`
- `lint/style/useTemplate`
- `lint/correctness/noUnusedImports`

`useNodejsImportProtocol` is skipped, so the hook does not report it, even though the file header comment and the install reminder still list it among biome's unique catches.

## Skips and failure modes

- Files under `node_modules/` and throwaway files in temp directories (the shared helper in [`lib/shared-temp-dir-edit-path-detection-iter124.ts`](../hooks/lib/shared-temp-dir-edit-path-detection-iter124.ts)) are not linted.
- If `biome` is not installed, it shows an install reminder (`bun add -g @biomejs/biome`) once per session.
- The biome subprocess has its own 4000 ms timeout; on timeout or any error the subhook reports nothing.
- Output is truncated to stay below Claude Code's 10,000-character hook-output limit.

## Code

The classifier is `classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifyBiomeLintForPostToolUseOrchestrator`. The file also runs standalone through its `import.meta.main` guard.
