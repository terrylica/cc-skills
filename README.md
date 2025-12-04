# cc-skills

Claude Code Skills Marketplace: Meta-skills and foundational tools for Claude Code CLI.

## Plugins

| Plugin                                              | Description                                                                                                      | Category     |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------ |
| [skill-architecture](./plugins/skill-architecture/) | Meta-skill for creating Claude Code skills with TodoWrite templates, security practices, and structural patterns | development  |
| [itp-workflow](./plugins/itp-workflow/)             | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release          | productivity |

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
│   └── itp-workflow/        # ADR-driven development workflow
│       ├── commands/        # /itp, /itp-setup slash commands
│       ├── skills/          # 8 bundled skills
│       └── scripts/
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

### itp-workflow

**Implement-The-Plan workflow: ADR-driven 4-phase development.**

Execute approved plans from Claude Code's Plan Mode through a structured workflow:

- **Preflight**: ADR + Design Spec creation with graph-easy diagrams
- **Phase 1**: Implementation with engineering standards
- **Phase 2**: Format & Push to GitHub
- **Phase 3**: Release (semantic-release) & Publish (PyPI)

**Bundled Skills**: adr-code-traceability, adr-graph-easy-architect, code-hardcode-audit, graph-easy, impl-standards, implement-plan-preflight, pypi-doppler, semantic-release

**Triggers**: `/itp`, `/itp-setup`, ADR workflow, plan execution

## License

MIT
