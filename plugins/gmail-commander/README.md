# Gmail Commander

Gmail + Telegram bot lifecycle plugin for Claude Code.

## Features

- **Interactive Telegram Bot**: 9 slash commands with inline keyboards
- **AI-Powered Free-Text**: Natural language email queries via Agent SDK (Haiku)
- **Scheduled Digest**: 3-category triage (System/Work/Personal) every 6 hours
- **Voice Briefing**: Podcast-style audio digest via Kokoro TTS
- **Gmail CLI**: Full email access (list, search, read, draft) via 1Password OAuth
- **Sender Alignment**: Auto-detect reply sender, confirm for new emails

## Quick Start

```bash
# Install plugin
claude plugin marketplace add terrylica/cc-skills

# Run setup wizard
# (In Claude Code): /setup
```

## System Resources

| Resource | Bot Daemon                  | Digest                    |
| -------- | --------------------------- | ------------------------- |
| Memory   | ~20-30 MB RSS               | ~40 MB (peak, Agent SDK)  |
| CPU      | Negligible (idle polling)   | Brief burst during triage |
| Network  | Single long-poll connection | Burst during email fetch  |
| Disk     | ~1 MB/day audit logs        | Same (shared audit dir)   |

## Skills

| Skill                 | Purpose                                  |
| --------------------- | ---------------------------------------- |
| `gmail-access`        | Gmail CLI access with 1Password OAuth    |
| `email-triage`        | Scheduled digest via Agent SDK           |
| `interactive-bot`     | Telegram bot slash commands + AI routing |
| `bot-process-control` | Daemon lifecycle management              |

## Commands

| Command   | Purpose                                        |
| --------- | ---------------------------------------------- |
| `/setup`  | Full setup wizard (OAuth + Telegram + launchd) |
| `/health` | 8-subsystem health check                       |

## License

Private plugin.
