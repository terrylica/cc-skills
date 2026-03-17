# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "telethon>=1.42.0",
# ]
# ///
"""Telegram user-account CLI via MTProto (Telethon).

Send messages, list dialogs as your personal Telegram account.
Credentials fetched from 1Password at runtime.

Session persists at ~/.local/share/telethon/session.session
after first interactive auth (phone + code + optional 2FA).
"""

import argparse
import asyncio
import os
import subprocess
import sys

from telethon import TelegramClient

SESSION_FILE = os.path.expanduser("~/.local/share/telethon/session")

# 1Password item coordinates (public — no secrets here)
OP_ITEM_ID = os.environ.get(
    "TELETHON_OP_UUID", "<1password-item-id>"
)
OP_VAULT = os.environ.get("TELETHON_OP_VAULT", "Claude Automation")


def _op_get(field: str, *, reveal: bool = False) -> str:
    """Fetch a field from 1Password."""
    cmd = [
        "op", "item", "get", OP_ITEM_ID,
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


def get_credentials() -> tuple[int, str]:
    """Return (api_id, api_hash) from env vars or 1Password."""
    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")

    if api_id and api_hash:
        return int(api_id), api_hash

    # Fall back to 1Password
    api_id_str = _op_get("App ID")
    api_hash = _op_get("App API Hash", reveal=True)
    return int(api_id_str), api_hash


async def _make_client() -> TelegramClient:
    api_id, api_hash = get_credentials()
    os.makedirs(os.path.dirname(SESSION_FILE), exist_ok=True)
    client = TelegramClient(SESSION_FILE, api_id, api_hash)
    await client.start()
    return client


async def cmd_send(recipient: str | int, message: str) -> None:
    client = await _make_client()
    await client.send_message(recipient, message)
    print(f"Sent to {recipient}")
    await client.disconnect()


async def cmd_dialogs() -> None:
    client = await _make_client()
    async for dialog in client.iter_dialogs():
        print(f"{dialog.name:40s}  (id: {dialog.id})")
    await client.disconnect()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Telegram CLI — send messages as your personal account via MTProto"
    )
    sub = parser.add_subparsers(dest="command")

    send_p = sub.add_parser("send", help="Send a message")
    send_p.add_argument("recipient", help="Username, phone, or chat ID")
    send_p.add_argument("message", help="Message text")

    sub.add_parser("dialogs", help="List all chats/groups/channels")

    args = parser.parse_args()

    if args.command == "send":
        recipient = (
            int(args.recipient)
            if args.recipient.lstrip("-").isdigit()
            else args.recipient
        )
        asyncio.run(cmd_send(recipient, args.message))
    elif args.command == "dialogs":
        asyncio.run(cmd_dialogs())
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
