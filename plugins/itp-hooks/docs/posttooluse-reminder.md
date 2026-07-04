# posttooluse-reminder

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Bash\|Write\|Edit

Context-aware reminders (UV, Pueue, graph-easy, ADR sync, setproctitle, file-size, **fail-fast**). **Fail-fast nudge** (added 2026-06-08): on a Bun/TS/JS Write/Edit, if the file is a long-running awaited loop that catches errors and `continue`s with NO fail-fast path (no `throw`, no `process.exit(<non-zero>)`), it reminds Claude to halt-on-error (retry only transient errors, persist resumable state, exit non-zero, offer a `SKIP_BAD`-style opt-out) instead of swallow-and-continue. Motivated by the yukon non-PDF back-scan silently masking HEIC/timeout errors. High-precision (requires awaited loop + `catch…continue` + no halt path); escape hatch `FAIL-FAST-OK`. Reminder only, never blocks.
