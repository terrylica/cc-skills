# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "telethon>=1.42.0",
# ]
# ///
"""Purge deleted/ghost Telegram accounts from dialogs and contacts.

Scans all profiles for deleted accounts across:
- Regular dialogs
- Archived dialogs (folder=1)
- Contact list

Uses 3 fallback deletion methods:
1. delete_dialog (standard)
2. DeleteHistoryRequest (force clear)
3. Block + Unblock + delete_dialog (stubborn ghosts)

After deletion, re-scans to catch any survivors and retries with
the block+unblock method which forces Telegram to reset peer state.
"""

import argparse
import asyncio
import os
import subprocess
import sys

from telethon import TelegramClient, functions, types

SESSION_DIR = os.path.expanduser("~/.local/share/telethon")

PROFILES: dict[str, str] = {
    "eon": "iqwxow2iidycaethycub7agfmm",
    "missterryli": "dk456cs3v2fjilppernryoro5a",
}

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


async def _make_client(profile: str) -> TelegramClient:
    item_id = PROFILES.get(profile)
    if not item_id:
        print(f"Unknown profile '{profile}'. Available: {', '.join(PROFILES)}", file=sys.stderr)
        sys.exit(1)
    api_id = int(_op_get(item_id, "App ID"))
    api_hash = _op_get(item_id, "App API Hash", reveal=True)
    client = TelegramClient(os.path.join(SESSION_DIR, profile), api_id, api_hash)
    await client.start()
    return client


async def _collect_deleted(client: TelegramClient) -> list[tuple]:
    """Collect deleted accounts from dialogs and archived dialogs."""
    found = []
    seen_ids = set()

    # Pass 1: regular dialogs
    async for dialog in client.iter_dialogs():
        entity = dialog.entity
        if isinstance(entity, types.User) and entity.deleted and entity.id not in seen_ids:
            found.append((dialog, entity))
            seen_ids.add(entity.id)

    # Pass 2: archived dialogs
    try:
        async for dialog in client.iter_dialogs(folder=1):
            entity = dialog.entity
            if isinstance(entity, types.User) and entity.deleted and entity.id not in seen_ids:
                found.append((dialog, entity))
                seen_ids.add(entity.id)
    except Exception:
        pass

    return found


async def _delete_one(client: TelegramClient, dialog, entity, profile: str) -> bool:
    """Try 3 methods to delete a dialog with a deleted account."""
    # Method 1: standard delete_dialog
    try:
        await client.delete_dialog(entity, revoke=True)
        print(f"  [{profile}] ✓ Removed id={entity.id} (delete_dialog)")
        return True
    except Exception:
        pass

    # Method 2: DeleteHistoryRequest
    try:
        await client(functions.messages.DeleteHistoryRequest(
            peer=await client.get_input_entity(entity),
            max_id=0,
            just_clear=False,
            revoke=True,
        ))
        print(f"  [{profile}] ✓ Removed id={entity.id} (DeleteHistory)")
        return True
    except Exception:
        pass

    # Method 3: Block + Unblock + delete (forces peer state reset)
    try:
        input_user = types.InputUser(user_id=entity.id, access_hash=entity.access_hash)
        await client(functions.contacts.BlockRequest(id=input_user))
        await asyncio.sleep(0.2)
        await client(functions.contacts.UnblockRequest(id=input_user))
        await asyncio.sleep(0.2)
        await client.delete_dialog(entity, revoke=True)
        print(f"  [{profile}] ✓ Removed id={entity.id} (block+unblock+delete)")
        return True
    except Exception as exc:
        print(f"  [{profile}] ✗ FAILED id={entity.id}: {exc}", file=sys.stderr)
        return False


async def cleanup_profile(profile: str, dry_run: bool = False) -> tuple[int, int, int]:
    """Purge deleted accounts from a single profile. Returns (found, removed, failed)."""
    client = await _make_client(profile)

    # Collect deleted accounts
    deleted = await _collect_deleted(client)
    print(f"\n=== {profile}: {len(deleted)} deleted account(s) found ===")

    if dry_run:
        for dialog, entity in deleted:
            print(f"  [DRY] id={entity.id} ({dialog.name or 'Deleted Account'})")
        await client.disconnect()
        return len(deleted), 0, 0

    # Delete them
    removed = 0
    failed = 0
    for dialog, entity in deleted:
        if await _delete_one(client, dialog, entity, profile):
            removed += 1
        else:
            failed += 1
        await asyncio.sleep(0.3)

    # Clean up deleted contacts
    try:
        result = await client(functions.contacts.GetContactsRequest(hash=0))
        if hasattr(result, "users"):
            deleted_contacts = [u for u in result.users if u.deleted]
            for u in deleted_contacts:
                try:
                    await client(functions.contacts.DeleteContactsRequest(
                        id=[types.InputUser(user_id=u.id, access_hash=u.access_hash)]
                    ))
                    print(f"  [{profile}] ✓ Removed contact id={u.id}")
                    removed += 1
                except Exception as exc:
                    print(f"  [{profile}] ✗ Contact {u.id}: {exc}", file=sys.stderr)
                    failed += 1
    except Exception:
        pass

    # Re-scan for stubborn survivors
    survivors = await _collect_deleted(client)
    for dialog, entity in survivors:
        print(f"  [{profile}] STUBBORN id={entity.id} — retrying block+unblock...")
        try:
            input_user = types.InputUser(user_id=entity.id, access_hash=entity.access_hash)
            await client(functions.contacts.BlockRequest(id=input_user))
            await asyncio.sleep(0.2)
            await client(functions.contacts.UnblockRequest(id=input_user))
            await asyncio.sleep(0.2)
            await client.delete_dialog(entity, revoke=True)
            print(f"    ✓ Removed on retry")
            removed += 1
        except Exception as exc:
            print(f"    ✗ Still stuck: {exc}", file=sys.stderr)
            failed += 1

    total_found = len(deleted) + len(survivors)
    print(f"\n[{profile}] Done: {removed} removed, {failed} failed")
    await client.disconnect()
    return total_found, removed, failed


async def main(profiles: list[str], dry_run: bool) -> None:
    total_found, total_removed, total_failed = 0, 0, 0
    for p in profiles:
        f, r, fail = await cleanup_profile(p, dry_run=dry_run)
        total_found += f
        total_removed += r
        total_failed += fail

    print(f"\n{'='*50}")
    action = "would remove" if dry_run else "removed"
    print(f"TOTAL: {total_found} found, {total_removed} {action}, {total_failed} failed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Purge deleted/ghost Telegram accounts from all profiles"
    )
    parser.add_argument(
        "-p", "--profile",
        nargs="*",
        default=list(PROFILES.keys()),
        help=f"Profiles to clean (default: all). Available: {', '.join(PROFILES)}",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Scan and report without deleting",
    )
    args = parser.parse_args()
    asyncio.run(main(args.profile, args.dry_run))
