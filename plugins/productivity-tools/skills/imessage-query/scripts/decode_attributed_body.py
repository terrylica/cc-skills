#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pytypedstream"]
# ///
# ADR: references/evolution-log.md (v1→v2→v3→v4)
# Issue: references/known-pitfalls.md (#1-#14)
# FILE-SIZE-OK: single-file script by design (self-contained for skill distribution)
"""
Decode iMessage messages from macOS chat.db, including NSAttributedString binary blobs.

Many iOS messages store text in the `attributedBody` column (as NSAttributedString binary)
rather than the `text` column. This script handles both transparently.

Decoder strategy (v3 — 3-tier with pytypedstream):
  1. pytypedstream (Unarchiver) — proper typedstream deserialization, handles all formats
  2. Multi-format binary — 0x2B length-prefix with 1-4 byte lengths, 0x4F, 0x49 fallbacks
  3. NSString marker — split on b"NSString" + length-prefix (v2 legacy)

Native pitfall protections (v4):
  - Retracted messages (Undo Send): detected via date_retracted, excluded from output
  - Edited messages: date_edited tracked, flagged in output
  - Audio/voice messages: is_audio_message column distinguishes from empty text
  - Inline quotes: thread_originator_guid resolved to quoted message text
  - Attachments: type/filename surfaced for attachment-only messages
  - Message effects: expressive_send_style_id captured (slam, loud, gentle, invisible ink)
  - Service type: iMessage vs SMS distinguished

Usage:
    python3 decode_attributed_body.py --chat "+1234567890" --limit 50
    python3 decode_attributed_body.py --chat "user@example.com" --search "keyword"
    python3 decode_attributed_body.py --chat "+1234567890" --after "2026-01-01" --before "2026-02-01"
    python3 decode_attributed_body.py --chat "+1234567890" --sender me
    python3 decode_attributed_body.py --chat "+1234567890" --sender them
    python3 decode_attributed_body.py --chat "+1234567890" --search "keyword" --context 3
    python3 decode_attributed_body.py --chat "+1234567890" --after "2026-02-01" --export thread.jsonl

Output: timestamp|sender|text (pipe-delimited, one message per line)
        Messages decoded from attributedBody are marked with [decoded] prefix.
"""

import argparse
import json
import os
import re
import sqlite3
import sys

# Apple epoch offset: seconds between Unix epoch (1970-01-01) and Apple epoch (2001-01-01)
APPLE_EPOCH_OFFSET = 978307200

# Expressive send style IDs → human-readable names
_SEND_EFFECTS = {
    "com.apple.MobileSMS.expressivesend.impact": "slam",
    "com.apple.MobileSMS.expressivesend.gentle": "gentle",
    "com.apple.MobileSMS.expressivesend.loud": "loud",
    "com.apple.MobileSMS.expressivesend.invisibleink": "invisible_ink",
}

# Try to import pytypedstream (preferred decoder)
try:
    from typedstream import Unarchiver

    _HAS_TYPEDSTREAM = True
except ImportError:
    _HAS_TYPEDSTREAM = False


def _decode_via_typedstream(attr_body: bytes) -> str | None:
    """Tier 1: Decode via pytypedstream Unarchiver (proper typedstream deserialization).

    Source: pytypedstream package (same approach as imessage-conversation-analyzer).
    Handles all message lengths, emoji, and rich formatting correctly.
    """
    try:
        result = Unarchiver.from_data(attr_body).decode_all()
        for tv in result:
            obj = tv.value
            if hasattr(obj, "contents"):
                for item in obj.contents:
                    val = item.value
                    # NSMutableString wraps a str
                    if hasattr(val, "value") and isinstance(val.value, str):
                        text = val.value.strip()
                        return text if text else None
                    elif isinstance(val, str):
                        text = val.strip()
                        return text if text else None
    except (IndexError, ValueError, UnicodeDecodeError, TypeError, OSError):
        return None
    return None


