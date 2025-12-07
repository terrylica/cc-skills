---
description: "SETUP COMMAND - Execute TodoWrite FIRST, then Check -> Gate -> Install -> Verify"
allowed-tools: Read, Bash(brew:*), Bash(npm:*), Bash(cpanm:*), Bash(uv:*), Bash(which:*), Bash(command -v:*), Bash(PLUGIN_DIR:*), Bash(source:*), AskUserQuestion, TodoWrite, TodoRead
---

<!--
ADR: 2025-12-05-itp-setup-todowrite-workflow
-->

# ITP Setup

Verify and install dependencies required by the `/itp` workflow using TodoWrite-driven interactive workflow.

---

## MANDATORY FIRST ACTION

**YOUR FIRST ACTION MUST BE TodoWrite with the template below.**

DO NOT:

- Run any checks before TodoWrite
- Skip the interactive gate
- Install without user confirmation

**Execute this TodoWrite template EXACTLY:**

```
TodoWrite with todos:
- "Setup: Detect platform (macOS/Linux)" | pending | "Detecting platform"
- "Setup: Check Core Tools (uv, gh, prettier)" | pending | "Checking Core Tools"
- "Setup: Check ADR Diagram Tools (cpanm, graph-easy)" | pending | "Checking ADR Tools"
- "Setup: Check Code Audit Tools (ruff, semgrep, jscpd)" | pending | "Checking Audit Tools"
- "Setup: Check Release Tools (node, semantic-release)" | pending | "Checking Release Tools"
- "Setup: Present findings and disclaimer" | pending | "Presenting findings"
- "Setup: GATE - Await user decision" | pending | "Awaiting user decision"
- "Setup: Install missing tools (if confirmed)" | pending | "Installing missing tools"
- "Setup: Verify installation" | pending | "Verifying installation"
```

**After TodoWrite completes, proceed to Phase 1 below.**

---

## Phase 1: Preflight Check

Mark each todo as `in_progress` before starting, `completed` when done.

### Todo 1: Detect Platform

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
source "$PLUGIN_DIR/scripts/install-dependencies.sh" --detect-only
```

Platform detection sets: `OS`, `PM` (package manager), `HAS_MISE`

### Todo 2: Check Core Tools

Check each tool using `command -v`:

| Tool     | Check                 | Required |
| -------- | --------------------- | -------- |
| uv       | `command -v uv`       | Yes      |
| gh       | `command -v gh`       | Yes      |
| prettier | `command -v prettier` | Yes      |

Record findings:

- Found: `[OK] uv (installed)` -> mark completed
- Missing: `[x] prettier (missing)` -> note for Phase 3

### Todo 3: Check ADR Diagram Tools

| Tool       | Check                             | Required     |
| ---------- | --------------------------------- | ------------ |
| cpanm      | `command -v cpanm`                | For diagrams |
| graph-easy | `echo "[A]" \| graph-easy` (test) | For diagrams |

### Todo 4: Check Code Audit Tools

| Tool    | Check                | Required       |
| ------- | -------------------- | -------------- |
| ruff    | `command -v ruff`    | For code-audit |
| semgrep | `command -v semgrep` | For code-audit |
| jscpd   | `command -v jscpd`   | For code-audit |

### Todo 5: Check Release Tools

| Tool             | Check                            | Required      |
| ---------------- | -------------------------------- | ------------- |
| node             | `command -v node`                | For release   |
| semantic-release | `npx semantic-release --version` | For release   |
| doppler          | `command -v doppler`             | For PyPI only |

---

## Phase 2: Present Findings (Interactive Gate)

### Todo 6: Present Findings

Display summary with this format:

```
=== SETUP PREFLIGHT COMPLETE ===

Found: X tools | Missing: Y tools

Your existing installations:
[OK] uv (0.4.9)
[OK] gh (2.40.0)
[x] prettier (missing)
[OK] cpanm (installed)
...

Note: This plugin is developed against latest tool versions.
Your existing installations are respected and will not be reinstalled.
If you encounter issues, report or consider upgrading.

Missing tools can be installed:
  prettier -> npm i -g prettier
  ruff -> uv tool install ruff
```

### Todo 7: GATE - Await User Decision

**If missing tools exist, STOP and ask user:**

Use AskUserQuestion with these options:

```
question: "Would you like to install the missing tools?"
header: "Install"
options:
  - label: "Install missing"
    description: "Automatically install all missing tools"
  - label: "Skip"
    description: "Show manual install commands and exit"
```

**IMPORTANT**: Do NOT proceed to Phase 3 until user responds.

**If ALL tools present**: Mark todo completed, skip to "All set!" message, mark todos 8-9 as N/A.

---

## Phase 3: Installation (Conditional)

### Todo 8: Install Missing Tools

**Only execute if**:

- User selected "Install missing"
- OR `--install` flag was passed (skip interactive gate)

Run installation commands for missing tools only:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --install
```

**If user selected "Skip"**:

- Display manual install commands
- Mark todo as skipped
- Exit cleanly

### Todo 9: Verify Installation

Re-run checks to confirm tools are now available:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --check
```

Mark todo completed only if verification passes.

---

## Flag Handling

| Flag        | Behavior                                    |
| ----------- | ------------------------------------------- |
| (none)      | Default: Check -> Gate -> Ask permission    |
| `--check`   | Same as default (hidden alias)              |
| `--install` | Check -> Skip gate -> Install automatically |
| `--yes`     | Alias for `--install`                       |

Parse `$ARGUMENTS` for flags:

```bash
case "$ARGUMENTS" in
  *--install*|*--yes*)
    SKIP_GATE=true
    ;;
  *)
    SKIP_GATE=false
    ;;
esac
```

---

## Edge Cases

| Case                              | Handling                                                          |
| --------------------------------- | ----------------------------------------------------------------- |
| All tools present                 | Todos 1-6 complete, Todo 7 shows "All set!", Todos 8-9 marked N/A |
| Some missing, user says "install" | Todos 8-9 execute normally                                        |
| Some missing, user says "skip"    | Show manual commands, mark todos 8-9 as skipped                   |
| `--install` flag passed           | Skip Todo 7 gate, proceed directly to install                     |
| macOS vs Linux                    | Todo 1 detects platform, install commands adapt                   |

---

## Troubleshooting

### graph-easy fails to install

```bash
# Ensure cpanminus is installed first
brew install cpanminus

# Then install Graph::Easy
cpanm Graph::Easy
```

### semantic-release not found

```bash
# Install globally with npm
npm i -g semantic-release@25

# Or use npx (no global install needed)
npx semantic-release --version
```

### Permission errors with npm

```bash
# Fix npm permissions
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Add to your shell config
SHELL_RC="$([[ "$SHELL" == */zsh ]] && echo ~/.zshrc || echo ~/.bashrc)"
echo 'export PATH=~/.npm-global/bin:$PATH' >> "$SHELL_RC"
source "$SHELL_RC"
```

---

## Next Steps

After setup completes, configure itp-hooks for enhanced workflow guidance:

1. **Check hook status**:

   ```bash
   /itp:hooks status
   ```

2. **Install hooks** (if not already installed):

   ```bash
   /itp:hooks install
   ```

### What hooks provide

- **PreToolUse guard**: Blocks Unicode box-drawing diagrams without `<details>` source blocks
- **PostToolUse reminder**: Prompts ADR sync and graph-easy skill usage

**IMPORTANT:** Hooks require a Claude Code session restart after installation.
