# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "telethon>=1.42.0",
# ]
# ///
"""Telegram user-account CLI via MTProto (Telethon).

Comprehensive CLI for personal Telegram account operations:
messages, media, search, groups, channels, contacts, downloads.

Credentials fetched from 1Password at runtime.
Multi-profile support: use --profile to switch between accounts.
Sessions persist at ~/.local/share/telethon/<profile>.session.
"""

import argparse
import asyncio
import json
import os
import subprocess
import sys

from pathlib import Path

from telethon import TelegramClient, functions, types
from telethon.tl.types import MessageMediaPhoto, MessageMediaDocument

SESSION_DIR = os.path.expanduser("~/.local/share/telethon")

PROFILES: dict[str, str] = {
    "eon": "iqwxow2iidycaethycub7agfmm",
    "missterryli": "dk456cs3v2fjilppernryoro5a",
}
DEFAULT_PROFILE = "eon"

OP_VAULT = os.environ.get("TELETHON_OP_VAULT", "Claude Automation")


def _op_get(item_id: str, field: str, *, reveal: bool = False) -> str:
    cmd = [
        "op", "item", "get", item_id,
        "--vault", OP_VAULT,
        "--fields", field,
    ]
    if reveal:
        cmd.append("--reveal")
    try:
        return subprocess.check_output(cmd, text=True).strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"Failed to fetch '{field}' from 1Password: {exc}", file=sys.stderr)
        sys.exit(1)


def get_credentials(profile: str) -> tuple[int, str]:
    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")
    if api_id and api_hash:
        return int(api_id), api_hash

    item_id = os.environ.get("TELETHON_OP_UUID") or PROFILES.get(profile)
    if not item_id:
        print(f"Unknown profile '{profile}'. Available: {', '.join(PROFILES)}", file=sys.stderr)
        sys.exit(1)

    api_id_str = _op_get(item_id, "App ID")
    api_hash = _op_get(item_id, "App API Hash", reveal=True)
    return int(api_id_str), api_hash


def session_path(profile: str) -> str:
    return os.path.join(SESSION_DIR, profile)


def parse_entity(value: str) -> str | int:
    return int(value) if value.lstrip("-").isdigit() else value


async def _make_client(profile: str) -> TelegramClient:
    api_id, api_hash = get_credentials(profile)
    os.makedirs(SESSION_DIR, exist_ok=True)
    client = TelegramClient(session_path(profile), api_id, api_hash)
    await client.start()
    return client


# ── Messages ──────────────────────────────────────────────


async def cmd_send(profile: str, recipient: str | int, message: str) -> None:
    if not message:
        print("Error: message cannot be empty", file=sys.stderr)
        sys.exit(1)
    client = await _make_client(profile)
    try:
        await client.send_message(recipient, message)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    print(f"[{profile}] Sent to {recipient}")
    await client.disconnect()


async def cmd_send_file(
    profile: str, recipient: str | int, file_path: str,
    caption: str | None, voice: bool, video_note: bool, force_doc: bool,
) -> None:
    if not os.path.isfile(file_path):
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    client = await _make_client(profile)
    try:
        await client.send_file(
            recipient, file_path,
            caption=caption,
            voice_note=voice,
            video_note=video_note,
            force_document=force_doc,
        )
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    print(f"[{profile}] Sent file to {recipient}: {os.path.basename(file_path)}")
    await client.disconnect()


async def cmd_forward(
    profile: str, from_chat: str | int, msg_ids: list[int], to_chat: str | int,
) -> None:
    client = await _make_client(profile)
    try:
        await client.forward_messages(to_chat, msg_ids, from_peer=from_chat)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    print(f"[{profile}] Forwarded {len(msg_ids)} message(s) → {to_chat}")
    await client.disconnect()


async def cmd_edit(profile: str, chat: str | int, msg_id: int, new_text: str) -> None:
    client = await _make_client(profile)
    try:
        await client.edit_message(chat, msg_id, new_text)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    print(f"[{profile}] Edited message {msg_id} in {chat}")
    await client.disconnect()


async def cmd_delete(profile: str, chat: str | int, msg_ids: list[int], revoke: bool) -> None:
    client = await _make_client(profile)
    try:
        await client.delete_messages(chat, msg_ids, revoke=revoke)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    who = "everyone" if revoke else "self"
    print(f"[{profile}] Deleted {len(msg_ids)} message(s) from {chat} (for {who})")
    await client.disconnect()


