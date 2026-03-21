---
name: send-message
description: "Send Telegram message as your personal account via MTProto. Use when user wants to send a message on Telegram, text someone on Telegram, or message a Telegram contact. TRIGGERS - telegram send, send telegram, text on telegram, message telegram, telegram message"
allowed-tools: Bash, Read, Grep, Glob
---

# Send Telegram Message

Send a message from your personal Telegram account (not a bot) via MTProto.

## Preflight

Before sending, verify:

1. Session exists at `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first
2. 1Password CLI available: `op --version`

## Usage

```bash
/usr/bin/env bash << 'SEND_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}"

# Default profile (eon)
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" send @username "Hello"

# By chat ID
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" send 2124832490 "Hello"

# Specific profile
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" -p personal send @username "Hello"
SEND_EOF
```

## Profiles

| Profile         | Account            | User ID    |
| --------------- | ------------------ | ---------- |
| `eon` (default) | @ExampleOpsAccount | 90417581   |
| `personal`   | @personal       | 2124832490 |

## Parameters

| Parameter      | Type       | Description                                                 |
| -------------- | ---------- | ----------------------------------------------------------- |
| `-p/--profile` | string     | Account profile (default: eon)                              |
| recipient      | string/int | Username (@user), phone (+1234567890), or chat ID (integer) |
| message        | string     | Message text (cannot be empty)                              |

## Error Handling

| Error                     | Cause               | Fix                           |
| ------------------------- | ------------------- | ----------------------------- |
| `Unknown profile`         | Invalid `-p` value  | Use `eon` or `personal`    |
| `Cannot find any entity`  | Bad username/ID     | Verify with `dialogs` command |
| `message cannot be empty` | Empty string passed | Provide message text          |
