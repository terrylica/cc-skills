# ty Type Checker Configuration

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hooks: [`posttooluse-ty-type-check.ts`](../hooks/posttooluse-ty-type-check.ts) (subhook `ty-type-check` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md), orchestrator timeout 5000 ms) and [`stop-ty-project-check.ts`](../hooks/stop-ty-project-check.ts) (run by `stop-orchestrator.ts` as `ty-check`, 15000 ms).

## Two levels

ty runs **per-file** on every `.py`/`.pyi` edit (PostToolUse) and **project-wide** on session exit (Stop hook). Both argument vectors live in [`lib/stop-ty-project-check-args.ts`](../hooks/lib/stop-ty-project-check-args.ts), and neither passes `--python-version`:

| Level               | Command                                          |
| ------------------- | ------------------------------------------------ |
| Per-file (edit)     | `ty check <file> --output-format concise`        |
| Project-wide (Stop) | `ty check . --output-format concise --exit-zero` |

Both run in the session's working directory, so ty resolves the same Python version for each: `ty.toml` → `requires-python` → active env → ty's 3.14 default. Leaving the version to ty is what makes a repository's own pin win (issue #157); a command-line flag would override it. The per-file check used to force `--python-version 3.14`, which disagreed with the Stop check on any repository pinned below 3.14.

## Recommended ty.toml

Projects using ty should pin the version in `ty.toml` so manual `ty check` runs and the Stop hook agree:

```toml
[environment]
python-version = "3.14"

[terminal]
output-format = "concise"
```

## Per-file check

- Skips paths under `/.venv/` or `/node_modules/`, throwaway files in temp directories, and files no longer on disk.
- If `ty` is not installed, shows an install reminder (`uv tool install ty`) once per session.
- Exit codes 2 (configuration error) and 101 (ty internal bug) are treated as ty problems, not type errors, and report nothing; so do timeouts (the subprocess has its own 4000 ms limit).
- Real diagnostics are shown to Claude as additional context with an error/warning summary line, capped at 30 lines and truncated below Claude Code's 10,000-character hook-output limit.

## Resource guard

Both levels spawn ty through the shared async helper with `residentMemoryGuardedToolName: "ty"`, so they get the machine-wide concurrency slots and RSS watchdog described in [subprocess-resource-guard.md](./subprocess-resource-guard.md). When every slot is busy the check is skipped quietly. A watchdog memory kill is **not** swallowed: both hooks report it with the observed peak, because silence after such a kill is how the 2026-07-30 freeze recurred.

## Gate File Mechanism

The gate is per session ([`lib/ty-edit-gate.ts`](../hooks/lib/ty-edit-gate.ts)). The PostToolUse hook touches `/tmp/.claude-ty-edits/<session_id>.edited` after each eligible `.py`/`.pyi` edit. The Stop hook reads `session_id` from its own Stop payload, a common input field on every hook event ([hooks reference, "Common input fields"](https://code.claude.com/docs/en/hooks#common-input-fields)), which `stop-orchestrator.ts` forwards to the subhook's stdin unchanged. It runs only if **its own** `<session_id>.edited` exists, `ty` is on `PATH` (no install reminder at exit), and the working directory has a `pyproject.toml` or a top-level `.py` file. It then deletes only that one file; other sessions' gates are never read or removed.

A session id that is missing, or not a plain file-name token, means there is no gate: the PostToolUse hook writes none, and the Stop hook skips the check and deletes nothing. A shared fallback name such as `unknown.edited` would be consumed by whichever session stopped next, which is the cross-session behaviour this design removes. Skipping costs one advisory check; the per-file check still ran on every edit.

Before this change, the Stop hook ran when the directory held any session's gate and then deleted the whole directory, so one session's exit both ran a check for edits it never made and discarded every other session's pending check.

`CLAUDE_TY_EDIT_GATE_DIR` overrides the directory; tests use it so they never touch the live one.

The Stop hook output is informational `additionalContext` (first 20 diagnostic lines plus error, warning and file counts) and it fails open: any error prints `{}` and never blocks session exit.

## Code

The per-file classifier is `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifyTyTypeCheckForPostToolUseOrchestrator`. The file also runs standalone through its `import.meta.main` guard.
