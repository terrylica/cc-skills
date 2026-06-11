# ty Type Checker Configuration

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## ty Type Checker Configuration

ty runs at two levels: **per-file** on every .py/.pyi edit (PostToolUse) and **project-wide** on session exit (Stop hook). Both always pass `--python-version 3.14` explicitly to override ty's default of Python 3.14.

### Recommended ty.toml

Projects using ty should also pin the version in `ty.toml` for consistency when running ty manually:

```toml
[environment]
python-version = "3.14"

[terminal]
output-format = "concise"
```

The hooks pass `--python-version 3.14` explicitly regardless of `ty.toml`, but having the config ensures manual `ty check` runs also use 3.13.

### Silent Failures Only

The hooks never block on ty configuration errors (exit code 2) or internal bugs (exit code 101). These are treated as ty issues, not type errors, and the hook exits silently. Only actual type diagnostics trigger a block/context message.

### Gate File Mechanism

The PostToolUse hook writes a gate file to `/tmp/.claude-ty-edits/{sessionId}.edited` after each .py/.pyi edit. The Stop hook checks for these gate files to decide whether to run the project-wide check. Gate files are cleaned up after the Stop hook runs.

