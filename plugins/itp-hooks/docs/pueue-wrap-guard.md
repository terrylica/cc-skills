# pueue-wrap-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Bash

Auto-wraps long-running commands with pueue + injects OP_SERVICE_ACCOUNT_TOKEN for Claude Automation vault (MUST be LAST PreToolUse entry — enforced by [iter-61 audit](../../../.mise/tasks/audit-pretooluse-pueue-wrap-guard-is-last-pretooluse-entry-in-hooks-json-to-mitigate-github-15897-multi-hook-updatedInput-aggregation-last-writer-wins-bug.sh) wired into release:preflight Check 4g; mitigates [GitHub #15897](https://github.com/anthropics/claude-code/issues/15897) multi-hook updatedInput last-writer-wins bug)
