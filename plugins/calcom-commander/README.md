# Cal.com Commander

Cal.com + Telegram bot lifecycle plugin for Claude Code.

## Features

- **Interactive Telegram Bot**: Slash commands for booking management with inline keyboards
- **AI-Powered Free-Text**: Natural language booking queries via Agent SDK (Haiku)
- **Scheduled Sync**: Periodic booking sync with Telegram notifications
- **Cal.com CLI**: Full booking access (list, create, update, cancel) via 1Password API key
- **Self-Hosted Deploy**: Cloud Run + Docker Compose deployment prescriptions
- **Supabase PostgreSQL**: Free-tier database provisioning via Management API

## Quick Start

```bash
# Install plugin
claude plugin marketplace add terrylica/cc-skills

# Run setup wizard
# (In Claude Code): /setup
```

## System Resources

| Resource | Bot Daemon                  | Sync                       |
| -------- | --------------------------- | -------------------------- |
| Memory   | ~20-30 MB RSS               | ~40 MB (peak, Agent SDK)   |
| CPU      | Negligible (idle polling)   | Brief burst during sync    |
| Network  | Single long-poll connection | Burst during booking fetch |
| Disk     | ~1 MB/day audit logs        | Same (shared audit dir)    |

## Skills

| Skill            | Purpose                                     |
| ---------------- | ------------------------------------------- |
| `calcom-access`  | Cal.com CLI access with 1Password API key   |
| `booking-config` | Event types, schedules, availability config |
| `booking-notify` | Scheduled sync + Telegram notifications     |
| `infra-deploy`   | Cloud Run + Docker Compose deployment       |

## Commands

| Command   | Purpose                                                     |
| --------- | ----------------------------------------------------------- |
| `/setup`  | Full setup wizard (Cal.com API + Telegram + Supabase + GCP) |
| `/health` | Multi-subsystem health check                                |

## License

Private plugin.
