---
name: imessage-query
description: Query macOS iMessage database (chat.db) via SQLite. Decode NSAttributedString messages, handle tapbacks, search conversations. TRIGGERS - imessage, chat.db, messages database, text messages, iMessage history, NSAttributedString, attributedBody
allowed-tools: Read, Bash, Grep, Glob, Write
---

# iMessage Database Query

Query the macOS iMessage SQLite database (`~/Library/Messages/chat.db`) to retrieve conversation history, decode messages stored in binary format, and build sourced timelines with precise timestamps.

## When to Use

- Retrieving iMessage conversation history for a specific contact
- Building sourced timelines with timestamps from text messages
- Searching for keywords across all conversations
- Debugging messages that appear empty but contain recoverable text
- Extracting message content that iOS stored in binary `attributedBody` format

## Prerequisites

1. **macOS only** — `chat.db` is a macOS-specific database
2. **Full Disk Access** — The terminal running Claude Code must have FDA granted in System Settings > Privacy & Security > Full Disk Access
3. **Read-only** — Never write to `chat.db`. Always use read-only SQLite access.

## Critical Knowledge - The `text` vs `attributedBody` Problem

**IMPORTANT**: Many iMessage messages have a NULL or empty `text` column but contain valid, recoverable text in the `attributedBody` column. This is NOT because they are voice messages — iOS stores dictated messages, messages with rich formatting, and some regular messages in `attributedBody` as an NSAttributedString binary blob.

### How to detect

```sql
-- Messages with attributedBody but no text (these are NOT necessarily voice messages)
SELECT COUNT(*) as hidden_messages
FROM message m
JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
JOIN chat c ON cmj.chat_id = c.ROWID
WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
AND (m.text IS NULL OR length(m.text) = 0)
AND m.attributedBody IS NOT NULL
AND length(m.attributedBody) > 100
AND m.associated_message_type = 0
AND m.cache_has_attachments = 0;
```

### How to distinguish message types when `text` is NULL

| `cache_has_attachments` | `attributedBody` length | Likely type                                                                |
| ----------------------- | ----------------------- | -------------------------------------------------------------------------- |
| 0                       | > 100 bytes             | **Dictated/rich text** — recoverable via decode script                     |
| 1                       | any                     | Attachment (image, file, voice memo) — text may be in `attributedBody` too |
| 0                       | < 50 bytes              | Tapback reaction or system message — usually noise                         |

### How to decode

Use the bundled decode script for reliable extraction:

```bash
python3 <skill-path>/scripts/decode_attributed_body.py --chat "<CHAT_IDENTIFIER>" --limit 50
```

Or use inline Python for one-off decoding (see [Known Pitfalls](./references/known-pitfalls.md) for the technique).

## Date Formula

iMessage stores dates as **nanoseconds since Apple epoch (2001-01-01 00:00:00 UTC)**.

```sql
datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as timestamp
```

- `m.date / 1000000000` — Convert nanoseconds to seconds
- `+ 978307200` — Add offset from Unix epoch (1970) to Apple epoch (2001)
- `'unixepoch'` — Tell SQLite this is a Unix timestamp
- `'localtime'` — Convert to local timezone (CRITICAL — omitting this gives UTC)

## Quick Start Queries

### 1. List all conversations

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT c.chat_identifier, c.display_name, COUNT(cmj.message_id) as msg_count
   FROM chat c
   JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
   GROUP BY c.ROWID
   ORDER BY msg_count DESC
   LIMIT 20"
```

### 2. Get conversation thread (text column only)

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as ts,
          CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Them' END as sender,
          m.text
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
   AND length(m.text) > 0
   AND m.associated_message_type = 0
   ORDER BY m.date DESC
   LIMIT 50"
```

### 3. Get ALL messages including attributedBody (use decode script)

```bash
python3 <skill-path>/scripts/decode_attributed_body.py \
  --chat "<CHAT_IDENTIFIER>" \
  --after "2026-01-01" \
  --limit 100
```

## Filtering Noise

### Tapback reactions

Tapback reactions (likes, loves, emphasis, etc.) are stored as separate message rows with `associated_message_type != 0`. Always filter:

```sql
AND m.associated_message_type = 0
```

### Shell escaping in zsh

The `!=` operator can cause issues in zsh. Use positive assertions instead:

```sql
-- BAD (breaks in zsh)
AND m.text != ''

-- GOOD (works everywhere)
AND length(m.text) > 0
```

## Using the Decode Script

The bundled `decode_attributed_body.py` handles all edge cases:

```bash
# Basic usage - get last 50 messages from a contact
python3 <skill-path>/scripts/decode_attributed_body.py --chat "+1234567890" --limit 50

# Search for keyword
python3 <skill-path>/scripts/decode_attributed_body.py --chat "+1234567890" --search "meeting"

# Date range
python3 <skill-path>/scripts/decode_attributed_body.py --chat "+1234567890" --after "2026-01-01" --before "2026-02-01"

# Only messages from the other party
python3 <skill-path>/scripts/decode_attributed_body.py --chat "+1234567890" --sender them

# Only messages from me
python3 <skill-path>/scripts/decode_attributed_body.py --chat "+1234567890" --sender me
```

Output format: `timestamp|sender|text` (pipe-delimited, one message per line)

**Note**: Replace `<skill-path>` with the actual installed skill path. To find it:

```bash
find ~/.claude -path "*/imessage-query/scripts/decode_attributed_body.py" 2>/dev/null
```

## Reference Documentation

- [Schema Reference](./references/schema-reference.md) — Tables, columns, relationships
- [Query Patterns](./references/query-patterns.md) — Reusable SQL templates for common operations
- [Known Pitfalls](./references/known-pitfalls.md) — Every gotcha discovered and how to handle it

---

## TodoWrite Task Templates

### Template A - Retrieve Conversation Thread

```
1. Identify chat_identifier for the contact (phone number or email)
2. Run decode script with --chat and appropriate date range
3. Review output for attributedBody-decoded messages (marked with [decoded])
4. If searching for specific topic, add --search flag
5. Format results as needed for the task
```

### Template B - Debug Empty Messages

```
1. Query messages where text IS NULL but attributedBody IS NOT NULL
2. Check cache_has_attachments to distinguish voice/file from dictated text
3. Run decode script to extract hidden text content
4. Verify decoded content makes sense in conversation context
5. Document any new decode patterns in known-pitfalls.md
```

### Template C - Build Sourced Timeline

```
1. Identify all relevant chat_identifiers
2. Run decode script for each contact with date range
3. Merge and sort by timestamp
4. Format as sourced quotes with timestamps for documentation
5. Verify no messages were missed (compare total count vs decoded count)
```

---

## Post-Change Checklist

After modifying this skill:

1. [ ] YAML frontmatter valid (name, description with triggers)
2. [ ] No private data (phone numbers, names, emails) in any file
3. [ ] All SQL uses parameterized placeholders
4. [ ] Decode script works with `python3` (no external deps)
5. [ ] All reference links are relative paths
6. [ ] Append changes to [evolution-log.md](./references/evolution-log.md)
