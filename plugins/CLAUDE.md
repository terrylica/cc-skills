# Plugin Development Guide

Context for developing plugins in the cc-skills marketplace.

## Plugin Discovery (Critical)

**Single source of truth**: `.claude-plugin/marketplace.json`

Creating a plugin directory without registering it results in "Plugin not found" error.

**Prevention checklist**:

- [ ] Plugin dir exists in `plugins/`
- [ ] Entry added to `.claude-plugin/marketplace.json`
- [ ] `bun scripts/validate-plugins.mjs` passes
- [ ] Pre-commit hook validates

**Detailed Reference**: [Validation Reference](/plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md)

## Creating Plugins

```bash
# Recommended: Auto-registers in marketplace.json
/plugin-dev:create my-plugin

# Manual: Must add marketplace.json entry yourself
mkdir -p plugins/my-plugin/{skills,hooks,commands,scripts}
```

## Plugin Structure

```
plugins/my-plugin/
├── plugin.json           # Plugin manifest
├── README.md             # Plugin documentation
├── skills/               # Skill definitions
│   └── my-skill/
│       ├── SKILL.md      # Main skill content
│       └── references/   # Supporting docs
├── hooks/                # Hook scripts + hooks.json
├── commands/             # Slash commands (*.md)
└── scripts/              # Installation/management
```

## Link Conventions

| Link Target           | Format                  | Example                          |
| --------------------- | ----------------------- | -------------------------------- |
| Skill-internal files  | Relative (`./`, `../`)  | `[Guide](./references/guide.md)` |
| Repo docs (ADRs)      | Repo-root (`/docs/...`) | `[ADR](/docs/adr/file.md)`       |
| External resources    | Full URL                | `[Docs](https://example.com)`    |

**Why**: Skill files are installed to `~/.claude/skills/`. Relative paths work there; absolute paths don't.

## Shell Compatibility

Claude Code's Bash tool may run through zsh on macOS. Wrap bash-specific syntax:

```bash
# Multi-line bash scripts
/usr/bin/env bash << 'SCRIPT_EOF'
if [[ -f "$FILE" ]]; then
    echo "Found"
fi
SCRIPT_EOF

# Single-line commands
/usr/bin/env bash -c 'VAR=$(command) && echo $VAR'
```

**Reference**: [Shell Portability ADR](/docs/adr/2025-12-06-shell-command-portability-zsh.md)

## Validation

Run before committing:

```bash
bun scripts/validate-plugins.mjs           # Validate only
bun scripts/validate-plugins.mjs --fix     # Show fix instructions
bun scripts/validate-plugins.mjs --strict  # Fail on warnings
```

## Hooks in Plugins

If your plugin includes hooks, see [Hooks Development Guide](/docs/HOOKS.md).

## Core Plugins

| Plugin                  | Purpose                                  |
| ----------------------- | ---------------------------------------- |
| `itp`                   | Core 4-phase workflow                    |
| `itp-hooks`             | Workflow enforcement hooks               |
| `ralph`                 | Autonomous loop mode (RSSI)              |
| `plugin-dev`            | Plugin creation meta-skill               |
| `git-account-validator` | Multi-account GitHub isolation           |
| `gh-tools`              | GitHub CLI enforcement                   |

## Related Documentation

- [Plugin Authoring Guide](/docs/plugin-authoring.md)
- [ITP Plugin README](/plugins/itp/README.md)
- [Marketplace Installation Troubleshooting](/docs/troubleshooting/marketplace-installation.md)
