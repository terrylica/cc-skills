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
    python3 decode_attributed_body.py --chat "+1234567890" --search "keyword" --context 3
    python3 decode_attributed_body.py --chat "+1234567890" --after "2026-02-01" --export thread.jsonl

Output: timestamp|sender|text (pipe-delimited, one message per line)
        Messages decoded from attributedBody are marked with [decoded] prefix.
"""

import argparse
import json
import os
import sqlite3
import sys

# Apple epoch offset: seconds between Unix epoch (1970-01-01) and Apple epoch (2001-01-01)
APPLE_EPOCH_OFFSET = 978307200


def decode_attributed_body(attr_body: bytes) -> str | None:
    """Decode NSAttributedString binary blob to plain text.

    Uses the NSString marker + length-prefix approach (same algorithm as
    LangChain's iMessage loader). The binary format stores text after a
    b"NSString" marker, a 5-byte preamble, and a variable-length field.
    """
    if not attr_body:
        return None
    try:
        parts = attr_body.split(b"NSString")
        if len(parts) < 2:
            return None
        content = parts[1][5:]  # skip 5-byte preamble after NSString
        length = content[0]
        start = 1
        if content[0] == 129:  # 0x81 = 2-byte length follows (little-endian)
            length = int.from_bytes(content[1:3], "little")
            start = 3
        text = content[start:start + length].decode("utf-8", errors="ignore").strip()
        if len(text) < 1:
            return None
        return text
    except (IndexError, ValueError):
        return None


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
