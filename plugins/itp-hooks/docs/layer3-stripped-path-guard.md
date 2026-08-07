# layer3-stripped-path-guard

> **RETIRED 2026-08-05.** Unregistered from `hooks.json`; the premise below is false. Kept for provenance and because the iter-107 escape-hatch-helper baseline test still references the implementation. **Do not re-register without new evidence.**

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Why it was retired (2026-08-05)

The guard assumed the Layer-2 → Layer-3 cache populator strips every plugin-root subtree outside `{hooks, skills, commands, agents, plugin.json}`. Measured on this machine, that is not what happens:

- `diff -rq` of `~/.claude/plugins/marketplaces/cc-skills/plugins/<p>` against the live L3 cache directory returns **exactly one** difference for each of `notes-commander`, `itp-hooks`, `doc-tools` and `gmail-commander` — the `.in_use` marker Claude Code adds. The L3 cache is a byte-identical full copy.
- `scripts/` — the canonical "stripped" example — is present in the latest cached version of **all 27** cc-skills plugins that ship one.
- Across 508 cached plugin-version directories the populator preserves `docs/`, `tests/`, `lib/`, `Sources/`, `launchd/`, `assets/`, `schemas/`, `templates/` and `libexec/` too.

A guard with a false premise emits only false positives. This one fired three times in a single session on documentation and test fixtures that merely _mentioned_ a path, blocking work that was correct.

The live hazard in this area is the opposite one and is now covered by [skill-plugin-root-guard.md](./skill-plugin-root-guard.md): `CLAUDE_PLUGIN_ROOT` is not a shell variable, so referencing it from a SKILL.md body silently resolves to the empty string.

Downstream docs that still assert the stripping premise — notably the `docs/HOOKS.md` cache-populator table — are annotated rather than deleted, because the historical measurement is real; what changed is the populator's behavior.

---

## Historical record (premise no longer holds)

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Write\|Edit\|MultiEdit

**Iter-78 edit-time companion to iter-77 release-time Check 4k** — blocks edits that introduce `${CLAUDE_PLUGIN_ROOT}/<segment>/` references where `<segment>` is NOT in the cache-populator allowlist (`hooks`, `skills`, `commands`, `agents`, `plugin.json`). Belt-and-suspenders defense per [GitHub #37210](https://github.com/anthropics/claude-code/issues/37210): stdout JSON `permissionDecision: "deny"` + stderr diagnostic + `exit 2`. Escape hatch: `LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>` same line or within 3 preceding lines. Pre-JSON-parse fastpath: short-circuits to `allow` in <1ms if raw stdin lacks `CLAUDE_PLUGIN_ROOT` substring. See [HOOKS.md "Iter-77 + Iter-78 Dual-Defense Architecture for L3-Stripped-Path Prevention"](../../../docs/HOOKS.md).
