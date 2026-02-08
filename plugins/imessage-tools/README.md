# imessage-tools

macOS iMessage database querying plugin for Claude Code.

## Skills

| Skill            | Description                                                                                                                     |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `imessage-query` | Query `chat.db` via SQLite — decode NSAttributedString messages, handle tapbacks, search conversations, build sourced timelines |

## Prerequisites

- **macOS only** — iMessage database is a macOS-specific feature
- **Full Disk Access** — Terminal/Claude Code must have FDA to read `~/Library/Messages/chat.db`
- **Python 3.10+** — For the decode script (stdlib only, no external dependencies)

## Quick Start

```bash
# List all conversations
sqlite3 ~/Library/Messages/chat.db "SELECT chat_identifier, display_name FROM chat ORDER BY ROWID DESC LIMIT 20"

# Decode messages with attributedBody fallback
python3 plugins/imessage-tools/skills/imessage-query/scripts/decode_attributed_body.py --chat "+1234567890" --limit 50
```
