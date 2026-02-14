# Cal.com Commander Plugin

Cal.com + Telegram bot lifecycle — booking management, interactive commands, scheduled sync, Agent SDK routing, 1Password OAuth.

## Architecture

Two independent processes sharing `scripts/lib/`:

| Process    | Entry             | Trigger                  | Purpose                         |
| ---------- | ----------------- | ------------------------ | ------------------------------- |
| Bot Daemon | `scripts/bot.ts`  | launchd KeepAlive        | Interactive Telegram commands   |
| Sync       | `scripts/sync.ts` | launchd StartInterval 6h | Scheduled booking sync + notify |

Cal.com CLI (compiled Bun binary): `scripts/calcom-cli/` — separate `package.json` + build process.

## Environment Variables

| Variable                   | Required | Description                                                 |
| -------------------------- | -------- | ----------------------------------------------------------- |
| `CALCOM_OP_UUID`           | Yes      | 1Password item UUID for Cal.com API key                     |
| `TELEGRAM_BOT_TOKEN`       | Yes      | Telegram bot token (@calcom_commander_bot)                  |
| `TELEGRAM_CHAT_ID`         | Yes      | Authorized chat ID                                          |
| `HAIKU_MODEL`              | Yes      | Claude model for routing (e.g. `claude-haiku-4-5-20251001`) |
| `OP_SERVICE_ACCOUNT_TOKEN` | Yes      | 1Password service account (biometric-free)                  |
| `CALCOM_API_URL`           | No       | Cal.com API base URL (default: self-hosted instance)        |
| `AUDIT_DIR`                | No       | Audit log directory (default: `~/own/amonic/logs/audit`)    |
| `BOT_STATE_FILE`           | No       | Bot state file path                                         |

## Conventions

- **Hooks**: Use `$HOME`-based paths, never `$CLAUDE_PLUGIN_ROOT`
- **Skills**: Follow Suite Pattern (Template F) with mandatory preflight
- **CLI paths**: `$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli/calcom`
- **Secrets**: `.mise.local.toml` (gitignored) in project directory
- **Deploy**: SKILL.md prescription for Cloud Run + Docker Compose (not in CLI)
