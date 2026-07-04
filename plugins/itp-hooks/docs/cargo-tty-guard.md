# Cargo TTY Suspension Prevention

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Cargo TTY Suspension Prevention (2026-02-23)

**Problem**: Running `cargo bench` or `cargo test` with backgrounding (`&`) in Claude Code causes immediate suspension with `suspended (tty input)`.

**Root Cause**: Cargo spawns subprocesses that inherit stdin. When backgrounded, TTY contention triggers SIGSTOP.

**Solution**: `pretooluse-cargo-tty-guard.ts` hook automatically redirects to PUEUE daemon (process-isolated, no stdin inheritance).

### Usage

**Automatic (default)**:

```bash
cargo bench --bench rangebar_bench &
# 🛡️ Cargo TTY Guard: Redirecting to PUEUE daemon
# ✓ PUEUE task 42 completed
```

**Override (opt-out)**:

```bash
cargo bench & # CARGO-TTY-SKIP
```

**Force (opt-in)**:

```bash
cargo bench # CARGO-TTY-WRAP
```

**Full Documentation**: [cargo-tty-suspension-prevention.md](../../../docs/cargo-tty-suspension-prevention.md)

### Related GitHub Issues

- [#11898](https://github.com/anthropics/claude-code/issues/11898): TTY suspension on iTerm2
- [#12507](https://github.com/anthropics/claude-code/issues/12507): Subprocess stdin inheritance
- [#13598](https://github.com/anthropics/claude-code/issues/13598): Spurious /dev/tty reader


## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Bash

**Cargo TTY suspension prevention** — Redirects `cargo bench/test/build &` to PUEUE daemon (eliminates stdin inheritance, prevents SIGSTOP). See [Full Guide](../../../docs/cargo-tty-suspension-prevention.md)
