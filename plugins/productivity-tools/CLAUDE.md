# productivity-tools Plugin

> Slash command factory and calendar event management with tiered sound alarms.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [doc-tools CLAUDE.md](../doc-tools/CLAUDE.md)

## Skills

- [calendar-event-manager](./skills/calendar-event-manager/SKILL.md)
- [gdrive-access](./skills/gdrive-access/SKILL.md)
- [imessage-query](./skills/imessage-query/SKILL.md)
- [iterm2-layout](./skills/iterm2-layout/SKILL.md)
- [notion-cli](./skills/notion-cli/SKILL.md)
- [notion-sdk](./skills/notion-sdk/SKILL.md)
- [slash-command-factory](./skills/slash-command-factory/SKILL.md)
- [amazon-photos-album-download](./skills/amazon-photos-album-download/SKILL.md) — pull originals from a public Amazon Photos share link (Drive `/drive/v1/` API + Playwright)

## Hooks

| Hook                  | Event       | Matcher | Purpose                                            |
| --------------------- | ----------- | ------- | -------------------------------------------------- |
| `calendar-alarm-hook` | PostToolUse | Bash    | Validates alarm compliance, auto-creates Reminders |

## Conventions

- **6-Tier Sound Alarms**: Blow → Sosumi → Pop → Glass → Ping → Funk (escalating urgency)
- **gdrive-access**: Absorbed from former `gdrive-tools` plugin (1Password OAuth)
- **Hook is not opt-in**: `calendar-reminder-sync.ts` is registered in `hooks/hooks.json`, so it runs whenever the plugin is enabled. The `tether` skill and `scripts/manage-hooks.sh` that advertised an opt-in install were retired in issue #127 — their injection into `~/.claude/settings.json` duplicated the shipped registration.
