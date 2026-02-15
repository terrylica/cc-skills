#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pytypedstream"]
# ///
"""
Decode iMessage messages from macOS chat.db, including NSAttributedString binary blobs.

Many iOS messages store text in the `attributedBody` column (as NSAttributedString binary)
rather than the `text` column. This script handles both transparently.

Decoder strategy (v3 — 3-tier with pytypedstream):
  1. pytypedstream (Unarchiver) — proper typedstream deserialization, handles all formats
  2. Multi-format binary — 0x2B length-prefix with 1-4 byte lengths, 0x4F, 0x49 fallbacks
  3. NSString marker — split on b"NSString" + length-prefix (v2 legacy)

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


def build_query(args: argparse.Namespace) -> tuple[str, list]:
    """Build SQL query from command-line arguments."""
    params: list = []

    select = f"""
        SELECT
            datetime(m.date/1000000000 + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') as ts,
            m.is_from_me,
            m.text,
            m.attributedBody
        FROM message m
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
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
    """Print conversation statistics."""
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

    total, sent, received, has_text, hidden_text, attachments, first_msg, last_msg = row

    print(f"Chat: {args.chat}")
    print(f"Period: {first_msg} to {last_msg}")
    print(f"Total messages: {total}")
    print(f"  Sent: {sent}")
    print(f"  Received: {received}")
    print(f"  With text column: {has_text}")
    print(f"  Hidden in attributedBody: {hidden_text}")
    print(f"  With attachments: {attachments}")
    print(f"  Decode coverage: {((has_text + hidden_text) / total * 100):.1f}%")


def _resolve_message(ts, is_from_me, text, attr_body, me_label, them_label):
    """Resolve a raw DB row into a message dict. Returns None if no content."""
    sender_label = me_label if is_from_me else them_label
    sender_key = "me" if is_from_me else "them"
    content = None
    is_decoded = False

    if text and len(text.strip()) > 0:
        content = text.strip()
    elif attr_body and len(attr_body) > 50:
        decoded = decode_attributed_body(attr_body)
        if decoded:
            content = decoded
            is_decoded = True

    if not content:
        return None

    return {
        "ts": ts,
        "sender_label": sender_label,
        "sender": sender_key,
        "is_from_me": bool(is_from_me),
        "text": content,
        "decoded": is_decoded,
    }


def _print_messages(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Print messages with attributedBody decoding."""
    query, params = build_query(args)
    cur = conn.cursor()
    cur.execute(query, params)

    # Collect all resolved messages into a list
    messages = []
    for ts, is_from_me, text, attr_body in cur:
        msg = _resolve_message(ts, is_from_me, text, attr_body, args.me_label, args.them_label)
        if msg:
            messages.append(msg)

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
        print(f"{msg['ts']}|{msg['sender_label']}|{prefix}{msg['text']}")
        count += 1
        if msg["decoded"]:
            decoded_count += 1

    # Print summary to stderr
    if count > 0:
        summary = f"--- {count} messages ({decoded_count} decoded from attributedBody)"
        if match_indices:
            summary += f", {len(match_indices)} matches"
        summary += " ---"
        print(f"\n{summary}", file=sys.stderr)
    else:
        print(f"No messages found for chat: {args.chat}", file=sys.stderr)


def _export_ndjson(path: str, messages: list[dict], indices: list[int]) -> None:
    """Export messages to NDJSON (.jsonl) file."""
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
            }
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
            count += 1

    print(f"Exported {count} messages to {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
