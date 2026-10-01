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

### Escape Hatch

Add `# INLINE-IGNORE-OK` or `// INLINE-IGNORE-OK` on the same line:

```python
import pysbd  # type: ignore[import]  # INLINE-IGNORE-OK
```
