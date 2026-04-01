# productivity-tools Plugin

> Slash command factory and calendar event management with tiered sound alarms.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [doc-tools CLAUDE.md](../doc-tools/CLAUDE.md)

## Skills

| Skill                    | Purpose                                                         |
| ------------------------ | --------------------------------------------------------------- |
| `slash-command-factory`  | Generate custom slash commands through guided flow (10 presets) |
| `calendar-event-manager` | Create macOS Calendar events with 6-tier sound alarms           |
| `notion-sdk`             | Notion API integration (Python SDK)                             |
| `notion-cli`             | Notion CLI access via 4ier/notion-cli Go binary                 |
| `imessage-query`         | iMessage database queries                                       |
| `gdrive-access`          | Google Drive API access (1Password OAuth)                       |
| `iterm2-layout`          | iTerm2 window/tab layout management                             |

## Hooks

| Hook                  | Event       | Matcher | Purpose                                            |
| --------------------- | ----------- | ------- | -------------------------------------------------- |
| `calendar-alarm-hook` | PostToolUse | Bash    | Validates alarm compliance, auto-creates Reminders |

## Conventions

- **6-Tier Sound Alarms**: Blow → Sosumi → Pop → Glass → Ping → Funk (escalating urgency)
- **gdrive-access**: Absorbed from former `gdrive-tools` plugin (1Password OAuth)
- **Hook opt-in**: `/productivity-tools:hooks install` (not auto-enabled)
