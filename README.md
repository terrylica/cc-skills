# cc-skills

Claude Code Skills Marketplace: Meta-skills and foundational tools for Claude Code CLI.

## Plugins

| Plugin                                              | Description                                                                                                      | Category     |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------ |
| [skill-architecture](./plugins/skill-architecture/) | Meta-skill for creating Claude Code skills with TodoWrite templates, security practices, and structural patterns | development  |
| [itp](./plugins/itp/)                               | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release          | productivity |
| [gh-tools](./plugins/gh-tools/)                     | GitHub workflow automation with intelligent GFM link validation for PRs                                          | development  |
| [link-validator](./plugins/link-validator/)         | Validate markdown link portability in skills and plugins (relative paths for cross-installation compatibility)   | development  |
| [devops-tools](./plugins/devops-tools/)             | Doppler credentials, secret validation, Telegram bot management, MLflow queries, session recovery                | devops       |
| [dotfiles-tools](./plugins/dotfiles-tools/)         | Chezmoi dotfile management via natural language workflows                                                        | utilities    |
| [doc-build-tools](./plugins/doc-build-tools/)       | LaTeX compilation, Pandoc PDF generation, environment setup, and table generation                                | documents    |
| [doc-tools](./plugins/doc-tools/)                   | ASCII diagram validation and markdown documentation standards                                                    | documents    |
| [quality-tools](./plugins/quality-tools/)           | Code clone detection, multi-agent E2E validation, performance profiling, schema testing                          | quality      |
| [productivity-tools](./plugins/productivity-tools/) | Slash command generation and smart file organization                                                             | productivity |
| [mql5-tools](./plugins/mql5-tools/)                 | MQL5 indicator development patterns for MetaTrader 5                                                             | trading      |
| [notification-tools](./plugins/notification-tools/) | Dual-channel notifications (Telegram + Pushover) for watchexec process monitoring                                | utilities    |
| [python-tools](./plugins/python-tools/)             | Pydantic v2 API documentation patterns for Python packages                                                       | development  |

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
| `/itp:itp`     | Plugin `itp`, command `itp`   |
| `/itp:setup`   | Plugin `itp`, command `setup` |

**Why the colon format?**

- **Display**: Claude Code always shows the full `plugin:command` namespace in autocomplete and command lists
- **Invocation**: You may type `/itp` directly if no naming conflicts exist with other installed plugins
- **Clarity**: The namespace identifies which plugin provides each command

This is standard Claude Code behavior for marketplace plugins - the display format cannot be changed, but shorter invocation works when unambiguous.

## Repository Structure

```text
cc-skills/
├── .claude-plugin/
│   ├── plugin.json          # Marketplace metadata
│   └── marketplace.json     # Plugin registry (14 plugins)
├── plugins/
│   ├── skill-architecture/  # Meta-skill for creating skills
│   ├── itp/                 # ADR-driven development workflow (8 bundled skills)
│   ├── gh-tools/            # GitHub workflow automation
│   ├── link-validator/      # Markdown link portability validation
│   ├── devops-tools/        # Doppler credentials, secrets, MLflow, Telegram, recovery
│   ├── dotfiles-tools/      # Chezmoi dotfile management
│   ├── doc-build-tools/     # LaTeX + Pandoc PDF generation
│   ├── doc-tools/           # ASCII diagrams + documentation standards
│   ├── quality-tools/       # Code clones, E2E validation, profiling, schema
│   ├── productivity-tools/  # Slash commands + smart file placement
│   ├── mql5-tools/          # MQL5 indicator development
│   ├── notification-tools/  # Telegram + Pushover notifications
│   └── python-tools/        # Pydantic v2 API documentation
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

**Bundled Skills**: adr-code-traceability, adr-graph-easy-architect, code-hardcode-audit, graph-easy, impl-standards, implement-plan-preflight, pypi-doppler, semantic-release

**Triggers**: `/itp:itp`, `/itp:setup`, ADR workflow, plan execution

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

Five bundled skills:

- **doppler-workflows** - PyPI publishing, AWS credential rotation, multi-service patterns
- **doppler-secret-validation** - Add, validate, and test API tokens/credentials in Doppler
- **telegram-bot-management** - Production bot management, monitoring, restart, and troubleshooting
- **mlflow-query** - Query MLflow experiments, compare runs, analyze model metrics
- **session-recovery** - Troubleshoot Claude Code session issues and HOME variable problems

**Triggers**: "publish to PyPI", "add to Doppler", "telegram bot status", "MLflow experiments", "sessions not saving"

### dotfiles-tools

**Chezmoi dotfile management via natural language workflows.**

6 prompt patterns for tracking, syncing, and pushing dotfiles with SLO validation and secret detection.

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

Four bundled skills:

- **code-clone-assistant** - Detect and refactor code duplication using PMD CPD
- **multi-agent-e2e-validation** - Multi-agent parallel E2E validation for database refactors
- **multi-agent-performance-profiling** - Parallel performance profiling for data pipeline bottlenecks
- **schema-e2e-validation** - Run Earthly E2E validation for schema-first data contracts

**Triggers**: "detect code clones", "validate E2E", "profile performance", "validate schema"

### productivity-tools

**Productivity and automation tools: slash command generation and file organization.**

Two bundled skills:

- **slash-command-factory** - Generate custom Claude Code slash commands through intelligent question flow
- **smart-file-placement** - Organize files into hierarchical workspace directories automatically

**Triggers**: "create slash command", "generate command", "where should I put this file", "workspace organization"

### mql5-tools

**MQL5 indicator development patterns for MetaTrader 5.**

Battle-tested solutions for buffer management, display scaling, recalculation, and debugging patterns.

**Triggers**: "create MQL5 indicator", "blank indicator window", "OnCalculate() debugging"

### notification-tools

**Dual-channel notifications (Telegram + Pushover) for watchexec process monitoring.**

Features:

- Simultaneous Telegram + Pushover delivery
- HTML formatting for Telegram, plain text for Pushover
- Restart detection (startup, code change, crash)
- Message archiving for debugging

**Triggers**: "watchexec notifications", "send to Telegram and Pushover", "monitor process restarts"

### python-tools

**Pydantic v2 API documentation patterns for Python packages.**

3-layer architecture: Literal Types → Pydantic Models → Rich Docstrings.

Benefits: Single source of truth, AI agent discovery, IDE autocomplete, runtime validation.

**Triggers**: "document Python API", "create Pydantic models", "generate JSON schema"

## License

MIT
