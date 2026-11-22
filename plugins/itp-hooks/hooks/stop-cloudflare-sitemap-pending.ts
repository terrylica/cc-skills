#!/usr/bin/env bun
/**
 * Stop subhook (run by stop-orchestrator.ts): blocks the end of a turn while THIS session made a Cloudflare
 * Workers / Pages deploy that is newer than the last sitemap update (operator, 2026-11-15: "remind, and block the
 * turn's end"). Other sessions' deploys never block this one. Each deploy blocks at most MAX_BLOCKS times, so a
 * sitemap that cannot be updated (machine offline) never traps a session; covered and exhausted entries are dropped.
 * Logic and config: lib/cloudflare-deploy-sitemap.ts. Fail-open: any error exits 0 silently.
 */

import {
  MAX_BLOCKS,
  lastSitemapAt,
  markCommand,
  outstanding,
  readPending,
  updateCommand,
  writePending,
} from "./lib/cloudflare-deploy-sitemap.ts";

async function main(): Promise<void> {
  const input = JSON.parse(await Bun.stdin.text());
  const session = String(input.session_id ?? "");
  // stop_hook_active: Claude is already continuing because of a Stop block. The loop guard is the per-deploy cap
  // (MAX_BLOCKS, counted in PENDING), which holds across those continuations; a deploy already at the cap never blocks.
  const continuing = input.stop_hook_active === true;
  const entries = readPending();
  if (!entries.length) return;
  const last = lastSitemapAt();
  const mine = outstanding(session, entries, last).filter((e) => (e.blocks ?? 0) < MAX_BLOCKS);
  // keep only what is still owed: newer than the sitemap, and not yet blocked MAX_BLOCKS times
  const keep = entries
    .filter((e) => Date.parse(e.at) > last && (e.blocks ?? 0) < MAX_BLOCKS)
    .map((e) => (mine.includes(e) ? { ...e, blocks: (e.blocks ?? 0) + 1 } : e));
  writePending(keep);
  if (!mine.length) return;
  const list = mine.map((e) => `  - ${e.at} in ${e.cwd}: ${e.command.slice(0, 120)}`).join("\n");
  const reason =
    `[CF-SITEMAP] This session deployed to Cloudflare and the sitemap is older than the deploy:\n${list}\n` +
    `Update it: ${updateCommand()}. If the update runs on another machine, mark it here afterwards: ${markCommand()}. ` +
    `(Blocks at most ${MAX_BLOCKS} times per deploy${continuing ? "; this is a repeat block" : ""}.)`;
  console.log(JSON.stringify({ decision: "block", reason }));
}

main().catch(() => process.exit(0));
