# pyi-stub-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-89 orchestrator)

**Filename-vs-algorithm naming drift surfaced + remediated in iter-89.** Actual algorithm: blocks Write/Edit on Python `__init__.py` AND `__init__.pyi` files that contain top-level `class`/`def`/decorator definitions (PEP 561 + clean-package-structure: init files MUST be thin re-export layers; definitions belong in dedicated modules like `models.py`/`utils.py`/`constants.pyi`). The precise algorithm-encoding classifier name is `classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator`; the alias `classifyPyiStubGuardForOrchestrator` is maintained for symmetric naming with sibling subhooks. Honors docstring state (no false-positives inside triple-quote blocks), exempts `__getattr__`/`__dir__`/`__init_subclass__`/`_lazy_import` boilerplate (.py only — .pyi has stricter PEP 561 rules), and applies a re-export-dominated-write heuristic (≥70% imports) that exempts index files with incidental annotations. Escape hatch: `# INIT-MONOLITH-OK` comment in content. Standalone hook still runnable for direct CLI invocation; the Write\|Edit hooks.json entry now points to the iter-84/85/86/87/88/89 orchestrator which imports `classifyPyiStubGuardForOrchestrator` from this file. Lightest-first registry position: AFTER `mise-hygiene-guard` and BEFORE `gpu-optimization-guard` (cheap `__init__.py`/`__init__.pyi` filename-suffix `endsWith()` fastpath).
