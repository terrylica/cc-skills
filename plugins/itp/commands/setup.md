---
description: Install and verify dependencies for itp plugin. Run before first use.
allowed-tools: Read, Bash(brew:*), Bash(npm:*), Bash(cpanm:*), Bash(uv:*), Bash(which:*), Bash(command -v:*), Bash(PLUGIN_DIR:*)
---

# ITP Setup

Verify and install all dependencies required by the `/itp` workflow.

## Quick Check

Run the bundled verification script:

```bash
# Environment-agnostic path (explicit fallback for marketplace installation)
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --check
```

Or auto-install missing tools:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --install
```

## Manual Dependency Verification

If the script fails, manually verify each tool:

### Core Tools (Required)

| Tool     | Check Command        | Install Command     |
| -------- | -------------------- | ------------------- |
| uv       | `uv --version`       | `brew install uv`   |
| gh       | `gh --version`       | `brew install gh`   |
| prettier | `prettier --version` | `npm i -g prettier` |

### ADR Diagrams (Required for Preflight)

| Tool       | Check Command                                | Install Command          |
| ---------- | -------------------------------------------- | ------------------------ |
| cpanm      | `cpanm --version`                            | `brew install cpanminus` |
| graph-easy | `echo "[A]" \| graph-easy` (--version hangs) | `cpanm Graph::Easy`      |

### Code Audit (Optional - for Phase 1)

| Tool    | Check Command       | Install Command        |
| ------- | ------------------- | ---------------------- |
| ruff    | `ruff --version`    | `uv tool install ruff` |
| semgrep | `semgrep --version` | `brew install semgrep` |
| jscpd   | `jscpd --version`   | `npm i -g jscpd`       |

### Release (Optional - for Phase 3)

| Tool             | Check Command                    | Install Command                |
| ---------------- | -------------------------------- | ------------------------------ |
| node             | `node --version`                 | `mise install node`            |
| semantic-release | `npx semantic-release --version` | `npm i -g semantic-release@25` |
| doppler          | `doppler --version`              | `brew install doppler`         |

## Execution Instructions

1. Run the `--check` command first to see what's missing
2. Install missing tools using the commands above
3. Re-run `--check` to verify all dependencies are installed
4. You're ready to use `/itp` workflow!

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

# Add to your shell config (detects zsh vs bash)
SHELL_RC="$([[ "$SHELL" == */zsh ]] && echo ~/.zshrc || echo ~/.bashrc)"
echo 'export PATH=~/.npm-global/bin:$PATH' >> "$SHELL_RC"
source "$SHELL_RC"
```
