**Skill**: [iMessage Query](../SKILL.md)

# iMessage Database Schema Reference

The macOS iMessage database is located at `~/Library/Messages/chat.db` (SQLite3). Requires Full Disk Access.

## Core Tables

### `message`

The primary table. One row per message (including tapback reactions as separate rows).

| Column                    | Type    | Description                                                               |
| ------------------------- | ------- | ------------------------------------------------------------------------- |
| `ROWID`                   | INTEGER | Primary key                                                               |
| `text`                    | TEXT    | Message text (NULL for dictated/rich messages — check `attributedBody`)   |
| `attributedBody`          | BLOB    | NSAttributedString binary — contains text for dictated/formatted messages |
| `date`                    | INTEGER | Nanoseconds since Apple epoch (2001-01-01 00:00:00 UTC)                   |
| `is_from_me`              | INTEGER | 1 = sent, 0 = received                                                    |
| `cache_has_attachments`   | INTEGER | 1 = has file/image/voice attachment                                       |
| `associated_message_type` | INTEGER | 0 = normal message, non-zero = tapback/reaction                           |
| `handle_id`               | INTEGER | FK to `handle` table (sender/recipient)                                   |
| `service`                 | TEXT    | "iMessage" or "SMS"                                                       |
| `is_read`                 | INTEGER | 1 = read                                                                  |
| `is_delivered`            | INTEGER | 1 = delivered                                                             |
| `is_sent`                 | INTEGER | 1 = sent successfully                                                     |
| `subject`                 | TEXT    | Message subject (rarely used in iMessage)                                 |
| `group_title`             | TEXT    | Group chat name (if changed by this message)                              |

### `chat`

One row per conversation (1:1 or group).

| Column            | Type    | Description                                      |
| ----------------- | ------- | ------------------------------------------------ |
| `ROWID`           | INTEGER | Primary key                                      |
| `chat_identifier` | TEXT    | Phone number (e.g., `+1234567890`) or email      |
| `display_name`    | TEXT    | User-set display name (often NULL for 1:1 chats) |
| `service_name`    | TEXT    | "iMessage" or "SMS"                              |
| `group_id`        | TEXT    | Group chat identifier                            |

### `chat_message_join`

Many-to-many join between chats and messages.

| Column         | Type    | Description                    |
| -------------- | ------- | ------------------------------ |
| `chat_id`      | INTEGER | FK to `chat.ROWID`             |
| `message_id`   | INTEGER | FK to `message.ROWID`          |
| `message_date` | INTEGER | Denormalized date for indexing |

### `handle`

Contact identifiers (phone numbers, emails).

| Column    | Type    | Description                     |
| --------- | ------- | ------------------------------- |
| `ROWID`   | INTEGER | Primary key                     |
| `id`      | TEXT    | Phone number or email           |
| `service` | TEXT    | "iMessage" or "SMS"             |
| `country` | TEXT    | Country code (e.g., "us", "ca") |

### `attachment`

File attachments (images, voice memos, documents).

| Column          | Type    | Description                                                    |
| --------------- | ------- | -------------------------------------------------------------- |
| `ROWID`         | INTEGER | Primary key                                                    |
| `filename`      | TEXT    | Full path on disk (often `~/Library/Messages/Attachments/...`) |
| `mime_type`     | TEXT    | MIME type (e.g., `image/jpeg`, `audio/amr`)                    |
| `transfer_name` | TEXT    | Original filename                                              |
| `total_bytes`   | INTEGER | File size                                                      |
| `created_date`  | INTEGER | Apple epoch nanoseconds                                        |

### `message_attachment_join`

Many-to-many join between messages and attachments.

| Column          | Type    | Description              |
| --------------- | ------- | ------------------------ |
| `message_id`    | INTEGER | FK to `message.ROWID`    |
| `attachment_id` | INTEGER | FK to `attachment.ROWID` |

---

## Date Formula

iMessage uses **nanoseconds since Apple epoch (2001-01-01 00:00:00 UTC)**.

### Convert to human-readable local time

```sql
datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime')
```

### Breakdown

| Component             | Purpose                                       |
| --------------------- | --------------------------------------------- |
| `m.date / 1000000000` | Nanoseconds → seconds                         |
| `+ 978307200`         | Apple epoch (2001) → Unix epoch (1970) offset |
| `'unixepoch'`         | Tell SQLite the input is a Unix timestamp     |
| `'localtime'`         | Convert UTC → local timezone                  |

### The magic number 978307200

```python
from datetime import datetime
# Seconds between 1970-01-01 and 2001-01-01
(datetime(2001, 1, 1) - datetime(1970, 1, 1)).total_seconds()
# = 978307200.0
```

### Filter by date

To find messages after a specific date, compare in the datetime domain:

```sql
WHERE datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') >= '2026-01-01'
```

---

## `associated_message_type` Values

| Value     | Meaning                    |
| --------- | -------------------------- |
| 0         | Normal message             |
| 2000      | Loved                      |
| 2001      | Liked                      |
| 2002      | Disliked                   |
| 2003      | Laughed                    |
| 2004      | Emphasized                 |
| 2005      | Questioned                 |
| 3000–3005 | Removal of above reactions |

**Always filter `associated_message_type = 0`** to get only actual messages.
