# cc-skills

Claude Code Skills Marketplace: Meta-skills and foundational tools for Claude Code CLI.

## Plugins

| Plugin                                                    | Description                                                                                                       | Category     |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------ |
| [skill-architecture](./plugins/skill-architecture/)       | Meta-skill for creating Claude Code skills with TodoWrite templates, security practices, and structural patterns  | development  |
| [itp](./plugins/itp/)                                     | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release           | productivity |
| [gh-tools](./plugins/gh-tools/)                           | GitHub workflow automation with intelligent GFM link validation for PRs                                           | development  |
| [link-validator](./plugins/link-validator/)               | Validate markdown link portability in skills and plugins (relative paths for cross-installation compatibility)    | development  |
| [devops-tools](./plugins/devops-tools/)                   | Doppler credentials, secret validation, Telegram bot management, MLflow queries, session recovery                 | devops       |
| [dotfiles-tools](./plugins/dotfiles-tools/)               | Chezmoi dotfile management via natural language workflows                                                         | utilities    |
| [doc-build-tools](./plugins/doc-build-tools/)             | LaTeX compilation, Pandoc PDF generation, environment setup, and table generation                                 | documents    |
| [doc-tools](./plugins/doc-tools/)                         | ASCII diagram validation and markdown documentation standards                                                     | documents    |
| [quality-tools](./plugins/quality-tools/)                 | Code clone detection, multi-agent E2E validation, performance profiling, schema testing                           | quality      |
| [productivity-tools](./plugins/productivity-tools/)       | Slash command generation for Claude Code                                                                          | productivity |
| [mql5-tools](./plugins/mql5-tools/)                       | MQL5 indicator development patterns for MetaTrader 5                                                              | trading      |
| [mql5com](./plugins/mql5com/)                             | MQL5.com operations: article extraction, Python workspace, log reading                                            | trading      |
| [notification-tools](./plugins/notification-tools/)       | Dual-channel notifications (Telegram + Pushover) for watchexec process monitoring                                 | utilities    |
| [itp-hooks](./plugins/itp-hooks/)                         | ITP workflow enforcement: ASCII art blocking, graph-easy reminders                                                | enforcement  |
| [alpha-forge-worktree](./plugins/alpha-forge-worktree/)   | Git worktree management for alpha-forge with ADR-style naming and dynamic iTerm2 tab detection                    | development  |
| [link-checker](./plugins/link-checker/)                   | Universal link validation at session end: lychee broken link detection, path policy linting, ULID correlation IDs | quality      |
| [git-account-validator](./plugins/git-account-validator/) | Pre-push validation for multi-account GitHub: blocks HTTPS URLs, validates SSH account matches git config         | enforcement  |
| [ralph](./plugins/ralph/)                                 | Autonomous AI orchestration with Ralph Wiggum technique - keeps AI in loop until task complete                    | automation   |
| [iterm2-layout-config](./plugins/iterm2-layout-config/)   | iTerm2 workspace layout configuration with TOML-based separation of private paths from publishable code           | development  |

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
/plugin install cc-skills@skill-architecture
```

### Manual Installation

```bash
# Clone repository
git clone git@github.com:terrylica/cc-skills.git /tmp/cc-skills

# Copy plugin to Claude Code skills directory
cp -r /tmp/cc-skills/plugins/skill-architecture ~/.claude/skills/
```

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
│   └── marketplace.json     # Plugin registry (19 plugins)
├── plugins/
│   ├── skill-architecture/  # Meta-skill for creating skills
│   ├── itp/                 # ADR-driven development workflow (10 bundled skills)
│   ├── gh-tools/            # GitHub workflow automation
│   ├── link-validator/      # Markdown link portability validation
│   ├── devops-tools/        # Doppler credentials, secrets, MLflow, Telegram, recovery
│   ├── dotfiles-tools/      # Chezmoi dotfile management
│   ├── doc-build-tools/     # LaTeX + Pandoc PDF generation
│   ├── doc-tools/           # ASCII diagrams + documentation standards
│   ├── quality-tools/       # Code clones, E2E validation, profiling, schema
│   ├── productivity-tools/  # Slash command generation
│   ├── mql5-tools/          # MQL5 indicator development
│   ├── mql5com/             # MQL5.com article extraction + Python workspace
│   └── notification-tools/  # Telegram + Pushover notifications
├── plugin.json              # Root plugin config
├── package.json             # Node.js + semantic-release
└── README.md
```

## Available Plugins

### skill-architecture

**Meta-skill for creating Claude Code skills.**

Comprehensive guide for creating effective Claude Code skills following Anthropic's official standards with emphasis on:

- Security practices and `allowed-tools` restrictions
- CLI-specific features
- Progressive disclosure architecture
- TodoWrite task templates
- Bundled resources (scripts/, references/, assets/)

**Triggers**: "create skill", "YAML frontmatter", "validate skill", "skill architecture"

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

### link-validator

**Validate markdown link portability for skills and plugins.**

Ensures markdown links use relative paths (`./`, `../`) for cross-installation compatibility:

- Detects absolute repo paths that break when installed elsewhere
- Suggests relative path fixes
- Zero dependencies (PEP 723 inline script)

**Triggers**: link validation, portability check, relative paths, before skill distribution

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

### doc-build-tools

**Document build automation: LaTeX compilation, Pandoc PDF generation, setup, and tables.**

Four bundled skills:

- **latex-build** - Build automation with latexmk and live preview
- **latex-setup** - macOS environment setup with MacTeX and Skim
- **latex-tables** - Modern table creation with tabularray package
- **pandoc-pdf-generation** - Markdown to PDF with XeLaTeX, section numbering, TOC, bibliography

**Triggers**: "compile LaTeX", "set up LaTeX on Mac", "create LaTeX table", "generate PDF from markdown"

### doc-tools

**Documentation quality tools: ASCII diagram validation and markdown standards.**

Two bundled skills:

- **ascii-diagram-validator** - Validate ASCII box-drawing diagram alignment in markdown files
- **documentation-standards** - LLM-optimized markdown documentation standards with section numbering

**Triggers**: "validate ASCII diagrams", "check diagram alignment", "documentation standards"

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

### mql5-tools

**MQL5 indicator development patterns for MetaTrader 5.**

Battle-tested solutions for buffer management, display scaling, recalculation, and debugging patterns.

**Triggers**: "create MQL5 indicator", "blank indicator window", "OnCalculate() debugging"

### mql5com

**MQL5.com operations: article extraction, Python workspace, and log reading.**

Three bundled skills:

- **article-extractor** - Extract and organize MQL5 articles and documentation
- **python-workspace** - Configure Python workspace for MQL5 integration
- **log-reader** - Read MetaTrader 5 logs to validate indicator execution

**Triggers**: "extract MQL5 article", "MT5 Python setup", "read MT5 logs"

### notification-tools

**Dual-channel notifications (Telegram + Pushover) for watchexec process monitoring.**

Features:

- Simultaneous Telegram + Pushover delivery
- HTML formatting for Telegram, plain text for Pushover
- Restart detection (startup, code change, crash)
- Message archiving for debugging

**Triggers**: "watchexec notifications", "send to Telegram and Pushover", "monitor process restarts"

## License

MIT
