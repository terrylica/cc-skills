# Telegram CLI Plugin

> Send Telegram messages as your personal account via MTProto (GramJS) — not as a bot.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gmail-commander CLAUDE.md](../gmail-commander/CLAUDE.md)

## Architecture

Single function/enum-driven **Bun TypeScript** CLI using **GramJS** (MTProto client), run directly with `bun` (no build). Multi-profile support for multiple accounts.

| Component      | Path                                      | Purpose                                                                                 |
| -------------- | ----------------------------------------- | --------------------------------------------------------------------------------------- |
| CLI Script     | `scripts/tg-cli.ts`                       | Bun TS, invoked via `bun`; `telegram` is vendored in `scripts/vendor/`, no install      |
| Session footer | `scripts/session-footer.ts`               | SSoT for the provenance footer appended to every send (tests: `session-footer.test.ts`) |
| Exact links    | `scripts/safe-links.ts`                   | Dependency-free: `exactLinks` (bare links → exact `<a>`), `badLinks` (read-back check)  |
| Link entities  | `scripts/link-entities.ts`                | The same cut as GramJS entities, `relink` fixes, mention entities for `EditMessage`     |
| Cleanup        | `scripts/cleanup_deleted.ts`              | Purge deleted/ghost accounts (reuses CLI helpers)                                       |
| Sessions       | `~/.local/share/gramjs/<profile>.session` | Per-profile GramJS StringSession (one per account)                                      |
| Credentials    | 1Password `Claude Automation` vault       | Per-profile Telegram API id/hash                                                        |

## Profiles

Profile names and their 1Password item IDs are machine-local, never committed: `~/.config/cc-skills/tlg-profiles.json`, shaped `{ "default": "<profile>", "profiles": { "<profile>": "<item-id>" } }` (read by `loadProfiles()` in `scripts/tg-cli.ts`). `TELETHON_OP_UUID` overrides the item for one run.

## Standing policies

- **Session-reference footer on every send.** Every composed send — `send`, a `send-file` caption, and a `draft` — carries a provenance footer (`via Claude Code | session <uuid> | <context> | <timestamp>`), for all recipients, so the Telegram history doubles as a provenance trail. Use `--no-footer` for an external or sensitive chat where the session reference should not be disclosed. The context label is opt-in via `--context` and is never auto-filled from the working directory. Logic + tests live in `scripts/session-footer.ts`; `forward` is exempt (it relays, composing no new text). Content already bearing a Claude Code footer is not re-stamped.

- **Exact links on every send.** Telegram's server extends a bare link over the full-width punctuation and CJK text after it, up to the next whitespace (measured 2026-11-22). `send`, `draft`, `send-file` captions and `edit` therefore give each bare link an explicit link that ends where its URL ends, read each message back, and exit 1 naming any stored link that covers more than its URL; `relink <chat> <ids>` fixes sent messages. Logic, tests and the measurement: `scripts/safe-links.ts` and [send-message](./skills/send-message/SKILL.md#exact-links-automatic--no-link-may-swallow-chinese-text). Other code imports `exactLinks`/`badLinks` from `"$(cc-plugin-root tlg)/scripts/safe-links.ts"`, as it already imports `tg-cli.ts` and `session-footer.ts`.

## Skills by area

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

### Media, Archival & Setup

| Skill                                                | Purpose                                                     |
| ---------------------------------------------------- | ----------------------------------------------------------- |
| [download-media](./skills/download-media/SKILL.md)   | Download files from messages                                |
| [setup](./skills/setup/SKILL.md)                     | First-time auth + credential setup                          |
| [draft-message](./skills/draft-message/SKILL.md)     | Post a long or sensitive draft to Saved Messages for review |
| [dump-channel](./skills/dump-channel/SKILL.md)       | Archive a channel or chat to NDJSON with all media          |
| [cleanup-deleted](./skills/cleanup-deleted/SKILL.md) | Purge deleted or ghost accounts from dialogs and contacts   |

## Quick Reference

```bash
ROOT="$(cc-plugin-root tlg)"
SCRIPT="$ROOT/scripts/tg-cli.ts"

# Messaging
bun "$SCRIPT" send <to> "text"
bun "$SCRIPT" send-file <to> /path/to/file [-c "caption"]
bun "$SCRIPT" forward <from> <msg_ids> <to>
bun "$SCRIPT" edit <chat> <msg_id> "new text"
bun "$SCRIPT" relink <chat> <msg_ids>        # make the links of sent messages exact
bun "$SCRIPT" delete <chat> <msg_ids>
bun "$SCRIPT" pin <chat> <msg_id> [--unpin] [--silent]
bun "$SCRIPT" mark-read <chat>

# Reading & Search
bun "$SCRIPT" read <chat> [-n 10] [--around ID | --after ID | --before ID] [--topic ID] [--json] [--utc]
bun "$SCRIPT" thread <chat> <msg_id> [--replies]   # what a reply answers: climb its ↩ chain
bun "$SCRIPT" search "query" [--chat <chat>] [--from <user>]   # global results name their {chat}
bun "$SCRIPT" dialogs
bun "$SCRIPT" whoami
bun "$SCRIPT" find-user @username

# Media
bun "$SCRIPT" download <chat> <msg_id> [-o /path]
bun "$SCRIPT" dump <chat> <out_dir> [--no-media] [--after ID]

# Groups
bun "$SCRIPT" create-group "Title" [--type supergroup|channel|group]
bun "$SCRIPT" invite <group> @user1 @user2
bun "$SCRIPT" kick <group> @user
bun "$SCRIPT" members <group> [--admins] [--search "name"]
```

All commands accept `-p <profile>` (default: the file's `default`, else its first profile).

## Credentials

Fetched from 1Password at runtime via `op item get`. Each profile maps to a different 1Password item.

**Override**: Set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` env vars to skip 1Password.

**Service-account token** (no Touch ID prompt): resolved by `scripts/op-sa-token.ts` from the first of `OP_SERVICE_ACCOUNT_TOKEN` (already exported), `OP_SA_TOKEN_CMD` (a command printing the token, run as a plain argv with no shell, e.g. `vault get op-service-account token`) or `OP_SA_TOKEN_FILE` (a file you name). There is no default path. With none set, `op` uses the 1Password app; a source that is set but fails is an error, never skipped.

## Upstream

MTProto client library is **GramJS** (`telegram` on npm):

- **Canonical**: <https://github.com/gram-js/gramjs> · docs <https://gram.js.org>
- Vendored, not installed: `scripts/vendor/telegram.js` is bundled from `scripts/bun.lock` by `scripts/vendor-plugin-deps.ts` (`moon run repo:vendor-deps` rebuilds it after a lockfile change).
