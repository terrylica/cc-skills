**Skill**: [iMessage Query](../SKILL.md)

# Known Pitfalls

Every gotcha discovered when working with the macOS iMessage database, with symptoms and solutions.

---

## Critical: The `text` vs `attributedBody` Problem

**Pitfall**: Many messages have a NULL or empty `text` column but contain valid, recoverable text in `attributedBody`.

**Symptom**: Messages appear empty or are mistakenly classified as "voice messages" when they are actually dictated text or rich-formatted messages.

**Root cause**: iOS stores messages typed via dictation, messages with rich formatting (links, styled text), and some regular messages in `attributedBody` as an NSAttributedString binary blob instead of (or in addition to) the `text` column.

**Solution**: Always check `attributedBody` when `text` is NULL. Use the decode script or the inline Python technique below.

**Scale**: In real-world conversations, 20-60% of one party's messages may be stored exclusively in `attributedBody`, especially if they use dictation frequently.

---

## Pitfall Reference Table

| #   | Pitfall                       | Symptom                                         | Solution                                                                                                 |
| --- | ----------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 1   | `text` column NULL            | Message appears empty/missing                   | Check `attributedBody` — use decode script                                                               |
| 2   | NSAttributedString binary     | Raw binary garbage in output                    | Split on null bytes, filter NS\* class names, take longest chunk                                         |
| 3   | Tapback reactions as messages | Duplicate/phantom messages                      | Filter with `associated_message_type = 0`                                                                |
| 4   | `iI` suffix artifacts         | Decoded text ends with `iI` + random chars      | Strip with regex `r'iI.{0,5}$'`                                                                          |
| 5   | `+` length prefix             | Decoded text starts with `+` then a single char | Strip with regex `r'^\+.'`                                                                               |
| 6   | Wrong timezone                | Timestamps off by hours                         | Add `'localtime'` modifier to `datetime()`                                                               |
| 7   | zsh `!=` escaping             | Shell error when using `!=` in SQL              | Use `length(m.text) > 0` instead of `m.text != ''`                                                       |
| 8   | `kIMMessagePartAttributeName` | Garbage metadata text in decoded output         | These are tapback metadata — filter by `associated_message_type = 0`                                     |
| 9   | Voice vs dictated confusion   | Both have NULL `text`                           | Voice: `cache_has_attachments = 1`. Dictated: `cache_has_attachments = 0` + `attributedBody` > 100 bytes |
| 10  | `NSValue` in decoded text     | Short garbage strings like "NSValue"            | These are tapback/reaction attribute values — already filtered by `associated_message_type = 0`          |

---

## Detailed Explanations

### 1. Decoding NSAttributedString Binary

The `attributedBody` column contains a serialized `NSAttributedString` object. The binary format includes:

- A `streamtyped` header
- The actual text content
- Attribute dictionaries (font, color, paragraph style)
- Apple framework class names as markers

**Decode strategy** (used by the bundled script):

```python
import re

def decode_attributed_body(attr_body: bytes) -> str | None:
    decoded = attr_body.decode("utf-8", errors="ignore")
    chunks = re.split(r"\x00+", decoded)

    # Filter out Apple framework noise
    ns_classes = {"NSDictionary", "NSMutableParagraphStyle", "NSFont",
                  "NSColor", "NSString", "NSAttributedString", "NSObject",
                  "NSNumber", "NSValue", "NSArray", "NSURL", "NSRange",
                  "streamtyped", "kIMMessagePartAttributeName",
                  "__kIMMessagePartAttributeName"}

    meaningful = [c.strip() for c in chunks
                  if len(c.strip()) > 3
                  and not any(cls in c for cls in ns_classes)]

    if not meaningful:
        return None

    text = max(meaningful, key=len)
    text = re.sub(r"iI.{0,5}$", "", text).strip()
    text = re.sub(r"^\+.", "", text).strip()
    return text if len(text) > 1 else None
```

### 2. Tapback Reactions

When a user "likes" or "loves" a message, iOS creates a NEW message row with:

- `associated_message_type` set to 2000-2005 (or 3000-3005 for removal)
- `text` often NULL
- `attributedBody` containing metadata about the reaction

**Always filter**: `AND m.associated_message_type = 0`

Without this filter, conversations appear to have many duplicate or garbage messages.

### 3. Shell Escaping in zsh

macOS default shell is zsh. The `!=` operator in SQL strings can be misinterpreted:

```bash
# BAD — zsh may choke on !=
sqlite3 db.db "SELECT * FROM message WHERE text != ''"

# GOOD — works in all shells
sqlite3 db.db "SELECT * FROM message WHERE length(text) > 0"
```

### 4. Date Conversion Gotchas

**Forgetting `'localtime'`**:

```sql
-- Returns UTC (wrong for display)
datetime(m.date/1000000000 + 978307200, 'unixepoch')

-- Returns local time (correct)
datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime')
```

**Comparing dates**: Always compare in the `datetime()` domain, not raw integers:

```sql
-- GOOD
WHERE datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') >= '2026-01-01'

-- BAD (raw integer comparison is error-prone)
WHERE m.date >= 788918400000000000
```

### 5. Group Chats vs 1:1

Group chats have a different `chat_identifier` format (often `chat` + number). To find group chats:

```sql
SELECT chat_identifier, display_name
FROM chat
WHERE chat_identifier LIKE 'chat%'
```

Group chat messages may have different `handle_id` values for each participant. Use the `handle` table to resolve sender identity in group chats.

### 6. Database Locking

`chat.db` is actively used by Messages.app. Always open read-only:

```python
# Python — read-only URI mode
conn = sqlite3.connect("file:path/to/chat.db?mode=ro", uri=True)
```

```bash
# sqlite3 CLI — inherently read-only for SELECT queries
sqlite3 ~/Library/Messages/chat.db "SELECT ..."
```

Never attempt to write to `chat.db` — it will corrupt the database.
