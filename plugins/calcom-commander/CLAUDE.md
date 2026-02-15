# Cal.com Commander Plugin

Cal.com + Telegram + Pushover lifecycle — booking management, interactive commands, scheduled sync, webhook relay, Agent SDK routing, 1Password OAuth.

## Architecture

Three notification paths sharing `scripts/lib/`:

| Path        | Entry                   | Trigger                  | Channel              | Purpose                             |
| ----------- | ----------------------- | ------------------------ | -------------------- | ----------------------------------- |
| Real-time   | `scripts/webhook-relay` | Cal.com webhook          | Pushover (emergency) | Instant booking alerts (dune sound) |
| Scheduled   | `scripts/sync.ts`       | launchd StartInterval 6h | Telegram + Pushover  | Booking sync + change detection     |
| Interactive | `scripts/bot.ts`        | launchd KeepAlive        | Telegram             | Slash commands + AI routing         |

```
Cal.com Booking Event
  ├─→ Webhook → Cloud Run relay → Pushover (emergency, "dune" sound)
  └─→ sync.ts (6h poll) → Telegram (HTML) + Pushover (plain text)

Telegram Bot (always-on)
  └─→ /bookings, /today, /status, free-text → Agent SDK (Haiku)
```

Cal.com CLI (compiled Bun binary): `scripts/calcom-cli/` — separate `package.json` + build process.

## Environment Variables

| Variable                   | Required | Description                                                 |
| -------------------------- | -------- | ----------------------------------------------------------- |
| `CALCOM_OP_UUID`           | Yes      | 1Password item UUID for Cal.com API key                     |
| `TELEGRAM_BOT_TOKEN`       | Yes      | Telegram bot token (@calcom_commander_bot)                  |
| `TELEGRAM_CHAT_ID`         | Yes      | Authorized chat ID                                          |
| `HAIKU_MODEL`              | Yes      | Claude model for routing (e.g. `claude-haiku-4-5-20251001`) |
| `OP_SERVICE_ACCOUNT_TOKEN` | Yes      | 1Password service account (biometric-free)                  |
| `PUSHOVER_APP_TOKEN`       | No       | Pushover application token (dual-channel)                   |
| `PUSHOVER_USER_KEY`        | No       | Pushover user key (dual-channel)                            |
| `PUSHOVER_SOUND`           | No       | Custom Pushover sound name (default: `dune`)                |
| `PUSHOVER_OP_UUID`         | No       | 1Password item UUID for Pushover credentials                |
| `WEBHOOK_RELAY_URL`        | No       | Cloud Run webhook relay URL                                 |
| `CALCOM_API_URL`           | No       | Cal.com API base URL (default: self-hosted instance)        |
| `AUDIT_DIR`                | No       | Audit log directory (default: `~/own/amonic/logs/audit`)    |
| `BOT_STATE_FILE`           | No       | Bot state file path                                         |

## Conventions

- **Hooks**: Use `$HOME`-based paths, never `$CLAUDE_PLUGIN_ROOT`
- **Skills**: Follow Suite Pattern (Template F) with mandatory preflight
- **CLI paths**: `$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli/calcom`
- **Secrets**: `.mise.local.toml` (gitignored) in project directory
- **Deploy**: SKILL.md prescription for Cloud Run + Docker Compose (not in CLI)
- **Dual-channel**: Telegram (HTML) + Pushover (plain text). Build in HTML, strip for Pushover.
- **Pushover optional**: All Pushover functionality gracefully degrades if credentials not set
- **Webhook relay**: Deployed to same GCP project as Cal.com (Cloud Run, `--allow-unauthenticated`)