async def cmd_pin(profile: str, chat: str | int, msg_id: int, unpin: bool, silent: bool) -> None:
    client = await _make_client(profile)
    try:
        if unpin:
            await client.unpin_message(chat, msg_id if msg_id else None)
            print(f"[{profile}] Unpinned {'all' if not msg_id else f'message {msg_id}'} in {chat}")
        else:
            await client.pin_message(chat, msg_id, notify=not silent)
            print(f"[{profile}] Pinned message {msg_id} in {chat}")
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


# ── Reading & Search ──────────────────────────────────────


async def cmd_read(profile: str, chat_id: str | int, limit: int) -> None:
    client = await _make_client(profile)
    try:
        async for msg in client.iter_messages(chat_id, limit=limit):
            sender = msg.sender
            name = getattr(sender, "first_name", "") or "" if sender else "Unknown"
            date_str = msg.date.strftime("%Y-%m-%d %H:%M:%S") if msg.date else ""
            text = (msg.text or "[media/service]")[:200]
            print(f"[{date_str}] (id:{msg.id}) {name}: {text}")
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


async def cmd_search(
    profile: str, query: str, chat: str | int | None, limit: int, from_user: str | int | None,
) -> None:
    client = await _make_client(profile)
    kwargs: dict = {"search": query, "limit": limit}
    if from_user:
        kwargs["from_user"] = from_user
    try:
        async for msg in client.iter_messages(chat, **kwargs):
            chat_name = ""
            if hasattr(msg, "chat") and msg.chat:
                chat_name = getattr(msg.chat, "title", None) or getattr(msg.chat, "first_name", "") or ""
            sender = msg.sender
            name = getattr(sender, "first_name", "") or "" if sender else "?"
            date_str = msg.date.strftime("%Y-%m-%d %H:%M") if msg.date else ""
            text = (msg.text or "[media]")[:150]
            prefix = f"[{chat_name}] " if chat_name else ""
            print(f"[{date_str}] {prefix}(id:{msg.id}) {name}: {text}")
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


async def cmd_mark_read(profile: str, chat: str | int) -> None:
    client = await _make_client(profile)
    try:
        await client.send_read_acknowledge(chat)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    print(f"[{profile}] Marked {chat} as read")
    await client.disconnect()


# ── Dialogs & User Info ───────────────────────────────────


async def cmd_dialogs(profile: str) -> None:
    client = await _make_client(profile)
    async for dialog in client.iter_dialogs():
        print(f"{dialog.name:40s}  (id: {dialog.id})")
    await client.disconnect()


async def cmd_whoami(profile: str) -> None:
    client = await _make_client(profile)
    me = await client.get_me()
    info = {
        "profile": profile,
        "user_id": me.id,
        "first_name": me.first_name,
        "last_name": me.last_name,
        "username": me.username,
        "phone": me.phone,
    }
    print(json.dumps(info, indent=2, ensure_ascii=False))
    await client.disconnect()


async def cmd_find_user(profile: str, query: str) -> None:
    client = await _make_client(profile)
    try:
        entity = await client.get_entity(query)
        info: dict = {"type": type(entity).__name__, "id": entity.id}
        if hasattr(entity, "first_name"):
            info["first_name"] = entity.first_name
            info["last_name"] = entity.last_name
            info["username"] = entity.username
            info["phone"] = getattr(entity, "phone", None)
            info["bot"] = getattr(entity, "bot", False)
        elif hasattr(entity, "title"):
            info["title"] = entity.title
            info["username"] = getattr(entity, "username", None)
            info["participants_count"] = getattr(entity, "participants_count", None)
        print(json.dumps(info, indent=2, ensure_ascii=False))
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


# ── Media Downloads ───────────────────────────────────────


async def cmd_download(
    profile: str, chat: str | int, msg_id: int, output_dir: str,
) -> None:
    client = await _make_client(profile)
    os.makedirs(output_dir, exist_ok=True)
    try:
        msgs = await client.get_messages(chat, ids=msg_id)
        msg = msgs if not isinstance(msgs, list) else msgs[0] if msgs else None
        if not msg:
            print(f"Error: message {msg_id} not found in {chat}", file=sys.stderr)
            await client.disconnect()
            sys.exit(1)
        if not msg.media:
            print(f"Error: message {msg_id} has no media", file=sys.stderr)
            await client.disconnect()
            sys.exit(1)
        path = await client.download_media(msg, file=output_dir)
        print(f"[{profile}] Downloaded: {path}")
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


# ── Channel Dump ─────────────────────────────────────────


