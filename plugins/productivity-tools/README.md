# productivity-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-2-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

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

### calendar-event-manager

Create macOS Calendar events with tiered sound alarms and auto-paired Reminders.

**Triggers**: `add event`, `calendar event`, `create reminder`, `schedule event`, `RSVP`

**Features**:

- **6-Tier Sound Alarms**: Escalating sounds from gentle (Blow) to urgent (Funk)
- **Paired Reminders**: Auto-creates 3 Reminders (TOMORROW, TODAY, due-time) via hook
- **Sound Validation**: Blocks short sounds (< 1.4s) that get missed
- **PostToolUse Hook**: Validates alarm compliance and auto-creates Reminders

**Alarm Tiers**:

| Tier         | Trigger   | Sound  | Duration |
| ------------ | --------- | ------ | -------- |
| 1 day before | -1440 min | Blow   | 1.40s    |
| Morning-of   | 9 AM      | Sosumi | 1.54s    |
| 3 hours      | -180 min  | Pop    | 1.63s    |
| 1 hour       | -60 min   | Glass  | 1.65s    |
| 30 min       | -30 min   | Ping   | 1.50s    |
| At event     | 0 min     | Funk   | 2.16s    |

**Hook**: Install with `/productivity-tools:hooks install` (opt-in, not auto-enabled).

## Installation

```bash
# Via Claude Code plugin system
claude plugin install productivity-tools@cc-skills
```

## Dependencies

| Component       | Required             | Installation       |
| --------------- | -------------------- | ------------------ |
| Claude Code     | Yes                  | CLI tool           |
| Bun             | Yes (calendar hook)  | `brew install bun` |
| macOS Calendar  | Yes (calendar skill) | Built-in           |
| macOS Reminders | Yes (calendar skill) | Built-in           |

## References

- [SKILL.md](skills/slash-command-factory/SKILL.md) - Slash command factory documentation
- [HOW_TO_USE.md](skills/slash-command-factory/HOW_TO_USE.md) - Usage guide
- [presets.json](skills/slash-command-factory/presets.json) - Preset definitions
- [Calendar SKILL.md](skills/calendar-event-manager/SKILL.md) - Calendar event skill
- [Sound Reference](skills/calendar-event-manager/references/sound-reference.md) - Sound duration data

## Troubleshooting

| Issue                          | Cause                          | Solution                                              |
| ------------------------------ | ------------------------------ | ----------------------------------------------------- |
| Command not found after create | Output directory not in skills | Move generated files to `~/.claude/commands/`         |
| YAML frontmatter invalid       | Syntax error in generated file | Check for missing quotes or invalid characters        |
| Preset not loading             | presets.json not found         | Verify plugin installed correctly with `/plugin ls`   |
| Question flow interrupted      | Context lost mid-generation    | Restart with `/slash-command-factory` trigger         |
| Generated command too simple   | Wrong pattern selected         | Choose Multi-Phase or Agent-Style for complex needs   |
| Bun not available              | Optional dependency missing    | Install with `brew install bun` for TypeScript        |
| Validation warnings            | Missing required fields        | Add description and allowed-tools to YAML frontmatter |
| Sound alarm not playing        | Notifications disabled         | Enable in System Settings > Notifications > Calendar  |
| Reminders not created          | Hook not installed             | Run `/productivity-tools:hooks install`               |

## License

MIT
