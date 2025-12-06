# notification-tools

Dual-channel notification plugin for Claude Code with Telegram and Pushover integration for watchexec process monitoring.

## Skills

| Skill                      | Description                                                 |
| -------------------------- | ----------------------------------------------------------- |
| **dual-channel-watchexec** | Send notifications to Telegram + Pushover on process events |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install notification-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "set up watchexec notifications" → dual-channel-watchexec
- "send to Telegram and Pushover" → dual-channel-watchexec
- "monitor process restarts" → dual-channel-watchexec
- "configure file change alerts" → dual-channel-watchexec

## Key Features

- **Dual-Channel**: Simultaneous Telegram + Pushover delivery
- **HTML for Telegram**: Proper formatting without escaping hell
- **Plain Text for Pushover**: Automatic HTML stripping
- **Restart Detection**: Startup, code change, crash differentiation
- **Message Archiving**: Pre-send archives for debugging

## Bundled Examples

- `examples/notify-restart.sh` - Complete dual-channel notification script
- `examples/bot-wrapper.sh` - watchexec wrapper with restart detection
- `examples/setup-example.sh` - Setup guide and installation steps

## Requirements

- watchexec (`brew install watchexec`)
- jq (`brew install jq`)
- Doppler CLI or environment variables for credentials

## License

MIT
