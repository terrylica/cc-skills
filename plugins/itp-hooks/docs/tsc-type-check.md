# tsc-type-check

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — native TypeScript 7+ compiler hook.

## Overview

Native TypeScript compiler type checker on `.ts`/`.tsx` files — uses the `tsc` binary from TypeScript 7+ (Go-based, included in `typescript@latest`). **Iter-126 migration from deprecated `tsgo` (@typescript/native-preview is now FROZEN).**

**Matcher**: (inlined in iter-126 orchestrator)

## Behavior

Runs `tsc --noEmit --singleThreaded` after every Write/Edit of a `.ts`/`.tsx` file.

### Key Design Points

1. **Binary resolution** (preference order):
   - Project's local `node_modules/.bin/tsc` (walks up to find it)
   - System PATH `tsc`
   - Falls back to once-per-session install reminder on ENOENT

2. **Project-scoped execution**:
   - Walks up the filesystem to find the nearest `tsconfig.json` directory
   - Runs from that directory to respect TypeScript's project-scoped type checking
   - Filters output to errors referencing the edited file's tsconfig-relative path
   - Avoids "blame innocent files" — pre-existing errors in other files are suppressed

3. **Performance tuning**:
   - Passes `--singleThreaded` to prevent 4-worker checker spawn per keystroke (unnecessary parallelism on dev machines where tsc is I/O-dominated, not CPU-bound)
   - Async `Bun.spawn` (iter-94 refactor preserved; no `spawnSync` blocking the event loop)
   - 4000ms cooperative timeout with `AbortSignal`

4. **Iteration history**:
   - **Iter-94** (2026-06): Introduced `tsgo` — Go-native compiler from `@typescript/native-preview`
   - **Iter-126** (2026-07): Migrated to native `tsc` (TypeScript 7+), deprecated tsgo because `@typescript/native-preview` is frozen

### Algorithm

Encoded in `classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator`; re-exported as `classifyTscTypeCheckForPostToolUseOrchestrator` for symmetric naming with sibling subhooks (ty, oxlint, biome).

### Standalone CLI

Runnable via `import.meta.main` guard for direct invocation:

```bash
echo '{"tool_input": {"file_path": "src/example.ts"}, "session_id": "test"}' | \
  bun plugins/itp-hooks/hooks/posttooluse-tsc-type-check.ts
```

## Migration from tsgo (Iter-126)

### What Changed

| Aspect       | tsgo                                  | tsc                                                                        |
| ------------ | ------------------------------------- | -------------------------------------------------------------------------- |
| Binary       | `@typescript/native-preview` (frozen) | TypeScript 7+ (included in `typescript@latest`)                            |
| Command      | `tsgo --noEmit`                       | `tsc --noEmit --singleThreaded`                                            |
| Installation | Separate global binary                | No separate step; bundled in `npm install -D typescript@latest`            |
| Perf         | ~170ms full-project check             | ~200ms full-project check (similar, I/O-dominated)                         |
| Threading    | Not exposed to user                   | Explicit `--singleThreaded` avoids unnecessary parallelism on dev machines |

### Migration Path

Projects using `@typescript/native-preview` should:

1. Remove `@typescript/native-preview` from `package.json` (if installed)
2. Ensure `typescript@latest` is installed:

   ```bash
   npm install -D typescript@latest
   ```

3. Commit the updated `package-lock.json` (or equivalent lockfile)
4. The hook will automatically detect and use the local `tsc` binary

No code changes required; the hook is backward compatible.

### Why Not Use Global tsc?

The hook prefers a **project-local** `tsc` (from `node_modules/.bin/tsc`) over any system PATH `tsc`. This ensures:

- TypeScript version matches the project's pinned version
- Multi-project machines don't have conflicting global tooling
- CI/CD environments are reproducible

## Test Coverage

`posttooluse-tsc-type-check.test.ts` covers:

- Basic skip conditions (non-.ts/.tsx, node_modules, missing tsconfig)
- Temp directory exemption (iter-124)
- Install reminder (once-per-session gate-file)
- Export aliases for orchestrator integration
- Error handling (fail-open discipline)

**Current**: 15/15 tests pass.

## Integration

Inlined in the PostToolUse edit-time orchestrator as the 2nd subhook (after `ty-type-check`, before `oxlint-check`). Runs in parallel with `oxlint`, `biome`, and `ssot-principles` via `Promise.all` (iter-94+ architecture).

### Registry Entry

```typescript
{
  name: "tsc-type-check",
  timeoutMs: 5000,
  classify: classifyTscTypeCheckForPostToolUseOrchestrator,
  description: "..."
}
```

## Doctrine

- **SSoT**: `~/.claude/typescript-latest-CLAUDE.md` (TypeScript 7 = Go-native tsc era)
- **Compliance**: Hook enforces TypeScript 7+ via `classifyTscTypeCheckForPostToolUseOrchestrator`
- **Escape hatch**: None (type checking is always-on post-edit)

## Known Limitations

1. **No support for older TypeScript**: Requires TypeScript 7.0+ (uses native `tsc`)
2. **Performance not optimized for massive monorepos**: 200ms is practical for typical projects; projects with >100K files should tune `tsconfig.json`'s `include`/`exclude` scopes

## See Also

- [Orchestrator arc](./posttooluse-write-edit-orchestrator.md) (how subhooks are combined)
- [ty-type-check](./ty-type-checker.md) (Python type checking parallel)
- [oxlint-check](./oxlint-check.md) (complementary JS/TS linting)
