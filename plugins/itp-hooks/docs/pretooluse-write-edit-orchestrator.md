# PreToolUse Write/Edit Orchestrator (Iter-84→91)

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Topic**: Inlined subhook consolidation

## Overview

The iter-84 → iter-91 PreToolUse Write|Edit migration arc consolidated 8 subhooks (version-guard, hoisted-deps-guard, mise-hygiene-guard, pyi-stub-guard, native-binary-guard, gpu-optimization-guard, file-size-guard, vale-claude-md-guard) into a single bun process via `pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts`.

## Cold-Start Performance

**Iter-87 empirical correction**: per-saved-subhook cost is ~17ms (NOT iter-80's ~44ms estimate, which conflated stdin-parse + classifier overhead with pure cold-start). Final-state savings = `(8-1) × 17` = **~119ms per Write|Edit** (NOT iter-81's 308ms projection). Iter-89 web research independently corroborated this via 2026 Bun 1.3 8-15ms cold-start benchmarks.

## Subhook Registry (Lightest-First Deny-Wins)

Inlined in this order (each can exit early if it denies):

1. **version-guard** → Hardcoded version blocker for markdown
2. **hoisted-deps-guard** → pyproject.toml root-only + [tool.uv.sources] escape policies
3. **mise-hygiene-guard** → Secrets detection + line-count refactoring suggestion
4. **pyi-stub-guard** → Blocks **init**.py/**init**.pyi with top-level definitions
5. **native-binary-guard** → Blocks launchd shell scripts (Swift preferred)
6. **gpu-optimization-guard** → GPU optimization enforcement (6 policy checks)
7. **file-size-guard** → Per-extension line-count limits
8. **vale-claude-md-guard** → **FINAL subhook** — terminology conformance (REJECT on violation)

## Contract & Isolation

Subhook contract at [`lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts`](../hooks/lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts) enforces:

- Pure-function discipline per subhook
- Cooperative timeout via `AbortSignal.timeout()`
- Crash isolation via try/catch

Belt-and-suspenders deny defense per [GitHub #37210](https://github.com/anthropics/claude-code/issues/37210):

- stdout JSON: `permissionDecision: "deny"`
- stderr diagnostic
- exit 2

## Per-Subhook Deep Dives

See individual spoke docs:

- [version-guard.md](./pretooluse-hooks-full-table.md)
- [hoisted-deps-guard.md](./pretooluse-hooks-full-table.md)
- [mise-hygiene-guard.md](./pretooluse-hooks-full-table.md)
- [pyi-stub-guard.md](./pretooluse-hooks-full-table.md)
- [native-binary-guard.md](./native-binary-guard.md)
- [gpu-optimization-guard.md](./pretooluse-hooks-full-table.md)
- [file-size-guard.md](./file-size-guard.md)
- [vale-terminology-enforcement.md](./vale-terminology-enforcement.md)

## Silent Context Drop Bug (Iter-90 Audit)

Iter-90 added a marketplace-wide PreToolUse `additionalContext` silent-drop NON-USE invariant audit per [GitHub #15664](https://github.com/anthropics/claude-code/issues/15664) — emission-pattern grep (not prose-comment) confirms ZERO classifiers emit the silently-dropped field.

## Migration Timeline

| Iter | Subhooks Inlined                          | Count | Key Changes                         |
| ---- | ----------------------------------------- | ----- | ----------------------------------- |
| 84   | version-guard, file-size-guard            | 2     | Orchestrator inception              |
| 85   | (none)                                    | 2     | version-guard renamed .mjs → .ts    |
| 86   | hoisted-deps-guard                        | 3     | pyproject.toml policies             |
| 87   | gpu-optimization-guard, timeout refactor  | 4     | Per-subhook ~17ms cost correction   |
| 88   | mise-hygiene-guard                        | 5     | Secrets + line-count hygiene        |
| 89   | pyi-stub-guard, marketplace audit         | 6     | init-file monolith detection        |
| 90   | (none)                                    | 6     | Marketplace additionalContext audit |
| 91   | native-binary-guard, vale-claude-md-guard | 8     | **Arc COMPLETE**                    |
