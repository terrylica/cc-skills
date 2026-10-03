# tsc-type-check

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`posttooluse-tsc-type-check.ts`](../hooks/posttooluse-tsc-type-check.ts), subhook `tsc-type-check` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 5000 ms).

## Overview

Type-checks with the native TypeScript compiler after every Write/Edit of a `.ts`/`.tsx` file. TypeScript 7 ships the Go-native compiler as `tsc` itself, installed by `typescript@latest`; there is no separate `tsgo` binary to install.

## Behavior

1. **Skips** files under `node_modules/`, throwaway files in temp directories, and any file with no `tsconfig.json` in it or an ancestor directory.
2. **Project scoping**: walks up from the edited file to the nearest `tsconfig.json` directory and runs `tsc --noEmit --singleThreaded` from there.
3. **Binary resolution** (preference order):
   - `node_modules/.bin/tsc` in the tsconfig directory or an ancestor
   - `tsc` on `PATH`
   - neither found → a once-per-session install reminder (`npm install -D typescript@latest`)
4. **Output filtering**: keeps only error lines that start with the edited file's tsconfig-relative path or contain its absolute path, so pre-existing errors in other files are not blamed on this edit. No matching lines → no output.
5. **Performance**: `--singleThreaded` stops tsc spawning parallel checker workers on every edit. The subprocess runs through the async `Bun.spawn` helper with its own 4000 ms timeout; on timeout or spawn failure the subhook reports nothing. A full-project check is typically around 200 ms.
6. Output is truncated to stay below Claude Code's 10,000-character hook-output limit.

The hook prefers a project-local `tsc` so the compiler version matches the project's lockfile rather than whatever is global on the machine.

## Code

The classifier is `classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifyTscTypeCheckForPostToolUseOrchestrator`.

The file also runs standalone through its `import.meta.main` guard:

```bash
echo '{"tool_input": {"file_path": "src/example.ts"}, "session_id": "test"}' | \
  bun plugins/itp-hooks/hooks/posttooluse-tsc-type-check.ts
```

## Test Coverage

[`posttooluse-tsc-type-check.test.ts`](../hooks/posttooluse-tsc-type-check.test.ts) covers the skip conditions (non-`.ts`/`.tsx`, `node_modules`, missing tsconfig), the temp-directory exemption, the once-per-session install reminder, the export aliases, and fail-open error handling.

## Doctrine

- **SSoT**: `Skill(typescript-7)` — TypeScript 7 (the Go-native `tsc`) is the only TypeScript.
- The hook does not check the TypeScript version; `pretooluse-typescript-version-guard.ts` (subhook `typescript-version-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md)) blocks pre-7 declarations in `package.json`.
- **Escape hatch**: none; type checking is always on after an edit.

## Known Limitations

1. **TypeScript 7+ only in practice**: `--singleThreaded` is a TypeScript 7 option. An older local `tsc` rejects it, and because that error names no source file the output filter drops it, so the hook reports nothing.
2. **Large monorepos**: each check is a full-project check, so very large projects should narrow `tsconfig.json`'s `include`/`exclude`.

## See Also

- [Orchestrator](./posttooluse-write-edit-orchestrator.md) (how subhooks are combined)
- [ty-type-check](./ty-type-checker.md) (Python type checking parallel)
- [js-ts-lint](./js-ts-lint.md) (complementary JS/TS linting: oxlint + biome)
