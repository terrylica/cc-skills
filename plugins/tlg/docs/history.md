# tlg: history

> Moved from the plugin hub on 2026-10-01. Dated records; the hub holds only current guidance.

## Migration note (2026-06-22)

Ported from Telethon (Python, `uv run`) to GramJS (Bun TS). The MTProto engine changed, so the **session format changed**: sessions now live at `~/.local/share/gramjs/<profile>.session` as GramJS StringSessions — the old `~/.local/share/telethon/*.session` files are not reused. Each account logs in once more via the non-interactive flow (`send-code` → `sign-in`); see [setup](../skills/setup/SKILL.md). The Telegram API id/hash (1Password) are unchanged. `work` was re-authenticated and verified; `personal` re-login pending.

## Validation Results (2026-03-17)

All 17 subcommands empirically tested bi-directionally between `work` and `personal`:

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
