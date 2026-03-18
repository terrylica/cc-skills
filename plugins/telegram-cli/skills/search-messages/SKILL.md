---
name: search-messages
description: "Search for messages across all Telegram chats or within a specific chat. Find text, filter by sender. TRIGGERS - telegram search, search telegram, find in telegram, telegram find message, search telegram chat, search telegram text"
allowed-tools: Bash, Read, Grep, Glob
---

# Search Telegram Messages

Search messages globally across all chats or within a specific chat.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}/scripts/send.py"

# Global search (all chats)
uv run --python 3.13 "$SCRIPT" search "search term" -n 20

# Search in specific chat
uv run --python 3.13 "$SCRIPT" search "keyword" --chat 2124832490

# Filter by sender
uv run --python 3.13 "$SCRIPT" search "topic" --from @username

# Combined: search in chat from specific sender
uv run --python 3.13 "$SCRIPT" search "query" --chat @groupname --from @sender -n 10
EOF
```

## Parameters

| Parameter    | Type       | Description                              |
| ------------ | ---------- | ---------------------------------------- |
| query        | string     | Search text (required)                   |
| `--chat`     | string/int | Limit to specific chat (omit for global) |
| `--from`     | string/int | Filter by sender                         |
| `-n/--limit` | int        | Max results (default: 20)                |

## Output Format

```
[YYYY-MM-DD HH:MM] [Chat Name] (id:12345) Sender: Message text...
```

## Anti-Patterns

- **Flood risk**: Global search with common terms may hit rate limits (~30s wait per 10 requests)
- **Empty results**: Global search requires non-empty query string
