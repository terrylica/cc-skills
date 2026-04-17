# productivity-tools Plugin

> Slash command factory and calendar event management with tiered sound alarms.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [doc-tools CLAUDE.md](../doc-tools/CLAUDE.md)

## Skills

- [calendar-event-manager](./skills/calendar-event-manager/SKILL.md)
- [gdrive-access](./skills/gdrive-access/SKILL.md)
- [hooks](./skills/hooks/SKILL.md)
- [imessage-query](./skills/imessage-query/SKILL.md)
- [iterm2-layout](./skills/iterm2-layout/SKILL.md)
- [notion-cli](./skills/notion-cli/SKILL.md)
- [notion-sdk](./skills/notion-sdk/SKILL.md)
- [slash-command-factory](./skills/slash-command-factory/SKILL.md)

## Hooks

| Hook                  | Event       | Matcher | Purpose                                            |
| --------------------- | ----------- | ------- | -------------------------------------------------- |
| `calendar-alarm-hook` | PostToolUse | Bash    | Validates alarm compliance, auto-creates Reminders |

## Conventions

- **6-Tier Sound Alarms**: Blow → Sosumi → Pop → Glass → Ping → Funk (escalating urgency)
- **gdrive-access**: Absorbed from former `gdrive-tools` plugin (1Password OAuth)
- **Hook opt-in**: `/productivity-tools:hooks install` (not auto-enabled)
