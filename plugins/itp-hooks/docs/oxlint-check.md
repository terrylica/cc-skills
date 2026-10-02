# oxlint-check

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`posttooluse-oxlint-check.ts`](../hooks/posttooluse-oxlint-check.ts), subhook `oxlint-check` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 5000 ms).

## What it does

After a Write or Edit of a `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts` or `.cts` file, it runs:

```
oxlint -D correctness -D suspicious -A no-unused-vars -A no-empty-file -f unix <file>
```

oxlint takes about 40–65 ms on a single file. Only the `correctness` and `suspicious` categories are enabled because they catch runtime bugs (const reassignment, duplicate keys, `debugger` statements); style categories are left to project config. A non-zero exit shows the per-line diagnostics to Claude as additional context, with oxlint's summary line stripped. It is informational: a PostToolUse hook cannot undo the edit.

[biome-lint](./biome-lint.md) runs in parallel on the same files and covers rules oxlint's default config misses.

## Skips and failure modes

- Files under `node_modules/` and throwaway files in temp directories (the shared helper in [`lib/shared-temp-dir-edit-path-detection-iter124.ts`](../hooks/lib/shared-temp-dir-edit-path-detection-iter124.ts)) are not linted.
- If `oxlint` is not installed, it shows an install reminder (`bun add -g oxlint`) once per session.
- The oxlint subprocess has its own 4000 ms timeout; on timeout or any error the subhook reports nothing.
- Output is truncated to stay below Claude Code's 10,000-character hook-output limit.

## Code

The classifier is `classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifyOxlintCheckForPostToolUseOrchestrator`. Subprocesses go through the async helper `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail` in [`lib/posttooluse-subhook-async-helpers-iter95.ts`](../hooks/lib/posttooluse-subhook-async-helpers-iter95.ts). The file also runs standalone through its `import.meta.main` guard.
