---
name: list-dialogs
description: "List all Telegram chats, groups, and channels for your personal account. Use when user wants to see their Telegram contacts, find a chat ID, browse Telegram conversations. TRIGGERS - telegram dialogs, telegram chats, telegram contacts, find telegram chat, telegram chat id"
allowed-tools: Bash, Read, Grep, Glob
---

# List Telegram Dialogs

List all chats, groups, and channels visible to your personal Telegram account.

## Preflight

1. Session must exist: `~/.local/share/telethon/session.session`
   - If missing, run `/telegram-cli:setup` first
2. 1Password CLI available: `op --version`

## Usage

```bash
/usr/bin/env bash << 'DIALOGS_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}"
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" dialogs
DIALOGS_EOF
```

## Output Format

Each line shows:

```
Chat Name                                  (id: 1234567890)
```

Use the `id` value with `send-message` skill to send to that chat.

## Filtering Results

Pipe output through grep to find specific chats:

```bash
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" dialogs | grep -i "search term"
```