def _decode_via_multiformat(attr_body: bytes) -> str | None:
    """Tier 2: Multi-format binary length-prefix decoder (from macos-messages).

    Handles 0x2B (+) marker with 1-4 byte lengths, 0x4F extended encoding,
    and 0x49 (I) legacy format. No external dependencies.
    """
    try:
        text_section = attr_body.split(b"NSString")[1].split(b"NSDictionary")[0]

        # Try + marker (0x2B) — most common
        plus_idx = text_section.find(b"+")
        if plus_idx != -1 and plus_idx + 2 < len(text_section):
            marker = text_section[plus_idx + 1]
            if marker < 0x80:
                length, start = marker, plus_idx + 2
            elif marker == 0x81 and plus_idx + 4 <= len(text_section):
                length = int.from_bytes(text_section[plus_idx + 2 : plus_idx + 4], "little")
                start = plus_idx + 4
            elif marker == 0x82 and plus_idx + 5 <= len(text_section):
                length = int.from_bytes(text_section[plus_idx + 2 : plus_idx + 5], "little")
                start = plus_idx + 5
            elif marker == 0x83 and plus_idx + 6 <= len(text_section):
                length = int.from_bytes(text_section[plus_idx + 2 : plus_idx + 6], "little")
                start = plus_idx + 6
            else:
                length, start = 0, 0

            if length > 0 and start + length <= len(text_section):
                text = text_section[start : start + length].decode("utf-8", errors="ignore").strip()
                if text:
                    return text

        # Try 0x4F extended length encoding
        for i in range(len(text_section) - 2):
            if text_section[i] != 0x4F:
                continue
            size_marker = text_section[i + 1]
            if size_marker == 0x10:
                length, start = text_section[i + 2], i + 3
            elif size_marker == 0x11 and i + 4 <= len(text_section):
                length = int.from_bytes(text_section[i + 2 : i + 4], "big")
                start = i + 4
            elif size_marker == 0x12 and i + 6 <= len(text_section):
                length = int.from_bytes(text_section[i + 2 : i + 6], "big")
                start = i + 6
            else:
                continue
            if 0 < length < 100000 and start + length <= len(text_section):
                text = text_section[start : start + length].decode("utf-8", errors="ignore").strip()
                if text:
                    return text

        # Try legacy I marker (0x49) — 4-byte big-endian length
        i_idx = text_section.find(b"I")
        if i_idx != -1 and i_idx + 5 < len(text_section):
            length = int.from_bytes(text_section[i_idx + 1 : i_idx + 5], "big")
            if 0 < length < 100000 and i_idx + 5 + length <= len(text_section):
                text = text_section[i_idx + 5 : i_idx + 5 + length].decode("utf-8", errors="ignore").strip()
                if text:
                    return text
    except (IndexError, ValueError):
        pass

    # Heuristic fallback: find readable text sequences after NSString
    try:
        if b"streamtyped" in attr_body:
            parts = attr_body.split(b"NSString")
            if len(parts) > 1:
                matches = re.findall(rb"[\x20-\x7e\xc0-\xff]{4,}", parts[1])
                for m in matches:
                    decoded = m.decode("utf-8", errors="ignore").strip()
                    if decoded and not decoded.startswith(("NS", "{")):
                        return decoded
    except (IndexError, ValueError, UnicodeDecodeError):
        return None

    return None


def _decode_via_nsstring_marker(attr_body: bytes) -> str | None:
    """Tier 3: NSString marker + length-prefix (v2 legacy, LangChain approach).

    Simplest approach — split on b"NSString", skip 5-byte preamble, read length.
    Kept as last resort for unusual blob formats.
    """
    try:
        parts = attr_body.split(b"NSString")
        if len(parts) < 2:
            return None
        content = parts[1][5:]
        length = content[0]
        start = 1
        if content[0] == 0x81:
            length = int.from_bytes(content[1:3], "little")
            start = 3
        text = content[start : start + length].decode("utf-8", errors="ignore").strip()
        return text if text else None
    except (IndexError, ValueError):
        return None


def decode_attributed_body(attr_body: bytes) -> str | None:
    """Decode NSAttributedString binary blob to plain text.

    3-tier strategy:
      1. pytypedstream (Unarchiver) — proper deserialization, most reliable
      2. Multi-format binary — 0x2B/0x4F/0x49 length-prefix parsing
      3. NSString marker — v2 legacy split approach

    Falls through tiers on failure. Returns None if all tiers fail.
    """
    if not attr_body:
        return None

    # Tier 1: pytypedstream (if available)
    if _HAS_TYPEDSTREAM:
        result = _decode_via_typedstream(attr_body)
        if result:
            return result

    # Tier 2: Multi-format binary parsing
    result = _decode_via_multiformat(attr_body)
    if result:
        return result

    # Tier 3: NSString marker (v2 legacy)
    return _decode_via_nsstring_marker(attr_body)


