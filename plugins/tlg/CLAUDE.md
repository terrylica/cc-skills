# Telegram CLI Plugin

> Send Telegram messages as your personal account via MTProto (Telethon) — not as a bot.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gmail-commander CLAUDE.md](../gmail-commander/CLAUDE.md)

## Architecture

Single Python script using Telethon (MTProto client). Multi-profile support for multiple accounts.

| Component   | Path                                        | Purpose                                   |
| ----------- | ------------------------------------------- | ----------------------------------------- |
| CLI Script  | `scripts/tg-cli.py`                           | PEP 723 inline deps, invoked via `uv run` |
| Sessions    | `~/.local/share/telethon/<profile>.session` | Per-profile persisted auth                |
| Credentials | 1Password `Claude Automation` vault         | Per-profile API credentials               |
| Source Fork | `~/fork-tools/Telethon`                     | Cloned from Codeberg (canonical upstream) |

## Profiles

| Profile         | Account            | User ID    | 1Password Item UUID          |
| --------------- | ------------------ | ---------- | ---------------------------- |
| `eon` (default) | @EonLabsOperations | 90417581   | `iqwxow2iidycaethycub7agfmm` |
| `missterryli`   | @missterryli       | 2124832490 | `dk456cs3v2fjilppernryoro5a` |

## Skills (13)

### Messaging

| Skill                                                | Purpose                                 |
| ---------------------------------------------------- | --------------------------------------- |
| [send-message](./skills/send-message/SKILL.md)       | Send text messages                      |
| [send-media](./skills/send-media/SKILL.md)           | Send files, photos, videos, voice notes |
| [forward-message](./skills/forward-message/SKILL.md) | Forward messages between chats          |
| [pin-message](./skills/pin-message/SKILL.md)         | Pin/unpin messages                      |
| [delete-messages](./skills/delete-messages/SKILL.md) | Delete messages                         |
| [mark-read](./skills/mark-read/SKILL.md)             | Mark chats as read                      |

### Discovery & Search

| Skill                                                | Purpose                                  |
| ---------------------------------------------------- | ---------------------------------------- |
| [list-dialogs](./skills/list-dialogs/SKILL.md)       | Browse chats, read messages, whoami      |
| [search-messages](./skills/search-messages/SKILL.md) | Global + per-chat message search         |
| [find-user](./skills/find-user/SKILL.md)             | Resolve username/phone/ID → profile info |

### Group & Channel Management

| Skill                                              | Purpose                              |
| -------------------------------------------------- | ------------------------------------ |
| [create-group](./skills/create-group/SKILL.md)     | Create groups, supergroups, channels |
| [manage-members](./skills/manage-members/SKILL.md) | Invite, kick, list members           |

### Media & Setup

| Skill                                              | Purpose                            |
| -------------------------------------------------- | ---------------------------------- |
| [download-media](./skills/download-media/SKILL.md) | Download files from messages       |
| [setup](./skills/setup/SKILL.md)                   | First-time auth + credential setup |

## Quick Reference

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.py"

# Messaging
uv run --python 3.13 "$SCRIPT" send <to> "text"
uv run --python 3.13 "$SCRIPT" send-file <to> /path/to/file [-c "caption"]
uv run --python 3.13 "$SCRIPT" forward <from> <msg_ids> <to>
uv run --python 3.13 "$SCRIPT" edit <chat> <msg_id> "new text"
uv run --python 3.13 "$SCRIPT" delete <chat> <msg_ids>
uv run --python 3.13 "$SCRIPT" pin <chat> <msg_id> [--unpin] [--silent]
uv run --python 3.13 "$SCRIPT" mark-read <chat>

# Reading & Search
uv run --python 3.13 "$SCRIPT" read <chat> [-n 10]
uv run --python 3.13 "$SCRIPT" search "query" [--chat <chat>] [--from <user>]
uv run --python 3.13 "$SCRIPT" dialogs
uv run --python 3.13 "$SCRIPT" whoami
uv run --python 3.13 "$SCRIPT" find-user @username

# Media
uv run --python 3.13 "$SCRIPT" download <chat> <msg_id> [-o /path]

# Groups
uv run --python 3.13 "$SCRIPT" create-group "Title" [--type supergroup|channel|group]
uv run --python 3.13 "$SCRIPT" invite <group> @user1 @user2
uv run --python 3.13 "$SCRIPT" kick <group> @user
uv run --python 3.13 "$SCRIPT" members <group> [--admins] [--search "name"]
```

All commands accept `-p <profile>` (default: `eon`).

## Credentials

Fetched from 1Password at runtime via `op item get`. Each profile maps to a different 1Password item.

**Override**: Set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` env vars to skip 1Password.

## Upstream

Telethon migrated from GitHub to Codeberg (2026-02-21):

- **Canonical**: <https://codeberg.org/Lonami/Telethon>
- **Local clone**: `~/fork-tools/Telethon` (from Codeberg)

## Validation Results (2026-03-17)

All 17 subcommands empirically tested bi-directionally between `eon` and `missterryli`:

| Test                               | Status         |
| ---------------------------------- | -------------- |
| send (text, by ID, by username)    | ✅             |
| send-file (document with caption)  | ✅             |
| read (with message IDs in output)  | ✅             |
| search (global + per-chat)         | ✅             |
| forward (single + batch)           | ✅             |
| edit (text replacement)            | ✅             |
| delete (for everyone)              | ✅             |
| pin + unpin (silent)               | ✅             |
| mark-read                          | ✅             |
| find-user (username → JSON)        | ✅             |
| download (media to directory)      | ✅             |
| create-group (supergroup + invite) | ✅             |
| invite (to group)                  | ✅             |
| kick (from group)                  | ✅             |
| members (list + admin filter)      | ✅             |
| dialogs                            | ✅             |
| whoami                             | ✅             |
| Error: invalid profile             | ✅ clean error |
| Error: empty message               | ✅ clean error |
| Error: bad recipient               | ✅ clean error |

## Skills

- [cleanup-deleted](./skills/cleanup-deleted/SKILL.md)
- [create-group](./skills/create-group/SKILL.md)
- [delete-messages](./skills/delete-messages/SKILL.md)
- [download-media](./skills/download-media/SKILL.md)
- [draft-message](./skills/draft-message/SKILL.md)
- [dump-channel](./skills/dump-channel/SKILL.md)
- [find-user](./skills/find-user/SKILL.md)
- [forward-message](./skills/forward-message/SKILL.md)
- [list-dialogs](./skills/list-dialogs/SKILL.md)
- [manage-members](./skills/manage-members/SKILL.md)
- [mark-read](./skills/mark-read/SKILL.md)
- [pin-message](./skills/pin-message/SKILL.md)
- [search-messages](./skills/search-messages/SKILL.md)
- [send-media](./skills/send-media/SKILL.md)
- [send-message](./skills/send-message/SKILL.md)
- [setup](./skills/setup/SKILL.md)
