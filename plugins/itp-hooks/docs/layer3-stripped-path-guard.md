# layer3-stripped-path-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Write\|Edit\|MultiEdit

**Iter-78 edit-time companion to iter-77 release-time Check 4k** — blocks edits that introduce `${CLAUDE_PLUGIN_ROOT}/<segment>/` references where `<segment>` is NOT in the cache-populator allowlist (`hooks`, `skills`, `commands`, `agents`, `plugin.json`). Belt-and-suspenders defense per [GitHub #37210](https://github.com/anthropics/claude-code/issues/37210): stdout JSON `permissionDecision: "deny"` + stderr diagnostic + `exit 2`. Escape hatch: `LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>` same line or within 3 preceding lines. Pre-JSON-parse fastpath: short-circuits to `allow` in <1ms if raw stdin lacks `CLAUDE_PLUGIN_ROOT` substring. See [HOOKS.md "Iter-77 + Iter-78 Dual-Defense Architecture for L3-Stripped-Path Prevention"](../../../docs/HOOKS.md).
