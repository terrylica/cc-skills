---
description: "Check and install dependencies for itp-hooks silent failure detection"
allowed-tools: Read, Bash, TodoWrite, TodoRead, AskUserQuestion
argument-hint: "[--install|--check]"
---

# ITP Hooks Setup

Verify and install dependencies for the itp-hooks plugin:

- **jq** (required) - JSON processing for hook input/output
- **ruff** (optional) - Python silent failure detection
- **shellcheck** (optional) - Shell script analysis
- **oxlint** (optional) - JavaScript/TypeScript linting

## Quick Start

Run dependency check:

```bash
/usr/bin/env bash << 'SETUP_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --check
SETUP_EOF
```

## Interactive Setup Workflow

### Step 1: Check Dependencies

```bash
/usr/bin/env bash << 'CHECK_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --check
CHECK_EOF
```

### Step 2: Present Findings

After running the check, present the findings to the user:

| Tool       | Status | Purpose                       |
| ---------- | ------ | ----------------------------- |
| jq         | ?      | Required for hook I/O         |
| ruff       | ?      | Python silent failure rules   |
| shellcheck | ?      | Shell script analysis         |
| oxlint     | ?      | JavaScript/TypeScript linting |

### Step 3: User Decision (if missing tools)

If optional linters are missing, use AskUserQuestion:

```
question: "Install optional linters for full silent failure detection coverage?"
header: "Linters"
options:
  - label: "Install all"
    description: "Install ruff, shellcheck, and oxlint for Python, Shell, and JS/TS coverage"
  - label: "Skip"
    description: "Continue with graceful degradation (detection only for installed linters)"
```

### Step 4: Install (if confirmed)

```bash
/usr/bin/env bash << 'INSTALL_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --install
INSTALL_EOF
```

## Flags

| Flag        | Behavior                             |
| ----------- | ------------------------------------ |
| (none)      | Check dependencies, show status      |
| `--check`   | Same as default                      |
| `--install` | Check then install all missing tools |

## Graceful Degradation

The silent failure detector works with graceful degradation:

| Linter Missing | Effect                                 |
| -------------- | -------------------------------------- |
| ruff           | Python files skip silent failure check |
| shellcheck     | Shell scripts skip analysis            |
| oxlint         | JS/TS files skip linting               |
| jq             | Hook fails (required for JSON parsing) |

## Next Steps

After setup, install the hooks to your settings:

```bash
/itp-hooks:hooks install
```

**IMPORTANT**: Restart Claude Code session for hooks to take effect.
