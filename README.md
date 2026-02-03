# cc-skills

Claude Code Skills Marketplace: Meta-skills and foundational tools for Claude Code CLI.

[![Plugins](https://img.shields.io/badge/plugins-20-green.svg)](#plugins)
[![License](https://img.shields.io/badge/license-MIT-yellow.svg)](./LICENSE)

## Plugins

| Plugin                                                  | Description                                                                                             | Category     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------ |
| [plugin-dev](./plugins/plugin-dev/)                     | Plugin development: skill architecture, validation, silent failure auditing, TodoWrite templates        | development  |
| [itp](./plugins/itp/)                                   | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release | productivity |
| [gh-tools](./plugins/gh-tools/)                         | GitHub workflow automation with intelligent GFM link validation for PRs                                 | development  |
| [link-tools](./plugins/link-tools/)                     | Comprehensive link validation: portability checks, lychee broken link detection, path policy linting    | quality      |
| [devops-tools](./plugins/devops-tools/)                 | Doppler credentials, Firecrawl self-hosted, ML pipelines, Telegram bot, MLflow, session recovery        | devops       |
| [dotfiles-tools](./plugins/dotfiles-tools/)             | Chezmoi dotfile management via natural language workflows                                               | utilities    |
| [doc-tools](./plugins/doc-tools/)                       | Comprehensive documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF                | documents    |
| [quality-tools](./plugins/quality-tools/)               | Code clone detection, multi-agent E2E validation, performance profiling, schema testing                 | quality      |
| [productivity-tools](./plugins/productivity-tools/)     | Slash command generation for Claude Code                                                                | productivity |
| [mql5](./plugins/mql5/)                                 | MQL5 development: indicator patterns, mql5.com article extraction, Python workspace                     | trading      |
| [itp-hooks](./plugins/itp-hooks/)                       | ITP workflow enforcement: ASCII art blocking, graph-easy reminders, Ruff linting                        | enforcement  |
| [alpha-forge-worktree](./plugins/alpha-forge-worktree/) | Git worktree management for alpha-forge with ADR-style naming and dynamic iTerm2 tab detection          | development  |
| [ru](./plugins/ru/)                                     | Autonomous AI orchestration with Ralph Wiggum technique - keeps AI in loop until task complete          | automation   |
| [iterm2-layout-config](./plugins/iterm2-layout-config/) | iTerm2 workspace layout configuration with TOML-based separation of private paths from publishable code | development  |
| [statusline-tools](./plugins/statusline-tools/)         | Custom status line with git status, link validation (L), and path linting (P) indicators                | utilities    |
| [notion-api](./plugins/notion-api/)                     | Notion API integration using notion-client Python SDK with preflight credential prompting               | productivity |
| [asciinema-tools](./plugins/asciinema-tools/)           | Terminal recording automation: asciinema capture, launchd daemon, Keychain PAT storage                  | utilities    |
| [git-town-workflow](./plugins/git-town-workflow/)       | Prescriptive git-town workflow enforcement for fork-based development                                   | devops       |
| [quant-research](./plugins/quant-research/)             | Quantitative research: SOTA range bar metrics, Sharpe ratios, ML prediction quality, WFO epochs         | trading      |

## Installation

### Prerequisites

| Requirement     | Check              | Install                                                                                 |
| --------------- | ------------------ | --------------------------------------------------------------------------------------- |
| Claude Code CLI | `claude --version` | [Getting Started Guide](https://docs.anthropic.com/en/docs/claude-code/getting-started) |

### Quick Start (Recommended)

Run these commands in your **terminal** (not inside Claude Code):

```bash
# 1. Add the cc-skills marketplace
claude plugin marketplace add terrylica/cc-skills

# 2. Install all plugins (one-liner)
for p in itp plugin-dev gh-tools link-tools devops-tools dotfiles-tools doc-tools quality-tools productivity-tools mql5 itp-hooks alpha-forge-worktree ru iterm2-layout-config statusline-tools notion-api asciinema-tools git-town-workflow quant-research gmail-tools; do claude plugin install "$p@cc-skills"; done

# 3. Sync hooks to settings.json (requires cloning the repo)
git clone https://github.com/terrylica/cc-skills.git /tmp/cc-skills
/tmp/cc-skills/scripts/sync-hooks-to-settings.sh

# 4. Restart Claude Code to activate hooks
claude
```

### Step-by-Step Installation

#### Step 1: Add the Marketplace

```bash
claude plugin marketplace add terrylica/cc-skills
```

This clones the marketplace to `~/.claude/plugins/marketplaces/cc-skills/`.

**Verify installation:**

```bash
claude plugin marketplace list
# Should show: cc-skills - Source: GitHub (terrylica/cc-skills)
```

#### Step 2: Install Individual Plugins

```bash
# Install core plugins
claude plugin install itp@cc-skills
claude plugin install plugin-dev@cc-skills
claude plugin install gh-tools@cc-skills

# Install all remaining plugins
claude plugin install link-tools@cc-skills
claude plugin install devops-tools@cc-skills
claude plugin install dotfiles-tools@cc-skills
claude plugin install doc-tools@cc-skills
claude plugin install quality-tools@cc-skills
claude plugin install productivity-tools@cc-skills
claude plugin install mql5@cc-skills
claude plugin install itp-hooks@cc-skills
claude plugin install alpha-forge-worktree@cc-skills
claude plugin install ru@cc-skills
claude plugin install iterm2-layout-config@cc-skills
claude plugin install statusline-tools@cc-skills
claude plugin install notion-api@cc-skills
claude plugin install asciinema-tools@cc-skills
claude plugin install git-town-workflow@cc-skills
claude plugin install quant-research@cc-skills
```

#### Step 3: Sync Hooks

Hooks provide pre/post tool use enforcement and session events. They must be explicitly synced to `~/.claude/settings.json`:

```bash
# Clone the repository (if not already cloned)
git clone https://github.com/terrylica/cc-skills.git ~/cc-skills-temp

# Run the hook sync script
~/cc-skills-temp/scripts/sync-hooks-to-settings.sh
# Output: ✓ Hooks synced: PreToolUse=7, PostToolUse=3, Stop=5
```

#### Step 4: Restart Claude Code

**Hooks require a restart** to take effect:

```bash
# Exit any running Claude Code sessions, then:
claude
```

### Verify Installation

```bash
# Check marketplace is registered
claude plugin marketplace list

# Inside Claude Code, verify commands are available
# Type "/" and look for itp:go, plugin-dev:create, etc.
```

## Updating the Marketplace

When new versions are released:

```bash
# Update the marketplace repository
cd ~/.claude/plugins/marketplaces/cc-skills
git pull

# Reinstall updated plugins (or specific ones)
claude plugin install itp@cc-skills

# Re-sync hooks
./scripts/sync-hooks-to-settings.sh  # From the repo directory
```

## Troubleshooting

### "Source path does not exist" Error

**Cause**: Marketplace repository is out of sync or has stale data.

**Fix**:

```bash
# Update the marketplace
cd ~/.claude/plugins/marketplaces/cc-skills
git pull

# Retry installation
claude plugin install plugin-name@cc-skills
```

### Slash Commands Not Appearing

**Cause**: Plugins installed but commands not discovered.

**Fix**:

1. Verify plugin is installed:

   ```bash
   # Check installed_plugins.json
   cat ~/.claude/plugins/installed_plugins.json | grep "cc-skills"
   ```

2. Restart Claude Code (fresh session required)

3. If still not working, clear cache and reinstall:

   ```bash
   rm -rf ~/.claude/plugins/cache/cc-skills
   claude plugin install plugin-name@cc-skills
   ```

### Hooks Not Working

**Cause**: Hooks not synced to settings.json.

**Fix**:

```bash
# Sync hooks
cd /path/to/cc-skills
./scripts/sync-hooks-to-settings.sh

# Restart Claude Code
```

**Verify hooks are registered:**

```bash
cat ~/.claude/settings.json | jq '.hooks | keys'
# Should show: ["PreToolUse", "PostToolUse", "Stop"]
```

### "Plugin not found" After Adding Marketplace

**Cause**: Known Claude Code issue with SSH clone failures.

**Fix**:

```bash
# Remove and re-add with explicit clone
claude plugin marketplace remove cc-skills
rm -rf ~/.claude/plugins/marketplaces/cc-skills

# Clone manually via HTTPS
git clone https://github.com/terrylica/cc-skills.git ~/.claude/plugins/marketplaces/cc-skills

# Re-add to known_marketplaces.json
# Add this entry to ~/.claude/plugins/known_marketplaces.json:
# "cc-skills": {
#   "source": {"source": "github", "repo": "terrylica/cc-skills"},
#   "installLocation": "$HOME/.claude/plugins/marketplaces/cc-skills",
#   "lastUpdated": "2026-01-13T00:00:00.000Z"
# }
```

### Version Mismatch

**Cause**: Cache has old plugin version.

**Fix**:

```bash
# Check current cached version
ls ~/.claude/plugins/cache/cc-skills/itp/

# Clear specific plugin cache
rm -rf ~/.claude/plugins/cache/cc-skills/itp

# Reinstall
claude plugin install itp@cc-skills
```

## Architecture

### Directory Structure

```
~/.claude/plugins/
├── known_marketplaces.json      # Registered marketplaces
├── installed_plugins.json       # Installed plugins with versions
├── marketplaces/
│   └── cc-skills/               # Cloned marketplace repository
│       ├── .claude-plugin/
│       │   └── marketplace.json # Plugin registry (SSoT)
│       └── plugins/
│           ├── itp/
│           ├── plugin-dev/
│           └── ...
└── cache/
    └── cc-skills/               # Cached plugin copies
        ├── itp/
        │   └── <version>/       # Version-specific cache
        └── ...
```

### Key Files

| File                                        | Purpose                                                |
| ------------------------------------------- | ------------------------------------------------------ |
| `~/.claude/plugins/known_marketplaces.json` | Marketplace registry with source and install locations |
| `~/.claude/plugins/installed_plugins.json`  | Installed plugins with versions and paths              |
| `~/.claude/settings.json`                   | User settings including hooks configuration            |
| `.claude-plugin/marketplace.json`           | Plugin registry for this marketplace (SSoT)            |

### Marketplace Configuration

The `known_marketplaces.json` entry for cc-skills:

```json
{
  "cc-skills": {
    "source": {
      "source": "github",
      "repo": "terrylica/cc-skills"
    },
    "installLocation": "$HOME/.claude/plugins/marketplaces/cc-skills",
    "lastUpdated": "<timestamp>"
  }
}
```

## For Plugin Developers

### Critical Schema Requirements

Based on compatibility with Claude Code's plugin loader:

#### 1. Source Paths (marketplace.json)

**DO NOT** use trailing slashes in `source` paths:

```json
// CORRECT
"source": "./plugins/itp"

// WRONG - causes "Source path does not exist" error
"source": "./plugins/itp/"
```

#### 2. Author Field (plugin.json)

The `author` field **must** be an object, not a string:

```json
// CORRECT
"author": {
  "name": "Your Name",
  "url": "https://github.com/username"
}

// WRONG - causes validation error
"author": "Your Name"
```

#### 3. No Custom Fields (plugin.json)

Only standard fields are allowed. These cause validation errors:

```json
// WRONG - unrecognized keys
"commands_dir": "commands",
"references_dir": "references",
"scripts_dir": "scripts"
```

### Valid plugin.json Example

```json
{
  "name": "my-plugin",
  "version": "<version>",
  "description": "Plugin description (min 10 chars)",
  "keywords": ["keyword1", "keyword2"],
  "author": {
    "name": "Your Name",
    "url": "https://github.com/username"
  }
}
```

### Valid marketplace.json Entry

```json
{
  "name": "my-plugin",
  "description": "Plugin description",
  "version": "<version>",
  "source": "./plugins/my-plugin",
  "category": "development",
  "author": {
    "name": "Your Name",
    "url": "https://github.com/username"
  },
  "keywords": ["keyword1", "keyword2"],
  "strict": false
}
```

### Testing Your Plugin

```bash
# Validate marketplace structure
bun scripts/validate-plugins.mjs

# Check for schema errors
bun scripts/validate-plugins.mjs --fix
```

## Terminology

Understanding the architectural hierarchy:

| Term          | Definition                                                                                    | Location             | Example                          |
| ------------- | --------------------------------------------------------------------------------------------- | -------------------- | -------------------------------- |
| **Plugin**    | Marketplace-installable container with metadata, commands, and optional bundled skills        | `~/.claude/plugins/` | `itp`, `gh-tools`                |
| **Skill**     | Executable agent with SKILL.md frontmatter; can be standalone or bundled within a plugin      | `~/.claude/skills/`  | `semantic-release`, `graph-easy` |
| **Command**   | Slash command (`/plugin:command`) defined in `.md` file within plugin's `commands/` directory | Plugin's `commands/` | `/itp:setup`                     |
| **Reference** | Supporting documentation in `references/` directory; not directly executable                  | `references/`        | `error-handling.md`              |

**Hierarchy**:

```
Plugin (Container)
├── commands/           → Slash commands (/plugin:command)
├── skills/             → Bundled skills (copied to ~/.claude/skills/ on install)
│   └── skill-name/
│       ├── SKILL.md    → Skill definition (frontmatter + instructions)
│       ├── scripts/    → Executable helpers
│       └── references/ → Supporting docs
├── hooks/              → Hook definitions (hooks.json)
├── scripts/            → Plugin-level utilities
└── references/         → Plugin-level documentation
```

**Key distinctions**:

- **install** → Acquire packages/tools via package manager (`brew install`, `npm install`)
- **setup** → Verify environment post-installation (`/itp:setup` checks dependencies)
- **init** → Create initial directory structure (one-time scaffolding)
- **configure** → Adjust settings in config files (iterative customization)

## Plugin Dependencies

Some plugins use skills from other plugins. Install dependencies first for full functionality.

| Plugin       | Depends On  | Skills Used                                                     |
| ------------ | ----------- | --------------------------------------------------------------- |
| `plugin-dev` | `itp`       | implement-plan-preflight, code-hardcode-audit, semantic-release |
| `doc-tools`  | `itp`       | graph-easy, adr-graph-easy-architect                            |
| `itp`        | `doc-tools` | ascii-diagram-validator                                         |

**Note:** `doc-tools` and `itp` have a circular dependency (both provide diagram tools). Install both for full functionality.

Run `bun scripts/validate-plugins.mjs --deps` to see the full dependency graph.

## Slash Command Naming Convention

Marketplace plugin commands display with the `plugin:command` format:

| Display Format | Meaning                       |
| -------------- | ----------------------------- |
| `/itp:go`      | Plugin `itp`, command `go`    |
| `/itp:setup`   | Plugin `itp`, command `setup` |

**Why the colon format?**

- **Display**: Claude Code always shows the full `plugin:command` namespace in autocomplete and command lists
- **Invocation**: You may type `/go`, `/setup`, or `/hooks` directly if no naming conflicts exist with other installed plugins
- **Clarity**: The namespace identifies which plugin provides each command

**Important edge case**: When the command name equals the plugin name (e.g., `/foo:foo`), you **must** use the full format. Typing `/foo` alone is interpreted as the plugin prefix, not the command.

## Repository Structure

```text
cc-skills/
├── .claude-plugin/
│   ├── plugin.json          # Marketplace metadata
│   └── marketplace.json     # Plugin registry (20 plugins) - SSoT
├── plugins/
│   ├── itp/                       # ADR-driven development workflow (11 bundled skills)
│   ├── plugin-dev/                # Plugin development + skill architecture
│   ├── gh-tools/                  # GitHub workflow automation
│   ├── link-tools/                # Comprehensive link validation
│   ├── devops-tools/              # Doppler, secrets, MLflow, Telegram, recovery
│   ├── dotfiles-tools/            # Chezmoi dotfile management
│   ├── doc-tools/                 # ASCII diagrams, standards, LaTeX, Pandoc PDF
│   ├── quality-tools/             # Code clones, E2E validation, profiling, schema
│   ├── productivity-tools/        # Slash command generation
│   ├── mql5/                      # MQL5 development (indicators + mql5.com)
│   ├── itp-hooks/                 # ITP workflow enforcement hooks
│   ├── alpha-forge-worktree/      # Git worktree management
│   ├── ru/                        # Autonomous loop mode (Ralph Universe)
│   ├── iterm2-layout-config/      # iTerm2 workspace layout configuration
│   ├── statusline-tools/          # Custom status line with indicators
│   ├── notion-api/                # Notion API integration
│   ├── asciinema-tools/           # Terminal recording automation
│   ├── git-town-workflow/         # Prescriptive git-town workflow
│   └── quant-research/            # Quantitative research metrics
├── scripts/
│   ├── sync-hooks-to-settings.sh  # Hook synchronization
│   ├── validate-plugins.mjs       # Plugin validation
│   └── marketplace.schema.json    # JSON Schema for marketplace.json
├── .mise/tasks/                   # Release automation tasks
│   ├── release:full               # Complete 4-phase release
│   ├── release:sync               # Sync hooks and marketplace
│   └── ...
├── plugin.json                    # Root plugin config
├── package.json                   # Node.js + semantic-release
└── README.md
```

## Release Workflow (for maintainers)

This marketplace uses semantic-release with mise task automation:

```bash
# Check release status
mise run release:status

# Full release workflow (preflight → version → sync → verify)
mise run release:full

# Dry run (no changes)
mise run release:dry

# Manual hook sync only
mise run release:hooks

# Sync marketplace to ~/.claude after release
mise run release:sync
```

### Release Phases

| Phase | Task                | Description                                               |
| ----- | ------------------- | --------------------------------------------------------- |
| 1     | `release:preflight` | Validate prerequisites, check GitHub auth, verify plugins |
| 2     | `release:version`   | Run semantic-release (version bump + changelog)           |
| 3     | `release:sync`      | Update marketplace repo, sync hooks to settings.json      |
| 4     | `release:verify`    | Verify git tag, GitHub release, plugin cache              |

## Available Plugins

### itp

**Implement-The-Plan workflow: ADR-driven 4-phase development.**

Execute approved plans from Claude Code's Plan Mode through a structured workflow:

- **Preflight**: ADR + Design Spec creation with graph-easy diagrams
- **Phase 1**: Implementation with engineering standards
- **Phase 2**: Format & Push to GitHub
- **Phase 3**: Release (semantic-release) & Publish (PyPI)

**Commands**: `/itp:go`, `/itp:setup`, `/itp:release`, `/itp:hooks`

**Bundled Skills**: adr-code-traceability, adr-graph-easy-architect, bootstrap-monorepo, code-hardcode-audit, graph-easy, impl-standards, implement-plan-preflight, mise-configuration, mise-tasks, pypi-doppler, semantic-release

### plugin-dev

**Plugin and skill development: structure validation, silent failure auditing, skill architecture meta-skill.**

- **skill-architecture** - Meta-skill for creating skills (YAML frontmatter, TodoWrite templates)
- **plugin-validator** - Validate plugin structure, manifests, and detect silent script failures

**Commands**: `/plugin-dev:create`

### ru (Ralph Universe)

**Autonomous AI orchestration with Ralph Wiggum technique.**

Features:

- RSSI (Recursively Self-Improving Super Intelligence) loop mode
- Multi-signal task completion detection
- Validation exhaustion scoring
- Plan archive preservation
- Runtime limit configuration

**Commands**: `/ru:start`, `/ru:stop`, `/ru:status`, `/ru:config`, `/ru:hooks`

**Additional setup required**: See [plugins/ru/README.md](./plugins/ru/README.md)

### gh-tools

**GitHub workflow automation with intelligent GFM link validation.**

- Detects broken repository-relative links
- Auto-fixes common link patterns
- Integrates with `gh` CLI workflows

### link-tools

**Comprehensive link validation: portability checks, lychee broken link detection, path policy linting.**

- **link-validator** - Validates relative path usage for cross-installation compatibility
- **link-validation** - Lychee broken link detection with path policy linting

### devops-tools

**Doppler credentials, Firecrawl self-hosted, ML pipelines, Telegram bot management, MLflow queries, and session recovery.**

13 bundled skills: clickhouse-cloud-management, clickhouse-pydantic-config, doppler-workflows, doppler-secret-validation, dual-channel-watchexec, firecrawl-self-hosted, ml-data-pipeline-architecture, ml-failfast-validation, mlflow-python, python-logging-best-practices, session-chronicle, session-recovery, telegram-bot-management

### doc-tools

**Comprehensive documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF generation.**

Nine bundled skills: ascii-diagram-validator, documentation-standards, glossary-management, latex-build, latex-setup, latex-tables, pandoc-pdf-generation, plotext-financial-chart, terminal-print

### quality-tools

**Code quality and validation tools: clone detection, E2E validation, profiling, schema testing.**

Six bundled skills: clickhouse-architect, code-clone-assistant, multi-agent-e2e-validation, multi-agent-performance-profiling, schema-e2e-validation, symmetric-dogfooding

### itp-hooks

**ITP workflow enforcement via PreToolUse and PostToolUse hooks.**

- Hard block on manual ASCII art
- Ruff Python linting reminders
- Graph-easy skill reminders
- ADR/Design Spec sync reminders

### statusline-tools

**Custom Claude Code status line with git status, link validation, and path linting indicators.**

- Git status indicators (modified, deleted, staged, untracked)
- Remote tracking (ahead/behind commits)
- Link validation (broken links via lychee)
- Path linting (repository-relative path violations)

**Commands**: `/statusline-tools:setup`, `/statusline-tools:hooks`

### Other Plugins

See individual plugin READMEs for detailed documentation:

- [dotfiles-tools](./plugins/dotfiles-tools/) - Chezmoi dotfile management
- [productivity-tools](./plugins/productivity-tools/) - Slash command generation
- [mql5](./plugins/mql5/) - MQL5 development
- [alpha-forge-worktree](./plugins/alpha-forge-worktree/) - Git worktree management
- [iterm2-layout-config](./plugins/iterm2-layout-config/) - iTerm2 workspace configuration
- [notion-api](./plugins/notion-api/) - Notion API integration
- [asciinema-tools](./plugins/asciinema-tools/) - Terminal recording automation
- [git-town-workflow](./plugins/git-town-workflow/) - Prescriptive git-town workflow

## Known Issues

### Claude Code Plugin Ecosystem Issues

| Issue                                                            | Description                                                     | Workaround                          |
| ---------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------- |
| [#14929](https://github.com/anthropics/claude-code/issues/14929) | Commands from directory-based local marketplaces not discovered | Use GitHub-based marketplace source |
| SSH clone failures                                               | Silent failure when adding marketplace via SSH                  | Use HTTPS clone manually            |

### This Marketplace

| Issue                                | Status | Notes                               |
| ------------------------------------ | ------ | ----------------------------------- |
| Circular dependency: doc-tools ↔ itp | Known  | Install both for full functionality |

## Contributing

1. Fork the repository
2. Create a plugin in `plugins/your-plugin/`
3. Add entry to `.claude-plugin/marketplace.json`
4. Ensure `plugin.json` follows the schema (see [For Plugin Developers](#for-plugin-developers))
5. Run `bun scripts/validate-plugins.mjs`
6. Submit a pull request

## License

MIT