def _media_extension(msg) -> str | None:
    """Determine file extension from message media type."""
    if isinstance(msg.media, MessageMediaPhoto):
        return ".jpg"
    if isinstance(msg.media, MessageMediaDocument):
        doc = msg.media.document
        if doc:
            for attr in doc.attributes:
                name = getattr(attr, "file_name", None)
                if name and "." in name:
                    return Path(name).suffix
            mime = getattr(doc, "mime_type", "") or ""
            return {
                "video/mp4": ".mp4", "image/png": ".png", "image/jpeg": ".jpg",
                "image/webp": ".webp", "audio/ogg": ".ogg", "application/pdf": ".pdf",
                "video/quicktime": ".mov", "image/gif": ".gif",
            }.get(mime, ".bin")
    return None


async def cmd_dump(
    profile: str, chat: str | int, out_dir: str, *, download_media: bool = True,
) -> None:
    client = await _make_client(profile)
    out_path = Path(out_dir)
    ndjson_path = out_path / "messages.ndjson"
    media_dir = out_path / "media"
    media_dir.mkdir(parents=True, exist_ok=True)

    msg_count = 0
    media_count = 0
    skip_count = 0

    with open(ndjson_path, "w", encoding="utf-8") as f:
        async for msg in client.iter_messages(chat, limit=None, reverse=True):
            ext = _media_extension(msg) if msg.media else None
            media_file = f"{msg.id}{ext}" if ext else None

            record = {
                "id": msg.id,
                "date": msg.date.isoformat() if msg.date else None,
                "text": msg.text,
                "has_media": msg.media is not None,
                "media_type": type(msg.media).__name__ if msg.media else None,
                "media_file": media_file,
                "views": getattr(msg, "views", None),
                "forwards": getattr(msg, "forwards", None),
                "reply_to_msg_id": msg.reply_to.reply_to_msg_id if msg.reply_to else None,
                "grouped_id": msg.grouped_id,
                "edit_date": msg.edit_date.isoformat() if msg.edit_date else None,
            }
            if msg.sender:
                s = msg.sender
                record["sender"] = {
                    "id": s.id,
                    "name": getattr(s, "title", None) or getattr(s, "first_name", "") or "",
                    "username": getattr(s, "username", None),
                }
            else:
                record["sender"] = None

            f.write(json.dumps(record, ensure_ascii=False) + "\n")

            if download_media and media_file:
                dest = media_dir / media_file
                if dest.exists():
                    skip_count += 1
                else:
                    try:
                        await msg.download_media(file=str(dest))
                        media_count += 1
                    except Exception as exc:
                        print(f"  WARN: msg {msg.id} download failed: {exc}", file=sys.stderr)

            msg_count += 1
            if msg_count % 500 == 0:
                print(f"  ... {msg_count} msgs, {media_count} media, {skip_count} skipped", file=sys.stderr)

    await client.disconnect()
    print(f"Done: {msg_count} messages, {media_count} media → {out_dir}", file=sys.stderr)
    if skip_count:
        print(f"  ({skip_count} already existed — skipped)", file=sys.stderr)
    print(ndjson_path)


# ── Group/Channel Management ─────────────────────────────


async def cmd_create_group(
    profile: str, title: str, group_type: str, about: str | None, users: list[str],
) -> None:
    client = await _make_client(profile)
    try:
        if group_type == "group":
            user_entities = [await client.get_input_entity(u) for u in users] if users else []
            result = await client(functions.messages.CreateChatRequest(
                users=user_entities, title=title,
            ))
            chat = result.updates.chats[0] if hasattr(result, "updates") else result.chats[0]
            print(f"[{profile}] Created group '{title}' (id: {chat.id})")
        else:
            is_channel = group_type == "channel"
            result = await client(functions.channels.CreateChannelRequest(
                title=title,
                about=about or "",
                broadcast=is_channel,
                megagroup=not is_channel,
            ))
            ch = result.chats[0]
            print(f"[{profile}] Created {group_type} '{title}' (id: {ch.id})")
            if users:
                user_entities = [await client.get_input_entity(u) for u in users]
                await client(functions.channels.InviteToChannelRequest(
                    channel=ch, users=user_entities,
                ))
                print(f"[{profile}] Invited {len(users)} user(s)")
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


