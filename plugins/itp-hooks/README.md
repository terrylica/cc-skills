# ITP Hooks

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

### Non-blocking Reminders (PostToolUse)

| Check                 | Trigger                        | Reminder                              |
| --------------------- | ------------------------------ | ------------------------------------- |
| **Ruff linting**      | Edit/Write `.py` files         | Shows lint errors (9 rule categories) |
| Graph-easy skill      | Direct `graph-easy` CLI usage  | Prefer skill for reproducibility      |
| ADR→Spec sync         | Modify `docs/adr/*.md`         | Check if Design Spec needs updating   |
| Spec→ADR sync         | Modify `docs/design/*/spec.md` | Check if ADR needs updating           |
| Code→ADR traceability | Modify implementation files    | Consider ADR reference                |

### Silent Failure Detection (PostToolUse)

Detects silent failure patterns across multiple languages:

| Language  | Tool       | Rules Checked                                                        |
| --------- | ---------- | -------------------------------------------------------------------- |
| Python    | Ruff       | E722 (bare except), S110/S112 (pass/continue), BLE001 (blind except) |
| Shell     | ShellCheck | SC2155 (masked return), SC2164 (cd fail), SC2310/SC2312 (set -e)     |
| JS/TS     | Oxlint     | no-empty, no-floating-promises, require-await                        |
| Bash tool | Exit code  | Non-zero exit with stderr                                            |

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

## Files

- `commands/setup.md` - Setup command for dependency installation
- `commands/hooks.md` - Hook management command
- `hooks/hooks.json` - Hook configuration
- `hooks/pretooluse-guard.sh` - ASCII art blocking
- `hooks/posttooluse-reminder.sh` - Sync reminders + Ruff linting
- `hooks/silent-failure-detector.sh` - Multi-language silent failure detection
- `hooks/ruff.toml` - Ruff rule documentation
- `scripts/install-dependencies.sh` - Linter dependency installer
- `scripts/manage-hooks.sh` - Settings.json hook manager
- `README.md`
- `LICENSE`

## License

MIT
