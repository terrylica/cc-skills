# hoisted-deps-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-86 orchestrator)

pyproject.toml root-only + [tool.uv.sources] path-escape + sub-package [dependency-groups] policies (3 enforcement paths, maturin PyO3 carve-out). Renamed from `.mjs` to `.ts` in iter-86. Standalone hook still runnable for direct CLI invocation; the Write\|Edit hooks.json entry now points to the iter-84/85/86 orchestrator which imports `classifyHoistedDepsGuardForOrchestrator` from this file.
