# mise-hygiene-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-88 orchestrator)

mise.toml hygiene — 2-policy: (1) secrets detection (api keys, tokens, passwords) in `mise.toml`/`.mise.toml` [should be in `.mise.local.toml`]; (2) line-count > 100 → hub-spoke refactoring suggestion via `[task_config].includes`. Standalone hook still runnable for direct CLI invocation; the Write\|Edit hooks.json entry now points to the iter-84/85/86/87/88 orchestrator which imports `classifyMiseHygieneGuardForOrchestrator` from this file. Lightest-first registry position: AFTER `hoisted-deps-guard` and BEFORE `gpu-optimization-guard` (cheap filename-suffix + ignore-list fastpath; expensive policy work only runs on actual `mise.toml` writes).
