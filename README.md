# cc-skills

Claude Code Skills Marketplace: Meta-skills and foundational tools for Claude Code CLI.

## Plugins

| Plugin                                                    | Description                                                                                               | Category     |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------ |
| [plugin-dev](./plugins/plugin-dev/)                       | Plugin development: skill architecture, validation, silent failure auditing, TodoWrite templates          | development  |
| [itp](./plugins/itp/)                                     | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release   | productivity |
| [gh-tools](./plugins/gh-tools/)                           | GitHub workflow automation with intelligent GFM link validation for PRs                                   | development  |
| [link-tools](./plugins/link-tools/)                       | Comprehensive link validation: portability checks, lychee broken link detection, path policy linting      | quality      |
| [devops-tools](./plugins/devops-tools/)                   | Doppler credentials, secret validation, Telegram bot management, MLflow queries, session recovery         | devops       |
| [dotfiles-tools](./plugins/dotfiles-tools/)               | Chezmoi dotfile management via natural language workflows                                                 | utilities    |
| [doc-tools](./plugins/doc-tools/)                         | Comprehensive documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF                  | documents    |
| [quality-tools](./plugins/quality-tools/)                 | Code clone detection, multi-agent E2E validation, performance profiling, schema testing                   | quality      |
| [productivity-tools](./plugins/productivity-tools/)       | Slash command generation for Claude Code                                                                  | productivity |
| [mql5](./plugins/mql5/)                                   | MQL5 development: indicator patterns, mql5.com article extraction, Python workspace                       | trading      |
| [itp-hooks](./plugins/itp-hooks/)                         | ITP workflow enforcement: ASCII art blocking, graph-easy reminders                                        | enforcement  |
| [alpha-forge-worktree](./plugins/alpha-forge-worktree/)   | Git worktree management for alpha-forge with ADR-style naming and dynamic iTerm2 tab detection            | development  |
| [git-account-validator](./plugins/git-account-validator/) | Pre-push validation for multi-account GitHub: blocks HTTPS URLs, validates SSH account matches git config | enforcement  |
| [ralph](./plugins/ralph/)                                 | Autonomous AI orchestration with Ralph Wiggum technique - keeps AI in loop until task complete            | automation   |
| [iterm2-layout-config](./plugins/iterm2-layout-config/)   | iTerm2 workspace layout configuration with TOML-based separation of private paths from publishable code   | development  |
| [statusline-tools](./plugins/statusline-tools/)           | Custom status line with git status, link validation (L), and path linting (P) indicators                  | utilities    |

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
├── scripts/            → Plugin-level utilities
└── references/         → Plugin-level documentation
```

**Key distinctions**:

- **install** → Acquire packages/tools via package manager (`brew install`, `npm install`)
- **setup** → Verify environment post-installation (`/itp:setup` checks dependencies)
- **init** → Create initial directory structure (one-time scaffolding)
- **configure** → Adjust settings in config files (iterative customization)

## Installation

### Via Claude Code Plugin Marketplace

```bash
# Add marketplace to settings
/plugin marketplace add terrylica/cc-skills

# Install specific plugin
/plugin install cc-skills@plugin-dev
```

### Manual Installation

```bash
# Clone repository
git clone git@github.com:terrylica/cc-skills.git /tmp/cc-skills

