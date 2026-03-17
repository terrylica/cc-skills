# Telegram CLI Plugin

> Send Telegram messages as your personal account via MTProto (Telethon) — not as a bot.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gmail-commander CLAUDE.md](../gmail-commander/CLAUDE.md)

## Architecture

Single Python script using Telethon (MTProto client). Acts as your user account, not a bot.

| Component   | Path                                      | Purpose                                       |
| ----------- | ----------------------------------------- | --------------------------------------------- |
| CLI Script  | `scripts/send.py`                         | PEP 723 inline deps, invoked via `uv run`     |
| Session     | `~/.local/share/telethon/session.session` | Persisted auth (phone + code + 2FA, one-time) |
| Credentials | 1Password `Claude Automation` vault       | `App ID` + `App API Hash` fetched at runtime  |
| Source Fork | `~/fork-tools/Telethon`                   | Cloned from Codeberg (canonical upstream)     |

## Skills (3)

| Skill                                          | Purpose                            |
| ---------------------------------------------- | ---------------------------------- |
| [send-message](./skills/send-message/SKILL.md) | Send messages as your account      |
| [list-dialogs](./skills/list-dialogs/SKILL.md) | Browse all chats/groups/channels   |
| [setup](./skills/setup/SKILL.md)               | First-time auth + credential setup |

## Credentials

Fetched from 1Password at runtime via `op item get`:

| Field    | Type      | 1Password Label |
| -------- | --------- | --------------- |
| API ID   | TEXT      | `App ID`        |
| API Hash | CONCEALED | `App API Hash`  |

**Item**: `Telegram API - ExampleOpsAccount` in vault `Claude Automation`

**Override**: Set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` env vars to skip 1Password.

## Environment Variables

| Variable            | Required | Description                                        |
| ------------------- | -------- | -------------------------------------------------- |
| `TELETHON_OP_UUID`  | No       | 1Password item UUID (default: hardcoded in script) |
| `TELETHON_OP_VAULT` | No       | 1Password vault (default: `Claude Automation`)     |
| `TELEGRAM_API_ID`   | No       | Direct API ID (skips 1Password)                    |
| `TELEGRAM_API_HASH` | No       | Direct API hash (skips 1Password)                  |

## Upstream

Telethon migrated from GitHub to Codeberg (2026-02-21):

- **Canonical**: <https://codeberg.org/Lonami/Telethon>
- **Local clone**: `~/fork-tools/Telethon` (from Codeberg)
- **Stale GitHub**: <https://github.com/LonamiWebs/Telethon> (redirect only)
