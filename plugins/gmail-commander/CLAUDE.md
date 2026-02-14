# Gmail Commander Plugin

Gmail + Telegram bot lifecycle — email triage, interactive commands, voice digest, Agent SDK routing, 1Password OAuth.

## Architecture

Two independent processes sharing `scripts/lib/`:

| Process    | Entry               | Trigger                  | Purpose                        |
| ---------- | ------------------- | ------------------------ | ------------------------------ |
| Bot Daemon | `scripts/bot.ts`    | launchd KeepAlive        | Interactive Telegram commands  |
| Digest     | `scripts/digest.ts` | launchd StartInterval 6h | Scheduled email triage + voice |

Gmail CLI (absorbed from gmail-tools): `scripts/gmail-cli/` — separate `package.json` + build process.

## Environment Variables

| Variable                   | Required | Description                                                |
| -------------------------- | -------- | ---------------------------------------------------------- |
| `GMAIL_OP_UUID`            | Yes      | 1Password item UUID for OAuth credentials                  |
| `TELEGRAM_BOT_TOKEN`       | Yes      | Telegram bot token                                         |
| `TELEGRAM_CHAT_ID`         | Yes      | Authorized chat ID                                         |
| `HAIKU_MODEL`              | Yes      | Claude model for triage (e.g. `claude-haiku-4-5-20251001`) |
| `OP_SERVICE_ACCOUNT_TOKEN` | Yes      | 1Password service account (biometric-free)                 |
| `AUDIT_DIR`                | No       | Audit log directory (default: `~/own/amonic/logs/audit`)   |
| `BOT_STATE_FILE`           | No       | Bot state file path                                        |
| `GMAIL_OP_VAULT`           | No       | 1Password vault (default: Employee)                        |

## Conventions

- **Hooks**: Use `$HOME`-based paths, never `$CLAUDE_PLUGIN_ROOT`
- **Skills**: Follow Suite Pattern (Template F) with mandatory preflight
- **CLI paths**: `$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail`
- **Sender alignment**: Auto-detect for replies, AskUserQuestion for new emails
- **Secrets**: `.mise.local.toml` (gitignored) in project directory
