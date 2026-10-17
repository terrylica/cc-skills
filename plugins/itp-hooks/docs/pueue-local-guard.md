# pueue-local-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — created 2026-06-11 when the full-table snapshot docs were dissolved into per-hook spokes.

## What it checks (2026-10-17)

Purpose: a `pueue add` that was meant for a remote host (the agent lost its SSH context) must not run locally. It denies a `pueue add` whose own arguments carry a remote-context indicator; `# PUEUE-LOCAL-OK` bypasses it.

- **Only real invocations.** `pueue add` is found with the shared invocation walker (`lib/shell-command-invocation-walker.ts`), the same one the kill guards use. A `pueue add` inside a quoted grep pattern, a commit message, a comment or a heredoc written to a file is text, not a submission. Invocations inside `bash -c '…'` and after `cd …&&` are still found; one inside `ssh host '…'` already targets the remote and is skipped.
- **Indicators respect this machine.** The guard was written on a Mac and took every `/home/` path as proof of a remote target. On a Linux host that is the local home, so every local `pueue add` naming a file in it was denied. Now `/home/<user>` counts only when that directory does not exist here; `~/.local/bin/` only when this machine has no `~/.local/bin`; `clickhouse-client` only when it is not installed here. `/tmp/gen*`, `/tmp/sweep_*` and configured hostnames (`ITP_REMOTE_HOSTS`, `~/.config/itp-hooks/remote-hosts`) count as before.
- **Indicators are read from the invocation's own arguments**, not from anywhere in the command, so a `/home/` path in an unrelated part of a chained command does not count.

Tests: `hooks/pretooluse-pueue-local-guard.test.ts` (false positives above, plus the true positives: a home directory that does not exist here, a remote temp script, the escape hatch).

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Bash

Ensures pueue commands target local daemon (not remote)
