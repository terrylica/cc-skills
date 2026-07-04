# Inline Ignore Policy

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Inline Ignore Policy

The `pretooluse-inline-ignore-guard.ts` (PreToolUse) blocks new inline ignore comments, and `code-correctness-guard.sh` (PostToolUse) warns about existing ones.

### Hierarchy (Enforced)

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
| PreToolUse guard  | Write\|Edit | **DENY** if proposed content introduces new ignores     |
| PostToolUse audit | Write\|Edit | **WARN** about existing inline ignores (full-file scan) |

For Edit: only denies if `new_string` has more ignores than `old_string` (net-new detection).

### Escape Hatch

Add `# INLINE-IGNORE-OK` or `// INLINE-IGNORE-OK` on the same line:

```python
import pysbd  # type: ignore[import]  # INLINE-IGNORE-OK
```


## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Write\|Edit

Blocks inline ignore comments (`# noqa`, `# type: ignore`, `// eslint-disable`, `// biome-ignore`, `// oxlint-ignore`) — enforces config-level suppression