async def cmd_invite(profile: str, group: str | int, users: list[str]) -> None:
    client = await _make_client(profile)
    try:
        entity = await client.get_entity(group)
        user_entities = [await client.get_input_entity(u) for u in users]
        if hasattr(entity, "megagroup") or hasattr(entity, "broadcast"):
            await client(functions.channels.InviteToChannelRequest(
                channel=entity, users=user_entities,
            ))
        else:
            for u in user_entities:
                await client(functions.messages.AddChatUserRequest(
                    chat_id=entity.id, user_id=u, fwd_limit=50,
                ))
        print(f"[{profile}] Invited {len(users)} user(s) to {group}")
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


async def cmd_kick(profile: str, group: str | int, user: str) -> None:
    client = await _make_client(profile)
    try:
        await client.kick_participant(group, user)
        print(f"[{profile}] Kicked {user} from {group}")
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


async def cmd_members(
    profile: str, group: str | int, search: str | None, admins_only: bool, limit: int,
) -> None:
    client = await _make_client(profile)
    try:
        filter_type = types.ChannelParticipantsAdmins() if admins_only else None
        count = 0
        async for user in client.iter_participants(group, limit=limit, search=search or "", filter=filter_type):
            role = ""
            if hasattr(user, "participant"):
                p = user.participant
                ptype = type(p).__name__
                if "Admin" in ptype:
                    role = " [admin]"
                elif "Creator" in ptype:
                    role = " [creator]"
            username = f" @{user.username}" if user.username else ""
            print(f"{user.first_name or ''} {user.last_name or ''}{username} (id: {user.id}){role}")
            count += 1
        print(f"\n— {count} member(s) listed")
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        await client.disconnect()
        sys.exit(1)
    await client.disconnect()


