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


## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-93 orchestrator)

ty type checker on .py/.pyi files with --python-version 3.14, concise output (every edit). **Iter-93 first inlined PostToolUse subhook** — kicks off the iter-93+ PostToolUse Write\|Edit migration arc (Path B per iter-92 audit; async:true was ruled out for context-injecting hooks). Standalone hook still runnable via `import.meta.main` guard for direct CLI invocation; the Write\|Edit hooks.json entry now points to `posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts` which imports `classifyTyTypeCheckForPostToolUseOrchestrator` from this file (algorithm encoded in `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator`, alias preserved for symmetric naming).
