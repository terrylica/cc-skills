#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# ///
"""
Decode iMessage messages from macOS chat.db, including NSAttributedString binary blobs.

Many iOS messages store text in the `attributedBody` column (as NSAttributedString binary)
rather than the `text` column. This script handles both transparently.

Usage:
    python3 decode_attributed_body.py --chat "+1234567890" --limit 50
    python3 decode_attributed_body.py --chat "user@example.com" --search "keyword"
    python3 decode_attributed_body.py --chat "+1234567890" --after "2026-01-01" --before "2026-02-01"
    python3 decode_attributed_body.py --chat "+1234567890" --sender me
    python3 decode_attributed_body.py --chat "+1234567890" --sender them

Output: timestamp|sender|text (pipe-delimited, one message per line)
        Messages decoded from attributedBody are marked with [decoded] prefix.
"""

import argparse
import os
import re
import sqlite3
import sys

# Apple epoch offset: seconds between Unix epoch (1970-01-01) and Apple epoch (2001-01-01)
APPLE_EPOCH_OFFSET = 978307200

# Framework class names to filter out when decoding NSAttributedString
NS_FRAMEWORK_CLASSES = frozenset([
    "NSDictionary",
    "NSMutableDictionary",
    "NSMutableParagraphStyle",
    "NSParagraphStyle",
    "NSObject",
    "NSColor",
    "NSFont",
    "NSString",
    "NSMutableString",
    "NSAttributedString",
    "NSMutableAttributedString",
    "NSNumber",
    "NSValue",
    "NSArray",
    "NSMutableArray",
    "NSData",
    "NSURL",
    "NSRange",
    "streamtyped",
    "kIMMessagePartAttributeName",
    "__kIMMessagePartAttributeName",
])


def decode_attributed_body(attr_body: bytes) -> str | None:
    """Decode NSAttributedString binary blob to plain text.

    Strategy:
    1. Decode bytes as UTF-8 (ignoring errors)
    2. Split on null bytes
    3. Filter out Apple framework class names and short fragments
    4. Return the longest meaningful text chunk
    5. Clean up trailing iMessage artifacts
    """
    if not attr_body:
        return None

    try:
        decoded = attr_body.decode("utf-8", errors="ignore")
    except (UnicodeDecodeError, AttributeError):
        return None

    # Split on null bytes
    chunks = re.split(r"\x00+", decoded)

    # Filter meaningful chunks
    meaningful = []
    for chunk in chunks:
        chunk = chunk.strip()
        if len(chunk) < 4:
            continue
        # Skip Apple framework class names
        if any(cls in chunk for cls in NS_FRAMEWORK_CLASSES):
            continue
        meaningful.append(chunk)

    if not meaningful:
        return None

    # Take the longest meaningful chunk (most likely the actual message text)
    text = max(meaningful, key=len)

    # Clean up common artifacts
    # Strip trailing iMessage marker (iI followed by 0-5 chars at end)
    text = re.sub(r"iI.{0,5}$", "", text).strip()
    # Strip leading + followed by single non-space char (length prefix artifact)
    text = re.sub(r"^\+.", "", text).strip()

    # Final sanity check
    if len(text) < 2:
        return None

    return text


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

    args = parser.parse_args()

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


def _print_messages(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Print messages with attributedBody decoding."""
    query, params = build_query(args)
    cur = conn.cursor()
    cur.execute(query, params)

    search_lower = args.search.lower() if args.search else None
    count = 0
    decoded_count = 0

    for ts, is_from_me, text, attr_body in cur:
        sender = args.me_label if is_from_me else args.them_label
        content = None
        is_decoded = False

        # Try text column first
        if text and len(text.strip()) > 0:
            content = text.strip()
        # Fall back to attributedBody decoding
        elif attr_body and len(attr_body) > 50:
            decoded = decode_attributed_body(attr_body)
            if decoded:
                content = f"[decoded] {decoded}"
                is_decoded = True

        if not content:
            continue

        # Apply keyword search filter
        if search_lower and search_lower not in content.lower():
            continue

        print(f"{ts}|{sender}|{content}")
        count += 1
        if is_decoded:
            decoded_count += 1

    # Print summary to stderr
    if count > 0:
        print(f"\n--- {count} messages ({decoded_count} decoded from attributedBody) ---", file=sys.stderr)
    else:
        print(f"No messages found for chat: {args.chat}", file=sys.stderr)


if __name__ == "__main__":
    main()
