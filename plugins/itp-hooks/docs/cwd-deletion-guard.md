# CWD Deletion Guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## CWD Deletion Guard

The `pretooluse-cwd-deletion-guard.ts` hook prevents commands that would delete the current working directory. When CWD is deleted, the shell becomes permanently broken — every subsequent command (including `cd`) fails with exit code 1.

### Two Lessons Encoded

| Lesson              | Problem                                   | Solution                                                |
| ------------------- | ----------------------------------------- | ------------------------------------------------------- |
| Never delete CWD    | Shell unrecoverable after `rm -rf $(pwd)` | Delete it from a session started elsewhere              |
| Don't rm + re-clone | Wasteful and breaks CWD                   | `git remote set-url` + `git fetch` + `git reset --hard` |

### Detection Patterns

| Pattern          | Example                                               |
| ---------------- | ----------------------------------------------------- |
| Exact path match | `rm -rf /path/to/cwd` where path = CWD                |
| Parent deletion  | `rm -rf ~/fork-tools` when CWD is `~/fork-tools/repo` |
| Relative CWD     | `rm -rf .` or `rm -rf ./`                             |
| Shell expansion  | `rm -rf $(pwd)` or `rm -rf $PWD`                      |
| Tilde expansion  | `rm -rf ~/project` matching CWD                       |

### What counts (2026-10-17)

Only an `rm -r` (or `-R`, `--recursive`), `rmdir`, or `mv` whose SOURCE operand resolves to the protected directory or one of its parents. Invocations are found with the shared invocation walker, so quoted text, comments, commit messages and heredocs written to files are not commands, while `bash -c '…'` and `xargs` are looked through and `ssh host '…'` (another machine) is skipped.

- The previous matcher read text: any `rm` with `-f` plus `$PWD` or `$(pwd)` anywhere in the command was a hit, so `pueue add -w "$PWD" -- cmd && rm -f reports/x.json` was denied. `-w "$PWD"` is not an rm operand.
- Operands resolve against the directory after any `cd` earlier in the command; `$PWD`, `${PWD}`, `$(pwd)` and `` `pwd` `` mean that directory, `~` and `$HOME` the home directory. Any other expansion is unknowable and is not reported.
- A glob counts when it can match the protected directory itself (`rm -rf ../*`), not when it only matches its children (`rm -rf *`).
- Protected: the session's working directory always (Claude Code resumes there after the command, so `cd /tmp && rm -rf <cwd>` still strands the session), and the directory the command has `cd`'d into.

Tests: `hooks/cwd-deletion-patterns.test.ts`.

### Git-Aware Guidance

When the command includes `git clone` or `gh repo clone` (rm-before-reclone pattern), the denial message suggests `git remote set-url` instead:

```bash
# Instead of: rm -rf ~/fork-tools/repo && git clone <new-url> ~/fork-tools/repo
# Do:
git remote set-url origin <new-url>
git fetch origin
git reset --hard origin/main
```

### Escape Hatch

Add `# CWD-DELETE-OK` comment to bypass:

```bash
rm -rf ~/fork-tools/repo  # CWD-DELETE-OK
```

## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Bash

Prevents deleting the current working directory
