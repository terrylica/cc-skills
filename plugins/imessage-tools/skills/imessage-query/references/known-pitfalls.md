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

| #   | Pitfall                       | Symptom                                                                      | Solution                                                                                                                                                                                                                |
| --- | ----------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `text` column NULL            | Message appears empty/missing                                                | Check `attributedBody` — use decode script                                                                                                                                                                              |
| 2   | NSAttributedString binary     | Raw binary garbage in output                                                 | **v3**: 3-tier decoder (pytypedstream → multi-format binary → NSString marker)                                                                                                                                          |
| 3   | Tapback reactions as messages | Duplicate/phantom messages                                                   | Filter with `associated_message_type = 0`                                                                                                                                                                               |
| 4   | `iI` suffix artifacts         | Decoded text ends with `iI` + random chars                                   | **v1 only** — v2 length-prefix extraction doesn't include trailing artifacts                                                                                                                                            |
| 5   | `+` length prefix             | Decoded text starts with `+` then a single char                              | **v1 only** — v2 length-prefix extraction doesn't include leading artifacts                                                                                                                                             |
| 6   | Wrong timezone                | Timestamps off by hours                                                      | Add `'localtime'` modifier to `datetime()`                                                                                                                                                                              |
| 7   | zsh `!=` escaping             | Shell error when using `!=` in SQL                                           | Use `length(m.text) > 0` instead of `m.text != ''`                                                                                                                                                                      |
| 8   | `kIMMessagePartAttributeName` | Garbage metadata text in decoded output                                      | These are tapback metadata — filter by `associated_message_type = 0`                                                                                                                                                    |
| 9   | Voice vs dictated confusion   | Both have NULL `text`                                                        | Voice: `cache_has_attachments = 1`. Dictated: `cache_has_attachments = 0` + `attributedBody` > 100 bytes                                                                                                                |
| 10  | `NSValue` in decoded text     | Short garbage strings like "NSValue"                                         | These are tapback/reaction attribute values — already filtered by `associated_message_type = 0`                                                                                                                         |
| 11  | Short messages invisible      | Messages <50 chars return `None` from decode                                 | **FIXED v2/v3** — replaced null-split decoder; v3 uses pytypedstream for reliable decode                                                                                                                                |
| 12  | pytypedstream module name     | `ImportError` when importing `pytypedstream`                                 | Package = `pytypedstream` (PyPI), module = `typedstream`. Use `from typedstream import Unarchiver`                                                                                                                      |
| 13  | Unarchiver not iterable       | `TypeError` iterating `Unarchiver.from_data()`                               | Must call `.decode_all()` first — returns `list[TypedValue]`, not an iterator                                                                                                                                           |
| 14  | Retracted messages look empty | NULL `text`, NULL `attributedBody`, 0 attachments — looks like voice message | Check `date_edited > 0`: these are unsent/retracted messages with content wiped by iOS. NOT recoverable. NOT admissible — both parties know they were retracted. `message_summary_info.otr.le` records original length. |

---

## Detailed Explanations

### 1. Decoding NSAttributedString Binary

The `attributedBody` column contains a serialized `NSAttributedString` object. The binary format includes:

- A `streamtyped` header
- The actual text content (after a `b"NSString"` marker + 5-byte preamble + length prefix)
- Attribute dictionaries (font, color, paragraph style)
- Apple framework class names as markers

**Decode strategy v3** (used by the bundled script — 3-tier with pytypedstream):

```python
# Tier 1: pytypedstream (proper deserialization, most reliable)
from typedstream import Unarchiver
result = Unarchiver.from_data(attr_body).decode_all()
# Navigate: TypedValue.value → GenericArchivedObject.contents → NSMutableString.value → str

# Tier 2: Multi-format binary (0x2B/0x4F/0x49 markers with variable-length encoding)
# Ported from macos-messages — handles 4 encoding formats, zero external deps

# Tier 3: NSString marker + length-prefix (v2 legacy, LangChain approach)
# Split on b"NSString", skip 5-byte preamble, read length — simplest last resort
```

