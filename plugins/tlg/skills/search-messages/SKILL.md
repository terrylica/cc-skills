---
name: search-messages
description: "Use when user wants to search for messages across all Telegram chats or within a specific chat, find old messages by text, or look up Telegram message history filtered by sender."
allowed-tools: Bash, Read, Grep, Glob
---

# Search Telegram Messages

Search messages globally across all chats or within a specific chat.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.py"

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

| Parameter    | Type       | Description                                                              |
| ------------ | ---------- | ------------------------------------------------------------------------ |
| query        | string     | Search text (required)                                                   |
| `--chat`     | string/int | Limit to specific chat (omit for global)                                 |
| `--from`     | string/int | Filter by sender                                                         |
| `-n/--limit` | int        | Max results (default: 20)                                                |
| `--preview`  | int        | Truncate each body to N chars (default: full text, multi-line indented). |

## Output Format

Default (full text, multi-line indented):

```
[YYYY-MM-DD HH:MM] [Chat Name] (id:12345) Sender: First line of body
    continuation line 1 (indented under header)
    continuation line 2
```

With `--preview 100`:

```
[YYYY-MM-DD HH:MM] [Chat Name] (id:12345) Sender: First line of body ⏎ continuation collapsed onto…
```

Use `--preview N` only for high-volume scans where you want one row per
message. Default = full text — long bodies are no longer silently
truncated at 150 chars (the prior default forced direct-Telethon escape
hatches when content actually mattered).

## Anti-Patterns

- **Flood risk**: Global search with common terms may hit rate limits (~30s wait per 10 requests)
- **Empty results**: Global search requires non-empty query string

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If tg-cli.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
