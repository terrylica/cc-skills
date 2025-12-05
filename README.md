# cc-skills

Claude Code Skills Marketplace: Meta-skills and foundational tools for Claude Code CLI.

## Plugins

| Plugin                                              | Description                                                                                                      | Category     |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------ |
| [skill-architecture](./plugins/skill-architecture/) | Meta-skill for creating Claude Code skills with TodoWrite templates, security practices, and structural patterns | development  |
| [itp](./plugins/itp/)                               | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release          | productivity |
| [gh-tools](./plugins/gh-tools/)                     | GitHub workflow automation with intelligent GFM link validation for PRs                                          | development  |
| [link-validator](./plugins/link-validator/)         | Validate markdown link portability in skills and plugins (relative paths for cross-installation compatibility)   | development  |

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
│   └── marketplace.json     # Plugin registry
├── plugins/
│   ├── skill-architecture/  # Meta-skill for creating skills
│   │   ├── SKILL.md
│   │   ├── references/
│   │   └── scripts/
│   ├── itp/                 # ADR-driven development workflow
│   │   ├── commands/        # /itp:itp, /itp:setup slash commands
│   │   ├── skills/          # 8 bundled skills
│   │   └── scripts/
│   ├── gh-tools/            # GitHub workflow automation
│   │   └── skills/          # pr-gfm-validator
│   └── link-validator/      # Markdown link portability validation
│       ├── SKILL.md
│       ├── scripts/         # validate_links.py
│       └── references/
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

## License

MIT