# ── Main ──────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Telegram CLI — personal account operations via MTProto"
    )
    parser.add_argument(
        "-p", "--profile",
        default=DEFAULT_PROFILE,
        help=f"Account profile (default: {DEFAULT_PROFILE}). Available: {', '.join(PROFILES)}",
    )
    sub = parser.add_subparsers(dest="command")

    # ── Messages ──
    sp = sub.add_parser("send", help="Send a text message")
    sp.add_argument("recipient", help="Username, phone, or chat ID")
    sp.add_argument("message", help="Message text")

    sp = sub.add_parser("send-file", help="Send a file/photo/video")
    sp.add_argument("recipient", help="Username, phone, or chat ID")
    sp.add_argument("file", help="Path to file")
    sp.add_argument("-c", "--caption", help="Caption text")
    sp.add_argument("--voice", action="store_true", help="Send as voice note")
    sp.add_argument("--video-note", action="store_true", help="Send as round video")
    sp.add_argument("--document", action="store_true", help="Force send as document")

    sp = sub.add_parser("forward", help="Forward messages between chats")
    sp.add_argument("from_chat", help="Source chat ID or username")
    sp.add_argument("message_ids", help="Message ID(s), comma-separated")
    sp.add_argument("to_chat", help="Destination chat ID or username")

    sp = sub.add_parser("edit", help="Edit a message")
    sp.add_argument("chat", help="Chat ID or username")
    sp.add_argument("message_id", type=int, help="Message ID to edit")
    sp.add_argument("new_text", help="New message text")

    sp = sub.add_parser("delete", help="Delete messages")
    sp.add_argument("chat", help="Chat ID or username")
    sp.add_argument("message_ids", help="Message ID(s), comma-separated")
    sp.add_argument("--self-only", action="store_true", help="Delete only for yourself")

    sp = sub.add_parser("pin", help="Pin or unpin a message")
    sp.add_argument("chat", help="Chat ID or username")
    sp.add_argument("message_id", type=int, nargs="?", default=0, help="Message ID (omit to unpin all)")
    sp.add_argument("--unpin", action="store_true", help="Unpin instead of pin")
    sp.add_argument("--silent", action="store_true", help="Pin without notification")

    # ── Reading & Search ──
    sp = sub.add_parser("read", help="Read recent messages from a chat")
    sp.add_argument("chat", help="Chat ID or username")
    sp.add_argument("-n", "--limit", type=int, default=10, help="Number of messages (default: 10)")

    sp = sub.add_parser("search", help="Search messages")
    sp.add_argument("query", help="Search text")
    sp.add_argument("--chat", dest="search_chat", help="Limit to specific chat (omit for global)")
    sp.add_argument("-n", "--limit", type=int, default=20, help="Max results (default: 20)")
    sp.add_argument("--from", dest="from_user", help="Filter by sender")

    sp = sub.add_parser("mark-read", help="Mark a chat as read")
    sp.add_argument("chat", help="Chat ID or username")

    # ── Dialogs & Users ──
    sub.add_parser("dialogs", help="List all chats/groups/channels")
    sub.add_parser("whoami", help="Show current account info")

    sp = sub.add_parser("find-user", help="Resolve username/phone/ID to user info")
    sp.add_argument("query", help="Username (@user), phone, or user ID")

    # ── Media ──
    sp = sub.add_parser("download", help="Download media from a message")
    sp.add_argument("chat", help="Chat ID or username")
    sp.add_argument("message_id", type=int, help="Message ID with media")
    sp.add_argument("-o", "--output", default=".", help="Output directory (default: current)")

    # ── Dump ──
    sp = sub.add_parser("dump", help="Dump full chat/channel history to NDJSON + media")
    sp.add_argument("chat", help="Chat ID or username")
    sp.add_argument("output", help="Output directory (messages.ndjson + media/ created inside)")
    sp.add_argument("--no-media", action="store_true", help="Skip media downloads (NDJSON only)")

    # ── Groups/Channels ──
    sp = sub.add_parser("create-group", help="Create a group, supergroup, or channel")
    sp.add_argument("title", help="Group/channel title")
    sp.add_argument("--type", dest="group_type", choices=["group", "supergroup", "channel"], default="supergroup")
    sp.add_argument("--about", help="Description")
    sp.add_argument("--users", nargs="*", default=[], help="Users to invite (usernames or IDs)")

    sp = sub.add_parser("invite", help="Invite users to a group/channel")
    sp.add_argument("group", help="Group/channel ID or username")
    sp.add_argument("users", nargs="+", help="Users to invite")

    sp = sub.add_parser("kick", help="Kick a user from a group/channel")
    sp.add_argument("group", help="Group/channel ID or username")
    sp.add_argument("user", help="User to kick")

    sp = sub.add_parser("members", help="List members of a group/channel")
    sp.add_argument("group", help="Group/channel ID or username")
    sp.add_argument("--search", help="Filter by name/username")
    sp.add_argument("--admins", action="store_true", help="Show admins only")
    sp.add_argument("-n", "--limit", type=int, default=200, help="Max members (default: 200)")

    args = parser.parse_args()
    profile = args.profile

    match args.command:
        case "send":
            asyncio.run(cmd_send(profile, parse_entity(args.recipient), args.message))
        case "send-file":
            asyncio.run(cmd_send_file(
                profile, parse_entity(args.recipient), args.file,
                args.caption, args.voice, args.video_note, args.document,
            ))
        case "forward":
            ids = [int(x.strip()) for x in args.message_ids.split(",")]
            asyncio.run(cmd_forward(profile, parse_entity(args.from_chat), ids, parse_entity(args.to_chat)))
        case "edit":
            asyncio.run(cmd_edit(profile, parse_entity(args.chat), args.message_id, args.new_text))
        case "delete":
            ids = [int(x.strip()) for x in args.message_ids.split(",")]
            asyncio.run(cmd_delete(profile, parse_entity(args.chat), ids, not args.self_only))
        case "pin":
            asyncio.run(cmd_pin(profile, parse_entity(args.chat), args.message_id, args.unpin, args.silent))
        case "read":
            asyncio.run(cmd_read(profile, parse_entity(args.chat), args.limit))
        case "search":
            chat = parse_entity(args.search_chat) if args.search_chat else None
            from_u = parse_entity(args.from_user) if args.from_user else None
            asyncio.run(cmd_search(profile, args.query, chat, args.limit, from_u))
        case "mark-read":
            asyncio.run(cmd_mark_read(profile, parse_entity(args.chat)))
        case "dialogs":
            asyncio.run(cmd_dialogs(profile))
        case "whoami":
            asyncio.run(cmd_whoami(profile))
        case "find-user":
            asyncio.run(cmd_find_user(profile, args.query))
        case "download":
            asyncio.run(cmd_download(profile, parse_entity(args.chat), args.message_id, args.output))
        case "dump":
            asyncio.run(cmd_dump(profile, parse_entity(args.chat), args.output, download_media=not args.no_media))
        case "create-group":
            asyncio.run(cmd_create_group(profile, args.title, args.group_type, args.about, args.users))
        case "invite":
            asyncio.run(cmd_invite(profile, parse_entity(args.group), args.users))
        case "kick":
            asyncio.run(cmd_kick(profile, parse_entity(args.group), args.user))
        case "members":
            asyncio.run(cmd_members(profile, parse_entity(args.group), args.search, args.admins, args.limit))
        case _:
            parser.print_help()


if __name__ == "__main__":
    main()
