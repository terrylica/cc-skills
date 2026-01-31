# ITP Hooks

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Hooks](https://img.shields.io/badge/Hooks-16-orange.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Claude Code plugin for ITP (Implement The Plan) workflow enforcement via PreToolUse and PostToolUse hooks.

## Installation

```bash
# From cc-skills marketplace
/plugin install itp-hooks@cc-skills
```

## Setup

After installation, run setup to check and install optional linters:

```bash
# Check dependencies
/itp-hooks:setup

# Auto-install all linters
/itp-hooks:setup --install
```

Then install hooks to your settings:

```bash
/itp-hooks:hooks install
```

**IMPORTANT**: Restart Claude Code session for hooks to take effect.

## Features

### Hard Blocks (PreToolUse - Cannot be bypassed)

| Check            | Trigger                                         | Action            |
| ---------------- | ----------------------------------------------- | ----------------- |
| Manual ASCII art | Box-drawing chars in `.md` without source block | Exit code 2 block |

### Soft Blocks (PreToolUse - User can override)

| Check             | Trigger                              | Action                              |
| ----------------- | ------------------------------------ | ----------------------------------- |
| Polars preference | Write/Edit with Pandas in `.py`      | Dialog asking to use Polars instead |
| Fake data guard   | Write with test/fake data            | Block with explanation              |
| Hoisted deps      | pyproject.toml outside git root      | Block non-root pyproject.toml       |
| GPU optimization  | PyTorch training without AMP/compile | Block with optimization guidance    |

### Non-blocking Reminders (PostToolUse)

| Check                 | Trigger                        | Reminder                              |
| --------------------- | ------------------------------ | ------------------------------------- |
| **Ruff linting**      | Edit/Write `.py` files         | Shows lint errors (9 rule categories) |
| UV preference         | pip install in Bash            | Prefer `uv pip install`               |
| Polars preference     | Pandas usage (backup check)    | Prefer Polars for dataframes          |
| Graph-easy skill      | Direct `graph-easy` CLI usage  | Prefer skill for reproducibility      |
| ADR→Spec sync         | Modify `docs/adr/*.md`         | Check if Design Spec needs updating   |
| Spec→ADR sync         | Modify `docs/design/*/spec.md` | Check if ADR needs updating           |
| Code→ADR traceability | Modify implementation files    | Consider ADR reference                |

### Code Correctness Guard (PostToolUse)

Detects code correctness issues that cause runtime failures:

| Category              | Language  | Tool       | Rules Checked                                                        |
| --------------------- | --------- | ---------- | -------------------------------------------------------------------- |
| Silent failures       | Python    | Ruff       | E722 (bare except), S110/S112 (pass/continue), BLE001 (blind except) |
| Silent failures       | Shell     | ShellCheck | SC2155 (masked return), SC2164 (cd fail), SC2310/SC2312 (set -e)     |
| Silent failures       | JS/TS     | Oxlint     | no-empty, no-floating-promises, require-await                        |
| Silent failures       | Bash tool | Exit code  | Non-zero exit with stderr                                            |
| Cross-language syntax | Python    | grep       | Shell variables in Python strings (`Path("$HOME/...")`)              |

Uses `"decision": "block"` JSON format for Claude visibility (per ADR 2025-12-17) while remaining non-blocking (exit 0).

## Requirements

- `jq` - JSON processor (standard on most systems)
- `ruff` - Python linter (optional, for Python silent failure detection)
- `shellcheck` - Shell linter (optional, for shell silent failure detection)
- `oxlint` - JS/TS linter (optional, for JavaScript/TypeScript silent failure detection)
- Claude Code 1.0.0+

## How It Works

### Exit Code 2 vs Permission Decisions

| Approach                   | Bypass-able? | Use Case         |
| -------------------------- | ------------ | ---------------- |
| `permissionDecision: deny` | Yes          | Soft warnings    |
| `exit 2` + stderr          | **No**       | Hard enforcement |

This plugin uses **exit code 2** for ASCII art blocking because:

- Runs before permission system
- Cannot be bypassed even with `dangerously-skip-permissions`
- No legitimate reason to add manual diagrams without source

### Why PostToolUse for Graph-easy?

- Users may legitimately need direct CLI for testing
- Transcript-based skill detection had false positives
- Reminders work regardless of bypass permissions

## GPU Optimization Guard

The GPU optimization guard hook enforces **mandatory** GPU optimization best practices for PyTorch training scripts:

| Requirement          | Trigger                    | Severity | Why Required                         |
| -------------------- | -------------------------- | -------- | ------------------------------------ |
| AMP                  | GPU + backward() + step()  | ERROR    | ~2x speedup, 50% memory reduction    |
| Batch size auto-tune | Hardcoded batch_size < 64  | ERROR    | Parameter-free finds optimal for GPU |
| torch.compile        | GPU model without compile  | WARN     | 30-50% speedup on PyTorch 2.0+       |
| DataLoader tuning    | Missing num_workers/pin    | WARN     | Prevent I/O bottlenecks              |
| cudnn.benchmark      | CNN without benchmark=True | INFO     | 10-20% speedup for conv-heavy models |

**Philosophy**: Parameter-free optimization over magic numbers. Instead of `batch_size >= 64`, we require automatic batch size finders (Lightning `scale_batch_size`, Accelerate `find_executable_batch_size`).

**Bypass**: Add `# gpu-optimization-bypass: <reason>` comment.

**Context**: Lessons from exp068 disaster - batch_size=32 on RTX 4090 = 61 hours; auto-tuned = 8 hours.

## Files

- `commands/setup.md` - Setup command for dependency installation
- `commands/hooks.md` - Hook management command
- `hooks/hooks.json` - Hook configuration
- `hooks/pretooluse-guard.sh` - ASCII art blocking
- `hooks/pretooluse-polars-preference.ts` - Polars over Pandas dialog
- `hooks/pretooluse-gpu-optimization-guard.ts` - GPU optimization enforcement
- `hooks/posttooluse-reminder.ts` - Sync reminders + UV/Polars preference
- `hooks/code-correctness-guard.sh` - Code correctness detection (silent failures + cross-language syntax)
- `hooks/ruff.toml` - Ruff rule documentation
- `scripts/install-dependencies.sh` - Linter dependency installer
- `scripts/manage-hooks.sh` - Settings.json hook manager
- `README.md`
- `LICENSE`

## Polars Preference

The Polars preference hook enforces Polars over Pandas for dataframe operations:

- **PreToolUse** (`pretooluse-polars-preference.ts`): Shows dialog before writing Pandas code
- **PostToolUse** (`posttooluse-reminder.ts`): Backup reminder if PreToolUse bypassed

**Exception**: Add at file top to allow Pandas:

```python
# polars-exception: MLflow requires Pandas DataFrames
import pandas as pd
```

**Auto-skip paths**: `mlflow-python`, `legacy/`, `third-party/`

See [ADR](/docs/adr/2026-01-22-polars-preference-hook.md) for details.

## License

MIT
