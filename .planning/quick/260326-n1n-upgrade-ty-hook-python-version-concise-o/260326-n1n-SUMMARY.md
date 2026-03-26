---
phase: quick
plan: 260326-n1n
subsystem: itp-hooks
tags: [ty, python, type-checking, hooks, python-version]
dependency_graph:
  requires: []
  provides: [ty-python-313-enforcement, cross-file-type-checking]
  affects: [itp-hooks]
tech_stack:
  added: []
  patterns: [gate-file-signaling, concise-output-parsing]
key_files:
  created:
    - plugins/itp-hooks/hooks/stop-ty-project-check.ts
  modified:
    - plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts
    - plugins/itp-hooks/hooks/hooks.json
    - plugins/itp-hooks/CLAUDE.md
decisions:
  - Gate file mechanism for PostToolUse-to-Stop hook communication
  - Concise format parsing with error/warning count extraction
  - 30 line truncation for PostToolUse, 20 for Stop hook
metrics:
  duration: 3m28s
  completed: 2026-03-26
---

# Quick Task 260326-n1n: Upgrade ty Hook Suite Summary

ty type checker hooks upgraded with --python-version 3.13 enforcement, concise output parsing, and project-wide Stop hook for cross-file type checking.

## Completed Tasks

| #   | Task                                 | Commit     | Files                        |
| --- | ------------------------------------ | ---------- | ---------------------------- |
| 1   | Upgrade posttooluse-ty-type-check.ts | `02c70e60` | posttooluse-ty-type-check.ts |
| 2   | Create stop-ty-project-check.ts      | `689b106d` | stop-ty-project-check.ts     |
| 3   | Register stop hook + update docs     | `af5afb8d` | hooks.json, CLAUDE.md        |

## What Changed

### Task 1: PostToolUse Hook Upgrade

- Pinned `--python-version 3.13` (overrides ty default of 3.14, per project policy)
- Added `--output-format concise` for one-line diagnostics
- Parse output into error/warning counts with structured summary
- Accept `.pyi` stub files alongside `.py`
- Skip `.venv/` and `node_modules/` paths
- Check file existence before ty invocation (file may be deleted between Write and hook)
- Handle exit codes 2 (config error) and 101 (internal bug) silently
- Truncate output at 30 lines to prevent context flooding
- Write gate file to `/tmp/.claude-ty-edits/` for Stop hook tracking
- Switched to `node:fs` and `node:path` imports

### Task 2: Stop Hook (New)

- Project-wide `ty check .` on session exit
- Only runs when gate files exist (Python files were edited)
- Detects Python projects via `pyproject.toml` or `.py` files in CWD
- Silent skip when ty not installed (no install reminder from Stop hooks)
- Summarizes with unique file count across diagnostics
- Truncates at 20 diagnostic lines
- Cleans up gate files after run
- Uses `additionalContext` JSON output (non-blocking)
- 15s timeout for project-wide check
- `--exit-zero` flag prevents non-zero exit codes

### Task 3: Registration and Documentation

- Registered `stop-ty-project-check.ts` in hooks.json Stop section
- Updated PostToolUse table entry with --python-version 3.13 mention
- Added Stop hook to Stop Hooks table
- Added "ty Type Checker Configuration" section with recommended ty.toml
- Documented gate file mechanism and silent failure philosophy

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed trailing comma in hooks.json PostToolUse array**

- **Found during:** Task 3
- **Issue:** Pre-existing trailing comma after last entry in PostToolUse array made hooks.json invalid JSON per strict parsers (node's `require()` rejected it; Bun tolerates it)
- **Fix:** Removed trailing comma
- **Files modified:** plugins/itp-hooks/hooks/hooks.json
- **Commit:** af5afb8d

## Known Stubs

None -- all hooks are fully wired with real ty invocations.

## Verification Results

All 6 checks passed:

1. PostToolUse hook exits 0 on empty input
2. Stop hook outputs valid JSON (`{}`)
3. `--python-version` present in PostToolUse hook (3 occurrences)
4. `--python-version` present in Stop hook (2 occurrences)
5. `concise` present in PostToolUse hook (5 occurrences)
6. hooks.json is valid JSON