> **Why v3?** The v2 approach (NSString marker only) fixed the v1 short-message bug but only handles one encoding format. The v3 3-tier strategy handles all known formats via pytypedstream (tier 1), falls through to multi-format binary parsing (tier 2), and keeps the v2 approach as a last resort (tier 3). See [cross-repo-analysis.md](./cross-repo-analysis.md) for full comparison.

> **Why v2 over v1?** The original v1 approach (null-byte split + framework class name filtering) silently dropped short messages where the text and NS class names coexisted in the same chunk. See pitfall #11.

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

### 7. Short Messages Invisible to v1 Decoder (FIXED)

**Pitfall #11** — Messages under ~50 characters returned `None` from the original v1 decode function. Searching for known keywords returned "No messages found" despite messages existing in the DB.

**Root cause**: The v1 null-byte split approach puts actual message text in the same chunk as NSString/NSDictionary class markers. The framework class filter (`any(cls in chunk for cls in NS_FRAMEWORK_CLASSES)`) then discards the entire chunk — throwing out the message text along with the metadata.

**Affected messages** (discovered during Tiemar recruitment case, 2026-02-13):

- "She gave me these references" + phone numbers
- "The current office gave her a glaring reference"
- "Yes", "Cool.", "Never", and other short messages

**Solution**: Replaced with NSString marker + length-prefix extraction (v2, 2026-02-14), then upgraded to 3-tier decoder with pytypedstream (v3, 2026-02-14). No filtering needed — pytypedstream does proper deserialization, and the length-prefix fallbacks give exact text boundaries.

**Anti-pattern**: Never filter decoded chunks by checking if they _contain_ framework class names. The message text and class names coexist in the same binary region for short messages.

### 8. pytypedstream Module Name Mismatch

**Pitfall #12** — `from pytypedstream import Unarchiver` raises `ImportError`. The PyPI package name (`pytypedstream`) differs from the installed module name (`typedstream`).

**Solution**: `from typedstream import Unarchiver` — always import from `typedstream`, not `pytypedstream`.

### 9. Unarchiver Object Not Iterable

**Pitfall #13** — `for value in Unarchiver.from_data(blob):` raises `TypeError`. The `Unarchiver` object is not directly iterable.

**Solution**: Call `.decode_all()` first: `Unarchiver.from_data(blob).decode_all()` returns a `list[TypedValue]` that you can iterate.

### 10. Retracted Messages Mistaken for Voice Messages or Missing Content

**Pitfall #14** — Messages with NULL `text`, NULL/empty `attributedBody`, and `cache_has_attachments = 0` look identical to the "voice message" pattern from pitfall #9. Previous sessions incorrectly classified these as voice messages, inflating the "undecodable" count.

**Root cause**: When a sender uses "Undo Send" (iOS 16+), the message row stays in the database but both `text` and `attributedBody` are wiped. The `date_edited` field is set to the retraction timestamp (typically 3–64 seconds after `date`).

**How to detect**:

```sql
-- Retracted messages (NOT voice, NOT missing content — intentionally unsent)
SELECT datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as sent,
       datetime(m.date_edited/1000000000 + 978307200, 'unixepoch', 'localtime') as retracted,
       (m.date_edited - m.date) / 1000000000 as delay_secs
FROM message m
WHERE m.date_edited > 0
AND (m.text IS NULL OR length(m.text) = 0)
AND (m.attributedBody IS NULL OR length(m.attributedBody) < 50)
```

**Original text length**: The `message_summary_info` blob (a plist) contains `otr.0.le` which records the original text length before retraction. This confirms the message had real content, but that content is unrecoverable.

**Admissibility**: Retracted messages are NOT admissible in conversation logs or NDJSON exports. Both parties saw the retraction notification. The decode script correctly excludes them (no `text` or `attributedBody` means `_resolve_message()` returns `None`).

**Anti-pattern**: Never assume that NULL `text` + NULL `attributedBody` = voice message. Always check `date_edited` first — if set, it's a retracted message, not a voice message.
