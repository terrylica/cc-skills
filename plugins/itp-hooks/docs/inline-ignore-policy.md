# Inline Ignore Policy

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Inline Ignore Policy

`code-correctness-guard.sh` (PostToolUse) warns about inline ignore comments after a Write or Edit. Nothing blocks them: the PreToolUse guard that once did was unregistered on 2026-04-24 for rejecting legitimate escape hatches, and its source was deleted on 2026-10-01.

### Hierarchy (warned, not blocked)

1. **FIX THE ERROR** (preferred) — add type annotations, casts, None checks, `__all__` for re-exports
2. **CONFIG-LEVEL IGNORE** (only for tool/library limitations):
   - ruff: `[lint.per-file-ignores]` in `ruff.toml`
   - ty: `[[overrides]]` in `ty.toml` with `include` pattern
   - oxlint: `.oxlintrc.json` rules section
   - biome: `biome.json` linter.rules section
3. **NEVER**: Inline `# noqa` / `# type: ignore` / `// eslint-disable`

### Detection Patterns

| Language        | Patterns Detected                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Python (.py)    | `# noqa`, `# noqa: XXX`, `# type: ignore`, `# type: ignore[xxx]`, `# ty: ignore`, `# ty: ignore[xxx]`                  |
| JS/TS (.ts etc) | `// eslint-disable-next-line`, `// eslint-disable-line`, `/* eslint-disable */`, `// biome-ignore`, `// oxlint-ignore` |

### Enforcement

| Hook              | Event       | Behavior                                                |
| ----------------- | ----------- | ------------------------------------------------------- |
| PostToolUse audit | Write\|Edit | **WARN** about existing inline ignores (full-file scan) |

### The repository's own convention (2026-10-17)

A `# noqa: CODE` is not reported when the repository has already decided on that code. Reported case: `# noqa: E402` after `sys.path.insert(...)` was flagged in a repository that uses the pattern in every script. A line is skipped when every code on it is:

- **E402 in a file that changes `sys.path`** (`sys.path.insert`, `sys.path.append`, `site.addsitedir`) — the import has to follow the path change, and ruff has no rule-level way to say so;
- **ignored by the repository's ruff configuration for this file**, read with a TOML parser (`hooks/lib/ruff-ignored-codes.ts`): `ignore` / `extend-ignore`, or a `per-file-ignores` glob that matches the file; selectors are prefixes (`E` or `E4` covers E402, `ALL` covers everything). A code that is only in `select` does not count; or
- **suppressed inline in at least three other files committed at `HEAD`** (`git grep … HEAD`) — an established pattern, not a one-off; uncommitted suppressions cannot vouch for each other. Each code is looked up once per file.

Still reported: a bare `# noqa`, every `# type: ignore` / `# ty: ignore`, and any code without such a convention behind it. Test: `hooks/tests/test-code-correctness-guard-inline-ignore-convention.sh`.

### Escape Hatch

Add `# INLINE-IGNORE-OK` or `// INLINE-IGNORE-OK` on the same line:

```python
import pysbd  # type: ignore[import]  # INLINE-IGNORE-OK
```
