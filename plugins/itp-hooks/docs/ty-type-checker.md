# ty Type Checker Configuration

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hooks: [`posttooluse-ty-type-check.ts`](../hooks/posttooluse-ty-type-check.ts) (subhook `ty-type-check` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md), orchestrator timeout 5000 ms) and [`stop-ty-project-check.ts`](../hooks/stop-ty-project-check.ts) (run by `stop-orchestrator.ts` as `ty-check`, 15000 ms).

## Two levels

ty runs **per-file** on every `.py`/`.pyi` edit (PostToolUse) and **project-wide** on session exit (Stop hook). They resolve the Python version differently:

| Level               | Command                                                         | Python version                                                                                                                                                      |
| ------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Per-file (edit)     | `ty check <file> --python-version 3.14 --output-format concise` | Always 3.14; the flag overrides any repo pin                                                                                                                        |
| Project-wide (Stop) | `ty check . --output-format concise --exit-zero`                | No flag (args in [`lib/stop-ty-project-check-args.ts`](../hooks/lib/stop-ty-project-check-args.ts)): `ty.toml` → `requires-python` → active env → ty's 3.14 default |

The Stop hook leaves the version to ty so a repository's own pin wins (issue #157).

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

The PostToolUse hook touches `/tmp/.claude-ty-edits/<session-id>.edited` after each eligible `.py`/`.pyi` edit. The Stop hook runs only if that directory holds any `.edited` file, `ty` is on `PATH` (no install reminder at exit), and the working directory has a `pyproject.toml` or a top-level `.py` file. It then deletes the whole `/tmp/.claude-ty-edits/` directory, including other sessions' gate files.

The Stop hook output is informational `additionalContext` (first 20 diagnostic lines plus error, warning and file counts) and it fails open: any error prints `{}` and never blocks session exit.

## Code

The per-file classifier is `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifyTyTypeCheckForPostToolUseOrchestrator`. The file also runs standalone through its `import.meta.main` guard.
