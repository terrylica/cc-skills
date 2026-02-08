**Skill**: [iMessage Query](../SKILL.md)

# Reusable SQL Query Patterns

All queries use parameterized placeholders. Replace `<CHAT_IDENTIFIER>` with actual phone number or email.

**Database**: `~/Library/Messages/chat.db`
**Tool**: `sqlite3` (pre-installed on macOS)

---

## 1. List All Conversations

Find chat identifiers for all conversations, sorted by message count.

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT c.chat_identifier, c.display_name, COUNT(cmj.message_id) as msg_count
   FROM chat c
   JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
   GROUP BY c.ROWID
   ORDER BY msg_count DESC
   LIMIT 30"
```

## 2. Get Conversation Thread (text column only)

Simple retrieval — misses messages stored in `attributedBody`.

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
   ORDER BY m.date ASC"
```

## 3. Keyword Search Across All Chats

Search for a keyword in all conversations.

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT c.chat_identifier,
          datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as ts,
          CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Them' END as sender,
          m.text
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   WHERE m.text LIKE '%<KEYWORD>%'
   AND m.associated_message_type = 0
   ORDER BY m.date DESC
   LIMIT 50"
```

**Note**: This only searches the `text` column. To search `attributedBody` content, use the decode script with `--search`.

## 4. Message Statistics

Get counts by sender, message type, and date range for a conversation.

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT
     COUNT(*) as total,
     SUM(CASE WHEN m.is_from_me = 1 THEN 1 ELSE 0 END) as sent,
     SUM(CASE WHEN m.is_from_me = 0 THEN 1 ELSE 0 END) as received,
     SUM(CASE WHEN m.text IS NOT NULL AND length(m.text) > 0 THEN 1 ELSE 0 END) as has_text,
     SUM(CASE WHEN (m.text IS NULL OR length(m.text) = 0)
               AND m.attributedBody IS NOT NULL
               AND length(m.attributedBody) > 100
               AND m.cache_has_attachments = 0 THEN 1 ELSE 0 END) as hidden_in_attributed_body,
     SUM(CASE WHEN m.cache_has_attachments = 1 THEN 1 ELSE 0 END) as with_attachments,
     MIN(datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime')) as first_msg,
     MAX(datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime')) as last_msg
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
   AND m.associated_message_type = 0"
```

The `hidden_in_attributed_body` count shows how many messages would be missed without the decode script.

## 5. Find Messages with Attachments

List messages that have file attachments (images, voice memos, documents).

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as ts,
          CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Them' END as sender,
          a.mime_type,
          a.transfer_name,
          a.total_bytes,
          m.text
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   JOIN message_attachment_join maj ON m.ROWID = maj.message_id
   JOIN attachment a ON maj.attachment_id = a.ROWID
   WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
   AND m.associated_message_type = 0
   ORDER BY m.date DESC
   LIMIT 30"
```

## 6. Identify Messages Needing Decode

Find messages where text is NULL but attributedBody contains recoverable content.

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as ts,
          CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Them' END as sender,
          length(m.attributedBody) as attr_len,
          m.cache_has_attachments
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
   AND (m.text IS NULL OR length(m.text) = 0)
   AND m.attributedBody IS NOT NULL
   AND length(m.attributedBody) > 100
   AND m.associated_message_type = 0
   AND m.cache_has_attachments = 0
   ORDER BY m.date DESC
   LIMIT 50"
```

These are the messages that require the Python decode script to extract text.

## 7. Conversation Window (Time Range)

Get messages in a specific time window.

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as ts,
          CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Them' END as sender,
          m.text
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
   AND datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime')
       BETWEEN '<START_DATE>' AND '<END_DATE>'
   AND length(m.text) > 0
   AND m.associated_message_type = 0
   ORDER BY m.date ASC"
```

Date format: `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS`

## 8. All Messages Including Both Parties (Full Thread with Context)

Get a complete interleaved thread showing both sides, including empty-text markers.

```sql
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as ts,
          CASE WHEN m.is_from_me = 1 THEN 'Me' ELSE 'Them' END as sender,
          CASE
            WHEN length(m.text) > 0 THEN m.text
            WHEN m.cache_has_attachments = 1 THEN '[attachment]'
            WHEN m.attributedBody IS NOT NULL AND length(m.attributedBody) > 100 THEN '[needs decode]'
            ELSE '[empty]'
          END as content
   FROM message m
   JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
   JOIN chat c ON cmj.chat_id = c.ROWID
   WHERE c.chat_identifier = '<CHAT_IDENTIFIER>'
   AND m.associated_message_type = 0
   ORDER BY m.date ASC"
```

Messages showing `[needs decode]` should be processed with the Python decode script.