def get_db_path() -> str:
    """Get the iMessage database path."""
    return os.path.join(os.path.expanduser("~"), "Library", "Messages", "chat.db")


def _build_guid_index(conn: sqlite3.Connection, chat_identifier: str) -> dict[str, dict]:
    """Build a GUID → message dict for resolving thread_originator_guid references.

    Returns a dict mapping message GUID to {ts, sender, text} for all messages
    in the chat. Used to look up the quoted message when a reply references it.
    """
    cur = conn.cursor()
    cur.execute(
        f"""
        SELECT
            m.guid,
            datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') as ts,
            m.is_from_me,
            m.text,
            m.attributedBody
        FROM message m
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE c.chat_identifier = ?
        AND m.associated_message_type = 0
        """,
        (chat_identifier,),
    )

    index = {}
    for guid, ts, is_from_me, text, attr_body in cur:
        content = None
        if text and len(text.strip()) > 0:
            content = text.strip()
        elif attr_body and len(attr_body) > 50:
            content = decode_attributed_body(attr_body)

        if content:
            index[guid] = {
                "ts": ts,
                "sender": "me" if is_from_me else "them",
                "text": content,
            }

    return index


def build_query(args: argparse.Namespace) -> tuple[str, list]:
    """Build SQL query from command-line arguments.

    Selects all columns needed for comprehensive message extraction:
    - Core: ts, is_from_me, text, attributedBody
    - Pitfall protection: date_retracted, date_edited, is_audio_message
    - Context: thread_originator_guid (inline quotes)
    - Metadata: service, expressive_send_style_id, cache_has_attachments
    - Attachment: transfer_name, mime_type (via LEFT JOIN)
    """
    params: list = []

    select = f"""
        SELECT
            datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') as ts,
            m.is_from_me,
            m.text,
            m.attributedBody,
            m.thread_originator_guid,
            m.date_retracted,
            m.date_edited,
            m.is_audio_message,
            m.service,
            m.expressive_send_style_id,
            m.cache_has_attachments,
            a.transfer_name,
            a.mime_type
        FROM message m
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        LEFT JOIN message_attachment_join maj ON m.ROWID = maj.message_id
        LEFT JOIN attachment a ON maj.attachment_id = a.ROWID
        WHERE c.chat_identifier = ?
        AND m.associated_message_type = 0
    """

    params.append(args.chat)

    if args.sender == "me":
        select += " AND m.is_from_me = 1"
    elif args.sender == "them":
        select += " AND m.is_from_me = 0"

    if args.after:
        select += f" AND datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') >= ?"
        params.append(args.after)

    if args.before:
        select += f" AND datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') <= ?"
        params.append(args.before)

    select += " ORDER BY m.date"

    if args.order == "desc":
        select += " DESC"
    else:
        select += " ASC"

    if args.limit:
        select += " LIMIT ?"
        params.append(args.limit)

    return select, params


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query macOS iMessage database with NSAttributedString decoding"
    )
    parser.add_argument(
        "--chat",
        required=True,
        help="Chat identifier (phone number like +1234567890 or email)",
    )
    parser.add_argument(
        "--search",
        help="Filter messages containing this keyword (case-insensitive)",
    )
    parser.add_argument(
        "--after",
        help="Only messages after this date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)",
    )
    parser.add_argument(
        "--before",
        help="Only messages before this date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)",
    )
    parser.add_argument(
        "--sender",
        choices=["me", "them", "both"],
        default="both",
        help="Filter by sender (default: both)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Maximum number of messages to return",
    )
    parser.add_argument(
        "--order",
        choices=["asc", "desc"],
        default="asc",
        help="Sort order by date (default: asc)",
    )
    parser.add_argument(
        "--me-label",
        default="Me",
        help="Label for outgoing messages (default: Me)",
    )
    parser.add_argument(
        "--them-label",
        default="Them",
        help="Label for incoming messages (default: Them)",
    )
    parser.add_argument(
        "--db",
        help="Path to chat.db (default: ~/Library/Messages/chat.db)",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show statistics instead of messages",
    )
    parser.add_argument(
        "--context",
        type=int,
        metavar="N",
        help="Show N messages before and after each --search match",
    )
    parser.add_argument(
        "--export",
        metavar="PATH",
        help="Export messages to NDJSON file (.jsonl) instead of stdout",
    )

    args = parser.parse_args()

    if args.context and not args.search:
        parser.error("--context requires --search")

    db_path = args.db or get_db_path()

    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}", file=sys.stderr)
        print(
            "Ensure Full Disk Access is granted to your terminal application.",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    except sqlite3.OperationalError as e:
        print(f"Error opening database: {e}", file=sys.stderr)
        print(
            "This usually means Full Disk Access is not granted.",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.stats:
        _print_stats(conn, args)
    else:
        _print_messages(conn, args)

    conn.close()


def _print_stats(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Print conversation statistics with retracted/edited/audio breakdown."""
    cur = conn.cursor()
    cur.execute(
        f"""
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN m.is_from_me = 1 THEN 1 ELSE 0 END) as sent,
            SUM(CASE WHEN m.is_from_me = 0 THEN 1 ELSE 0 END) as received,
            SUM(CASE WHEN m.text IS NOT NULL AND length(m.text) > 0 THEN 1 ELSE 0 END) as has_text,
            SUM(CASE WHEN (m.text IS NULL OR length(m.text) = 0)
                      AND m.attributedBody IS NOT NULL
                      AND length(m.attributedBody) > 100
                      AND m.cache_has_attachments = 0 THEN 1 ELSE 0 END) as hidden_text,
            SUM(CASE WHEN m.cache_has_attachments = 1 THEN 1 ELSE 0 END) as attachments,
            SUM(CASE WHEN m.date_retracted > 0
                      OR (m.date_edited > 0
                          AND (m.text IS NULL OR length(m.text) = 0)
                          AND (m.attributedBody IS NULL OR length(m.attributedBody) < 50))
                      THEN 1 ELSE 0 END) as retracted,
            SUM(CASE WHEN m.date_edited > 0 AND m.date_retracted = 0
                      AND (m.text IS NOT NULL AND length(m.text) > 0
                           OR m.attributedBody IS NOT NULL AND length(m.attributedBody) >= 50)
                      THEN 1 ELSE 0 END) as edited,
            SUM(CASE WHEN m.is_audio_message = 1 THEN 1 ELSE 0 END) as audio,
            SUM(CASE WHEN m.thread_originator_guid IS NOT NULL
                      AND length(m.thread_originator_guid) > 0 THEN 1 ELSE 0 END) as threaded,
            SUM(CASE WHEN m.service = 'SMS' THEN 1 ELSE 0 END) as sms,
            MIN(datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime')) as first_msg,
            MAX(datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime')) as last_msg
        FROM message m
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE c.chat_identifier = ?
        AND m.associated_message_type = 0
        """,
        (args.chat,),
    )

    row = cur.fetchone()
    if not row or row[0] == 0:
        print(f"No messages found for chat: {args.chat}", file=sys.stderr)
        return

    (total, sent, received, has_text, hidden_text, attachments,
     retracted, edited, audio, threaded, sms, first_msg, last_msg) = row

    print(f"Chat: {args.chat}")
    print(f"Period: {first_msg} to {last_msg}")
    print(f"Total messages: {total}")
    print(f"  Sent: {sent}")
    print(f"  Received: {received}")
    print(f"  With text column: {has_text}")
    print(f"  Hidden in attributedBody: {hidden_text}")
    print(f"  With attachments: {attachments}")
    print(f"  Retracted (Undo Send): {retracted}")
    print(f"  Edited: {edited}")
    print(f"  Audio messages: {audio}")
    print(f"  Threaded replies: {threaded}")
    if sms:
        print(f"  SMS (not iMessage): {sms}")
    decodable = has_text + hidden_text
    print(f"  Decode coverage: {(decodable / total * 100):.1f}%")
    # Adjusted coverage excludes retracted (content wiped by iOS, not recoverable)
    adjusted_total = total - retracted
    if adjusted_total > 0 and retracted > 0:
        print(f"  Adjusted coverage (excl. retracted): {(decodable / adjusted_total * 100):.1f}%")


def _resolve_message(
    row: tuple,
    me_label: str,
    them_label: str,
    guid_index: dict[str, dict] | None,
) -> dict | None:
    """Resolve a raw DB row into a message dict. Returns None if no content.

    Row columns (from build_query):
        0: ts, 1: is_from_me, 2: text, 3: attributedBody,
        4: thread_originator_guid, 5: date_retracted, 6: date_edited,
        7: is_audio_message, 8: service, 9: expressive_send_style_id,
        10: cache_has_attachments, 11: transfer_name, 12: mime_type

    Pitfall protections:
        - Retracted messages (date_retracted > 0): EXCLUDED — content wiped by iOS,
          not admissible as both parties saw the retraction notification (pitfall #14)
        - Edited messages (date_edited > 0): included but flagged with "edited" field
        - Audio messages (is_audio_message = 1): included with "audio" type, not
          misclassified as empty/missing text (pitfall #9 correction)
    """
    (ts, is_from_me, text, attr_body, thread_guid,
     date_retracted, date_edited, is_audio, service,
     send_style, has_attachments, attachment_name, mime_type) = row

    # Pitfall #14: Retracted messages — EXCLUDE deterministically
    # Both parties know these were retracted. Content is unrecoverable.
    # Detection: date_retracted > 0 (newer iOS), OR date_edited > 0 with
    # wiped content (older iOS used date_edited for Undo Send).
    if date_retracted and date_retracted > 0:
        return None
    if (date_edited and date_edited > 0
            and (not text or len(text.strip()) == 0)
            and (not attr_body or len(attr_body) < 50)):
        return None

    sender_label = me_label if is_from_me else them_label
    sender_key = "me" if is_from_me else "them"
    content = None
    is_decoded = False
    msg_type = "text"

    # Try text column first
    if text and len(text.strip()) > 0:
        content = text.strip()
    # Try attributedBody (pitfall #1, #2, #11)
    elif attr_body and len(attr_body) > 50:
        decoded = decode_attributed_body(attr_body)
        if decoded:
            content = decoded
            is_decoded = True

    # Classify message type for messages with no text content
    if not content:
        # Pitfall #9: is_audio_message is the definitive column for voice messages
        if is_audio and is_audio == 1:
            msg_type = "audio"
            content = "[audio message]"
        elif has_attachments and has_attachments == 1:
            msg_type = "attachment"
            # Surface attachment info instead of silently dropping
            if attachment_name:
                content = f"[attachment: {attachment_name}]"
            elif mime_type:
                content = f"[attachment: {mime_type}]"
            else:
                content = "[attachment]"
        else:
            # No text, no attributedBody, no attachments, not retracted, not audio
            # This should not happen — but don't silently drop, flag it
            return None

    # Build message dict
    msg = {
        "ts": ts,
        "sender_label": sender_label,
        "sender": sender_key,
        "is_from_me": bool(is_from_me),
        "text": content,
        "decoded": is_decoded,
        "type": msg_type,
    }

    # Pitfall #14 complement: flag edited messages (content IS present, but was modified)
    if date_edited and date_edited > 0:
        msg["edited"] = True

    # Service type (iMessage vs SMS)
    if service and service != "iMessage":
        msg["service"] = service

    # Message effects (slam, loud, gentle, invisible ink)
    if send_style:
        effect = _SEND_EFFECTS.get(send_style, send_style)
        msg["effect"] = effect

    # Inline quote context — resolve thread_originator_guid to quoted message
    if thread_guid and guid_index:
        quoted = guid_index.get(thread_guid)
        if quoted:
            msg["reply_to"] = quoted

    return msg


def _print_messages(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Print messages with attributedBody decoding and full metadata extraction."""
    query, params = build_query(args)

    # Build GUID index for resolving inline quotes (thread_originator_guid)
    guid_index = _build_guid_index(conn, args.chat)

    cur = conn.cursor()
    cur.execute(query, params)

    # Collect all resolved messages into a list
    # Track skipped counts for summary
    messages = []
    skipped_retracted = 0
    skipped_empty = 0
    seen_ts = set()  # deduplicate rows from attachment JOIN

    for row in cur:
        ts = row[0]
        is_from_me = row[1]
        text = row[2]
        # Deduplicate: LEFT JOIN on attachments can produce duplicate rows
        # for messages with multiple attachments. Keep only the first.
        dedup_key = (ts, is_from_me, text or "")
        if dedup_key in seen_ts:
            continue
        seen_ts.add(dedup_key)

        msg = _resolve_message(row, args.me_label, args.them_label, guid_index)
        if msg:
            messages.append(msg)
        else:
            # Classify why the message was skipped
            date_retracted_val = row[5]
            date_edited_val = row[6]
            row_text = row[2]
            row_attr = row[3]
            is_retracted = (
                (date_retracted_val and date_retracted_val > 0)
                or (date_edited_val and date_edited_val > 0
                    and (not row_text or len(row_text.strip()) == 0)
                    and (not row_attr or len(row_attr) < 50))
            )
            if is_retracted:
                skipped_retracted += 1
            else:
                skipped_empty += 1

    search_lower = args.search.lower() if args.search else None
    context_n = args.context or 0

    # Determine which messages to output
    if search_lower:
        # Find matching indices
        match_indices = set()
        for i, msg in enumerate(messages):
            if search_lower in msg["text"].lower():
                match_indices.add(i)

        if not match_indices:
            if args.export:
                print(f"No messages matching '{args.search}' for chat: {args.chat}", file=sys.stderr)
            else:
                print(f"No messages found for chat: {args.chat}", file=sys.stderr)
            return

        # Expand with context windows
        output_indices = set()
        for idx in match_indices:
            start = max(0, idx - context_n)
            end = min(len(messages) - 1, idx + context_n)
            for i in range(start, end + 1):
                output_indices.add(i)

        output_indices = sorted(output_indices)
    else:
        output_indices = list(range(len(messages)))
        match_indices = set()

    # Export to NDJSON if requested
    if args.export:
        _export_ndjson(args.export, messages, output_indices)
        return

    # Print to stdout
    count = 0
    decoded_count = 0

    for pos, idx in enumerate(output_indices):
        # Insert context separator for non-contiguous groups
        if context_n and pos > 0 and output_indices[pos] > output_indices[pos - 1] + 1:
            print("--- context ---")

        msg = messages[idx]
        prefix = "[decoded] " if msg["decoded"] else ""
        # Mark search matches with [match] when using --context
        if context_n and idx in match_indices:
            prefix = "[match] " + prefix
        # Show reply context inline
        reply_info = ""
        if "reply_to" in msg:
            rt = msg["reply_to"]
            # Truncate quoted text for display
            quoted_text = rt["text"][:60] + "..." if len(rt["text"]) > 60 else rt["text"]
            reply_info = f" [replying to {rt['sender']}: \"{quoted_text}\"]"
        # Show edit/effect flags
        flags = ""
        if msg.get("edited"):
            flags += " [edited]"
        if msg.get("effect"):
            flags += f" [{msg['effect']}]"
        if msg.get("service"):
            flags += f" [{msg['service']}]"

        print(f"{msg['ts']}|{msg['sender_label']}|{prefix}{msg['text']}{reply_info}{flags}")
        count += 1
        if msg["decoded"]:
            decoded_count += 1

    # Print summary to stderr
    if count > 0:
        summary = f"--- {count} messages ({decoded_count} decoded from attributedBody)"
        if match_indices:
            summary += f", {len(match_indices)} matches"
        if skipped_retracted:
            summary += f", {skipped_retracted} retracted excluded"
        if skipped_empty:
            summary += f", {skipped_empty} empty skipped"
        summary += " ---"
        print(f"\n{summary}", file=sys.stderr)
    else:
        print(f"No messages found for chat: {args.chat}", file=sys.stderr)


def _export_ndjson(path: str, messages: list[dict], indices: list[int]) -> None:
    """Export messages to NDJSON (.jsonl) file with full metadata.

    Each line is a JSON object with:
    - ts, sender, is_from_me, text, decoded — core fields (always present)
    - type — "text", "audio", "attachment" (always present)
    - edited — true if message was edited after sending (optional)
    - service — "SMS" if not iMessage (optional)
    - effect — send effect name like "slam", "loud" (optional)
    - reply_to — {ts, sender, text} of the quoted message (optional)

    Retracted messages are NEVER exported — they are filtered in _resolve_message.
    """
    count = 0
    with open(path, "w", encoding="utf-8") as f:
        for idx in indices:
            msg = messages[idx]
            record = {
                "ts": msg["ts"],
                "sender": msg["sender"],
                "is_from_me": msg["is_from_me"],
                "text": msg["text"],
                "decoded": msg["decoded"],
                "type": msg["type"],
            }
            # Optional metadata — only include if present
            if msg.get("edited"):
                record["edited"] = True
            if msg.get("service"):
                record["service"] = msg["service"]
            if msg.get("effect"):
                record["effect"] = msg["effect"]
            if "reply_to" in msg:
                record["reply_to"] = msg["reply_to"]

            f.write(json.dumps(record, ensure_ascii=False) + "\n")
            count += 1

    print(f"Exported {count} messages to {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
