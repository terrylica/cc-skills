---
name: send-message
description: "Send Telegram message as your personal account via MTProto. Use when user wants to send a message on Telegram, text someone on Telegram, or message a Telegram contact. TRIGGERS - telegram send, send telegram, text on telegram, message telegram, telegram message"
allowed-tools: Bash, Read, Grep, Glob
---

# Send Telegram Message

Send a message from your personal Telegram account (not a bot) via MTProto.

## Preflight

Before sending, verify:

1. Session exists at `~/.local/share/telethon/session.session`
   - If missing, run `/telegram-cli:setup` first
2. 1Password CLI available: `op --version`
3. Script exists at plugin path

## Usage

```bash
/usr/bin/env bash << 'SEND_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}"

# By username
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" send @username "Hello from CLI"

# By chat ID (integer)
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" send 2124832490 "Hello"

# By phone number
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" send "+16043008878" "Hello"
SEND_EOF
```

## Parameters

| Parameter | Type       | Description                                                 |
| --------- | ---------- | ----------------------------------------------------------- |
| recipient | string/int | Username (@user), phone (+1234567890), or chat ID (integer) |
| message   | string     | Message text to send                                        |

## Finding Chat IDs

Use the `list-dialogs` skill or run:

```bash
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" dialogs
```

## Credential Resolution

1. Checks `TELEGRAM_API_ID` + `TELEGRAM_API_HASH` env vars
2. Falls back to 1Password: `op item get <TELETHON_OP_UUID> --vault "Claude Automation"`
3. Session file at `~/.local/share/telethon/session.session` handles user auth
