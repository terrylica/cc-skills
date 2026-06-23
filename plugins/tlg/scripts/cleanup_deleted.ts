#!/usr/bin/env bun
/**
 * cleanup_deleted.ts — purge deleted/ghost Telegram accounts from dialogs and
 * contacts across one or more profiles.
 *
 * Ported from cleanup_deleted.py (Telethon → GramJS). Reuses the authenticated
 * client + profile registry exported by tg-cli.ts so credential/session handling
 * lives in exactly one place.
 *
 * Deletion strategy per ghost (escalating):
 *   1. messages.DeleteHistory (revoke) — force-clear the dialog
 *   2. Block → Unblock → DeleteHistory — resets stubborn peer state
 * Then deleted contacts are removed, and a re-scan retries any survivors.
 *
 * Function-driven by design (see plugin convention).
 */

import process from "node:process";
import bigInt from "big-integer";
import { Api, type TelegramClient } from "telegram";
import { connectAuthed, PROFILES } from "./tg-cli.ts";

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

interface Ghost {
  readonly entity: any;
  readonly name: string;
}

interface Tally {
  found: number;
  removed: number;
  failed: number;
}

/** Collect deleted-account dialogs from the active and archived folders. */
async function collectDeleted(client: TelegramClient): Promise<Ghost[]> {
  const found: Ghost[] = [];
  const seen = new Set<string>();
  for (const folder of [0, 1]) {
    try {
      for await (const dialog of client.iterDialogs({ folder })) {
        const entity: any = (dialog as any).entity;
        if (entity instanceof Api.User && entity.deleted && !seen.has(String(entity.id))) {
          found.push({ entity, name: (dialog as any).name || "Deleted Account" });
          seen.add(String(entity.id));
        }
      }
    } catch {
      // archived folder may be empty or unavailable — skip
    }
  }
  return found;
}

async function deleteHistory(client: TelegramClient, entity: any): Promise<void> {
  await client.invoke(
    new Api.messages.DeleteHistory({
      peer: await client.getInputEntity(entity),
      maxId: 0,
      justClear: false,
      revoke: true,
    }),
  );
}

async function blockUnblockDelete(client: TelegramClient, entity: any): Promise<void> {
  const inputUser = new Api.InputUser({ userId: entity.id, accessHash: entity.accessHash });
  await client.invoke(new Api.contacts.Block({ id: inputUser }));
  await sleep(200);
  await client.invoke(new Api.contacts.Unblock({ id: inputUser }));
  await sleep(200);
  await deleteHistory(client, entity);
}

async function deleteOne(client: TelegramClient, entity: any, profile: string): Promise<boolean> {
  try {
    await deleteHistory(client, entity);
    process.stdout.write(`  [${profile}] ✓ Removed id=${entity.id} (DeleteHistory)\n`);
    return true;
  } catch {
    // escalate
  }
  try {
    await blockUnblockDelete(client, entity);
    process.stdout.write(`  [${profile}] ✓ Removed id=${entity.id} (block+unblock+delete)\n`);
    return true;
  } catch (error) {
    process.stderr.write(`  [${profile}] ✗ FAILED id=${entity.id}: ${String(error)}\n`);
    return false;
  }
}

async function removeDeletedContacts(client: TelegramClient, profile: string, tally: Tally): Promise<void> {
  try {
    const result: any = await client.invoke(new Api.contacts.GetContacts({ hash: bigInt(0) }));
    for (const user of (result.users ?? []).filter((u: any) => u.deleted)) {
      try {
        await client.invoke(
          new Api.contacts.DeleteContacts({
            id: [new Api.InputUser({ userId: user.id, accessHash: user.accessHash })],
          }),
        );
        process.stdout.write(`  [${profile}] ✓ Removed contact id=${user.id}\n`);
        tally.removed += 1;
      } catch (error) {
        process.stderr.write(`  [${profile}] ✗ Contact ${user.id}: ${String(error)}\n`);
        tally.failed += 1;
      }
    }
  } catch {
    // GetContacts may be unavailable — skip
  }
}

async function cleanupProfile(profile: string, dryRun: boolean): Promise<Tally> {
  const tally: Tally = { found: 0, removed: 0, failed: 0 };
  let client: TelegramClient;
  try {
    client = await connectAuthed(profile);
  } catch (error) {
    process.stderr.write(`\n=== ${profile}: SKIPPED — ${String(error)}\n`);
    return tally;
  }
  try {
    const deleted = await collectDeleted(client);
    process.stdout.write(`\n=== ${profile}: ${deleted.length} deleted account(s) found ===\n`);
    tally.found = deleted.length;

    if (dryRun) {
      for (const ghost of deleted) {
        process.stdout.write(`  [DRY] id=${ghost.entity.id} (${ghost.name})\n`);
      }
      return tally;
    }

    for (const ghost of deleted) {
      if (await deleteOne(client, ghost.entity, profile)) {
        tally.removed += 1;
      } else {
        tally.failed += 1;
      }
      await sleep(300);
    }

    await removeDeletedContacts(client, profile, tally);

    // Re-scan for stubborn survivors and retry the forced reset.
    for (const ghost of await collectDeleted(client)) {
      tally.found += 1;
      process.stdout.write(`  [${profile}] STUBBORN id=${ghost.entity.id} — retrying block+unblock...\n`);
      try {
        await blockUnblockDelete(client, ghost.entity);
        process.stdout.write("    ✓ Removed on retry\n");
        tally.removed += 1;
      } catch (error) {
        process.stderr.write(`    ✗ Still stuck: ${String(error)}\n`);
        tally.failed += 1;
      }
    }

    process.stdout.write(`\n[${profile}] Done: ${tally.removed} removed, ${tally.failed} failed\n`);
    return tally;
  } finally {
    await client.disconnect();
  }
}

function parseProfiles(argv: readonly string[]): { profiles: string[]; dryRun: boolean } {
  const profiles: string[] = [];
  let dryRun = false;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i] ?? "";
    if (arg === "--dry-run") {
      dryRun = true;
    } else if (arg === "-p" || arg === "--profile") {
      while (i + 1 < argv.length && !(argv[i + 1] ?? "").startsWith("-")) {
        profiles.push(argv[++i] ?? "");
      }
    }
  }
  return { profiles: profiles.length > 0 ? profiles : Object.keys(PROFILES), dryRun };
}

async function main(): Promise<void> {
  const { profiles, dryRun } = parseProfiles(process.argv.slice(2));
  const total: Tally = { found: 0, removed: 0, failed: 0 };
  for (const profile of profiles) {
    const t = await cleanupProfile(profile, dryRun);
    total.found += t.found;
    total.removed += t.removed;
    total.failed += t.failed;
  }
  process.stdout.write(`\n${"=".repeat(50)}\n`);
  const action = dryRun ? "would remove" : "removed";
  process.stdout.write(`TOTAL: ${total.found} found, ${total.removed} ${action}, ${total.failed} failed\n`);
}

main().catch((error: unknown) => {
  process.stderr.write(`Error: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
