# Telegram CLI Plugin

> Send Telegram messages as your personal account via MTProto (GramJS) — not as a bot.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gmail-commander CLAUDE.md](../gmail-commander/CLAUDE.md)

## Architecture

Single function/enum-driven **Bun TypeScript** CLI using **GramJS** (MTProto client),
run directly with `bun` (no build). Multi-profile support for multiple accounts.

| Component   | Path                                      | Purpose                                            |
| ----------- | ----------------------------------------- | -------------------------------------------------- |
| CLI Script  | `scripts/tg-cli.ts`                       | Bun TS, invoked via `bun` (deps: `bun install`)    |
| Cleanup     | `scripts/cleanup_deleted.ts`              | Purge deleted/ghost accounts (reuses CLI helpers)  |
| Sessions    | `~/.local/share/gramjs/<profile>.session` | Per-profile GramJS StringSession (one per account) |
| Credentials | 1Password `Claude Automation` vault       | Per-profile Telegram API id/hash                   |

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
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.ts"

# Messaging
bun "$SCRIPT" send <to> "text"
bun "$SCRIPT" send-file <to> /path/to/file [-c "caption"]
bun "$SCRIPT" forward <from> <msg_ids> <to>
bun "$SCRIPT" edit <chat> <msg_id> "new text"
bun "$SCRIPT" delete <chat> <msg_ids>
bun "$SCRIPT" pin <chat> <msg_id> [--unpin] [--silent]
bun "$SCRIPT" mark-read <chat>

# Reading & Search
bun "$SCRIPT" read <chat> [-n 10]
bun "$SCRIPT" search "query" [--chat <chat>] [--from <user>]
bun "$SCRIPT" dialogs
bun "$SCRIPT" whoami
bun "$SCRIPT" find-user @username

# Media
bun "$SCRIPT" download <chat> <msg_id> [-o /path]

# Groups
bun "$SCRIPT" create-group "Title" [--type supergroup|channel|group]
bun "$SCRIPT" invite <group> @user1 @user2
bun "$SCRIPT" kick <group> @user
bun "$SCRIPT" members <group> [--admins] [--search "name"]
```

All commands accept `-p <profile>` (default: `eon`).

## Credentials

Fetched from 1Password at runtime via `op item get`. Each profile maps to a different 1Password item.

**Override**: Set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` env vars to skip 1Password.

## Upstream

MTProto client library is **GramJS** (`telegram` on npm):

- **Canonical**: <https://github.com/gram-js/gramjs> · docs <https://gram.js.org>
- Installed as a local dep in `scripts/` (`bun install`); the old Telethon/`uv`
  toolchain was retired in the 2026-06 TypeScript port.

## Migration note (2026-06-22)

Ported from Telethon (Python, `uv run`) to GramJS (Bun TS). The MTProto engine
changed, so the **session format changed**: sessions now live at
`~/.local/share/gramjs/<profile>.session` as GramJS StringSessions — the old
`~/.local/share/telethon/*.session` files are not reused. Each account logs in
once more via the non-interactive flow (`send-code` → `sign-in`); see
[setup](./skills/setup/SKILL.md). The Telegram API id/hash (1Password) are
unchanged. `eon` was re-authenticated and verified; `missterryli` re-login pending.

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