# Copy plugin to Claude Code skills directory
cp -r /tmp/cc-skills/plugins/plugin-dev ~/.claude/skills/
```

## Plugin Dependencies

Some plugins use skills from other plugins. Install dependencies first for full functionality.

| Plugin       | Depends On  | Skills Used                                                     |
| ------------ | ----------- | --------------------------------------------------------------- |
| `plugin-dev` | `itp`       | implement-plan-preflight, code-hardcode-audit, semantic-release |
| `doc-tools`  | `itp`       | graph-easy, adr-graph-easy-architect                            |
| `itp`        | `doc-tools` | ascii-diagram-validator                                         |

**Note:** `doc-tools` and `itp` have a circular dependency (both provide diagram tools). Install both for full functionality:

```bash
/plugin install cc-skills@itp
/plugin install cc-skills@doc-tools
```

Run `node scripts/validate-plugins.mjs --deps` to see the full dependency graph.

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

**Important edge case**: When the command name equals the plugin name (e.g., `/foo:foo`), you **must** use the full format. Typing `/foo` alone is interpreted as the plugin prefix, not the command. This applies whenever `command-name` = `plugin-name`.

## Repository Structure

```text
cc-skills/
├── .claude-plugin/
│   ├── plugin.json          # Marketplace metadata
│   └── marketplace.json     # Plugin registry (18 plugins)
├── plugins/
│   ├── plugin-dev/                # Plugin development + skill architecture
│   ├── itp/                    # ADR-driven development workflow (10 bundled skills)
│   ├── gh-tools/               # GitHub workflow automation
│   ├── link-tools/             # Comprehensive link validation (portability + lychee)
│   ├── devops-tools/           # Doppler credentials, secrets, MLflow, Telegram, recovery
│   ├── dotfiles-tools/         # Chezmoi dotfile management
│   ├── doc-tools/              # ASCII diagrams, standards, LaTeX, Pandoc PDF
│   ├── quality-tools/          # Code clones, E2E validation, profiling, schema
│   ├── productivity-tools/     # Slash command generation
│   ├── mql5/                   # MQL5 development (indicators + mql5.com)
│   ├── itp-hooks/              # ITP workflow enforcement hooks
│   ├── git-account-validator/  # Multi-account GitHub pre-push validation
│   ├── alpha-forge-worktree/   # Git worktree management for alpha-forge
│   ├── ralph/                  # Autonomous AI orchestration
│   ├── iterm2-layout-config/   # iTerm2 workspace layout configuration
│   └── statusline-tools/       # Custom status line with git/link indicators
├── plugin.json              # Root plugin config
├── package.json             # Node.js + semantic-release
└── README.md
```

## Available Plugins

### plugin-dev

**Plugin and skill development: structure validation, silent failure auditing, skill architecture meta-skill.**

Comprehensive tooling for Claude Code plugin development:

- **skill-architecture** - Meta-skill for creating skills (YAML frontmatter, TodoWrite templates, bundled resources)
- **validate-plugin-structure** - Verify plugin directory and manifest compliance
- **silent-failure-auditor** - Detect and fix silent script failures

**Triggers**: "create skill", "YAML frontmatter", "validate skill", "plugin structure", "silent failures"

### itp

**Implement-The-Plan workflow: ADR-driven 4-phase development.**

Execute approved plans from Claude Code's Plan Mode through a structured workflow:

- **Preflight**: ADR + Design Spec creation with graph-easy diagrams
- **Phase 1**: Implementation with engineering standards
- **Phase 2**: Format & Push to GitHub
- **Phase 3**: Release (semantic-release) & Publish (PyPI)

**Bundled Skills**: adr-code-traceability, adr-graph-easy-architect, code-hardcode-audit, graph-easy, impl-standards, implement-plan-preflight, mise-configuration, mise-tasks, pypi-doppler, semantic-release

**Triggers**: `/itp:go`, `/itp:setup`, ADR workflow, plan execution

### gh-tools

**GitHub workflow automation with intelligent GFM link validation.**

Validates and fixes GitHub Flavored Markdown links in PR descriptions:

- Detects broken repository-relative links
- Auto-fixes common link patterns
- Integrates with `gh` CLI workflows

**Triggers**: PR creation, GFM validation, link checking

### link-tools

**Comprehensive link validation: portability checks, lychee broken link detection, path policy linting.**

Two bundled skills:

- **link-validator** - Validates relative path usage for cross-installation compatibility
- **link-validation** - Lychee broken link detection with path policy linting at session end

Features:

- Detects absolute repo paths that break when installed elsewhere
- Suggests relative path fixes
- Lychee-powered broken link detection
- Path policy linting (absolute paths, excessive parent traversal)
- ULID correlation IDs for tracing

**Triggers**: link validation, broken links, lychee, portability check, relative paths

### devops-tools

**Doppler credentials, secret validation, Telegram bot management, MLflow queries, and session recovery.**

Seven bundled skills:

- **clickhouse-cloud-management** - ClickHouse Cloud user/permission management via SQL over HTTP
- **clickhouse-pydantic-config** - Generate DBeaver configurations from Pydantic ClickHouse connection models
- **doppler-workflows** - PyPI publishing, AWS credential rotation, multi-service patterns
- **doppler-secret-validation** - Add, validate, and test API tokens/credentials in Doppler
- **telegram-bot-management** - Production bot management, monitoring, restart, and troubleshooting
- **mlflow-query** - Query MLflow experiments, compare runs, analyze model metrics
- **session-recovery** - Troubleshoot Claude Code session issues and HOME variable problems

**Triggers**: "publish to PyPI", "add to Doppler", "telegram bot status", "MLflow experiments", "sessions not saving", "create ClickHouse user", "DBeaver config"

### dotfiles-tools

**Chezmoi dotfile management via natural language workflows.**

One bundled skill:

- **chezmoi-workflows** - Natural language workflows for tracking, syncing, and pushing dotfiles with SLO validation

**Triggers**: "track my .zshrc", "sync dotfiles", "push dotfile changes"

### doc-tools

**Comprehensive documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF generation.**

Six bundled skills:

- **ascii-diagram-validator** - Validate ASCII box-drawing diagram alignment in markdown files
- **documentation-standards** - LLM-optimized markdown documentation standards with section numbering
- **latex-build** - Build automation with latexmk and live preview
- **latex-setup** - macOS environment setup with MacTeX and Skim
- **latex-tables** - Modern table creation with tabularray package
- **pandoc-pdf-generation** - Markdown to PDF with XeLaTeX, section numbering, TOC, bibliography

**Triggers**: "validate ASCII diagrams", "documentation standards", "compile LaTeX", "set up LaTeX on Mac", "create LaTeX table", "generate PDF from markdown"

### quality-tools

**Code quality and validation tools: clone detection, E2E validation, profiling, schema testing.**

Five bundled skills:

- **clickhouse-architect** - ClickHouse schema design authority (ORDER BY, compression, partitioning)
- **code-clone-assistant** - Detect and refactor code duplication using PMD CPD
- **multi-agent-e2e-validation** - Multi-agent parallel E2E validation for database refactors
- **multi-agent-performance-profiling** - Parallel performance profiling for data pipeline bottlenecks
- **schema-e2e-validation** - Run Earthly E2E validation for schema-first data contracts

**Triggers**: "detect code clones", "validate E2E", "profile performance", "validate schema", "ClickHouse schema design"

### productivity-tools

**Slash command generation for Claude Code.**

One bundled skill:

- **slash-command-factory** - Generate custom Claude Code slash commands through intelligent question flow

**Triggers**: "create slash command", "generate command"

### mql5

**MQL5 development: indicator patterns, mql5.com article extraction, Python workspace, log reading.**

Four bundled skills:

- **mql5-indicator-patterns** - Buffer management, display scaling, recalculation, debugging
- **article-extractor** - Extract and organize MQL5 articles and documentation
- **python-workspace** - Configure Python workspace for MQL5 integration
- **log-reader** - Read MetaTrader 5 logs to validate indicator execution

**Triggers**: "create MQL5 indicator", "extract MQL5 article", "MT5 Python setup", "read MT5 logs"

### itp-hooks

**ITP workflow enforcement via PreToolUse and PostToolUse hooks.**

Features:

- Hard block on manual ASCII art (exit code 2)
- Ruff Python linting reminders
- Graph-easy skill reminders for reproducibility
- ADR/Design Spec sync reminders
- Code-to-ADR traceability hints

**Commands**: `/itp-hooks:hooks`

**Triggers**: "ITP hooks", "block ASCII art", "enforce workflow standards"

### git-account-validator

**Pre-push validation for multi-account GitHub authentication.**

Features:

- Blocks HTTPS URLs (enforces SSH for multi-account)
- Validates SSH authentication matches git config
- Port 443 fallback support for restrictive networks
- Prevents wrong-account pushes

**Commands**: `/git-account-validator:hooks`

**Triggers**: "multi-account GitHub", "prevent wrong account push", "SSH validation"

### alpha-forge-worktree

**Git worktree management for alpha-forge with ADR-style naming.**

Features:

- Natural language worktree creation
- Automatic slug derivation from descriptions
- Dynamic iTerm2 tab detection with acronym naming
- Three modes: new branch, remote tracking, existing branch
- Stale worktree cleanup

**Commands**: `/alpha-forge-worktree:create`, `/alpha-forge-worktree:list`, `/alpha-forge-worktree:remove`

**Triggers**: "create worktree", "alpha-forge worktree", "git worktree management"

### ralph

**Autonomous AI orchestration with Ralph Wiggum technique.**

Features:

- RSSI (Recursively Self-Improving Super Intelligence) loop mode
- Multi-signal task completion detection
- Validation exhaustion scoring
- Plan archive preservation
- Runtime limit configuration

**Commands**: `/ralph:start`, `/ralph:stop`, `/ralph:status`, `/ralph:config`, `/ralph:hooks`

**Triggers**: "autonomous mode", "keep working", "Ralph Wiggum", "loop until done"

### iterm2-layout-config

**iTerm2 workspace layout configuration with TOML-based configuration.**

Features:

- TOML-based workspace configuration
- Private data separation (paths in `~/.config/iterm2/layout.toml`)
- Publishable layout logic
- XDG Base Directory compliance

**Triggers**: "iTerm2 layout", "workspace configuration", "TOML workspace"

### statusline-tools

**Custom Claude Code status line with git status, link validation, and path linting indicators.**

Features:

- Git status indicators (modified, deleted, staged, untracked)
- Remote tracking (ahead/behind commits)
- Repository state (stash count, merge conflicts)
- Link validation (broken links via lychee)
- Path linting (repository-relative path violations)
- Clickable GitHub URL to current branch

**Commands**: `/statusline-tools:setup`, `/statusline-tools:hooks`

**Triggers**: "status line", "git indicators", "link validation in status", "broken links indicator"

## License

MIT
