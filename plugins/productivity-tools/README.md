# productivity-tools

Productivity and automation tools for Claude Code.

## Skills

### slash-command-factory

Generate custom Claude Code slash commands through a guided question flow.

**Triggers**: `create slash command`, `generate command`, `custom command`

**Features**:

- **10 Preset Commands**: Ready-to-use commands for common tasks
- **Custom Generation**: 5-7 questions to create tailored commands
- **3 Official Patterns**: Simple, Multi-Phase, and Agent-Style
- **Automatic Validation**: YAML frontmatter, argument format, tool permissions

**Preset Commands**:

| Command              | Purpose                                      |
| -------------------- | -------------------------------------------- |
| `/research-business` | Market research and competitive analysis     |
| `/research-content`  | Multi-platform content trend analysis        |
| `/medical-translate` | Medical terminology to patient-friendly text |
| `/compliance-audit`  | HIPAA/GDPR/DSGVO compliance validation       |
| `/api-build`         | Generate API client with error handling      |
| `/test-auto`         | Auto-generate comprehensive test suites      |
| `/docs-generate`     | Automated documentation from code            |
| `/knowledge-mine`    | Extract insights from documents              |
| `/workflow-analyze`  | Analyze and optimize business processes      |
| `/batch-agents`      | Launch coordinated multi-agent tasks         |

**Example Usage**:

```
# Use a preset
@slash-command-factory
Generate the /research-business preset command

# Create custom
@slash-command-factory
Create a command for analyzing customer feedback
```

**Output**: Complete command files in `generated-commands/[name]/`

## Installation

```bash
# Via Claude Code plugin system
claude plugin install productivity-tools@cc-skills
```

## Dependencies

| Component   | Required | Installation       |
| ----------- | -------- | ------------------ |
| Claude Code | Yes      | CLI tool           |
| Bun         | Optional | `brew install bun` |

## References

- [SKILL.md](skills/slash-command-factory/SKILL.md) - Full skill documentation
- [HOW_TO_USE.md](skills/slash-command-factory/HOW_TO_USE.md) - Usage guide
- [presets.json](skills/slash-command-factory/presets.json) - Preset definitions

## License

MIT
