#!/usr/bin/env bun
// saved-tab-groups.ts — how many saved tab groups a Chrome profile still holds whose title is "Playwright · <client>".
//
// They are the residue of the Playwright Extension's per-connection tab groups from before chrome-profile.sh passed
// --no-tab-group: Chrome (131+) saves a group to the bookmarks bar when its last tab closes, so every run that tidied up
// its tab left one behind, synced and never removed. AppleScript cannot see tab groups, so `tabs list` never shows them.
//
// Reads a private copy of "<profile>/Sync Data/LevelDB" with the reader in extension-token-from-profile.ts. The newest
// record per key decides, so a deleted group does not count; a byte grep of the files counts it until compaction
// (measured 2026-11-17: 53 by grep against 33 live). Output: one JSON line {live, titles}; never URLs or tab content.
//
//   bun saved-tab-groups.ts <profile-dir>        exit 0 none, 1 some remain, 2 usage, 3 no readable sync store
import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { type Rec, readLevelDb, snapshot } from "./extension-token-from-profile.ts";

const GROUP_KEY = new TextEncoder().encode("saved_tab_group-dt-");
const TITLE = /Playwright · ([A-Za-z0-9 _.-]{1,40})/;

function hasPrefix(a: Uint8Array, p: Uint8Array): boolean {
  if (a.length < p.length) return false;
  for (let i = 0; i < p.length; i++) if (a[i] !== p[i]) return false;
  return true;
}

/** Live saved groups titled "Playwright · <client>": newest record per key, deletions excluded. */
export function savedPlaywrightGroups(records: Rec[]): { live: number; titles: Record<string, number> } {
  const newest = new Map<string, Rec>();
  for (const r of records) {
    if (!hasPrefix(r.key, GROUP_KEY)) continue;
    const k = Buffer.from(r.key).toString("latin1");
    const prev = newest.get(k);
    if (!prev || r.seq > prev.seq) newest.set(k, r);
  }
  const titles: Record<string, number> = {};
  let live = 0;
  for (const r of newest.values()) {
    if (!r.value) continue;
    const m = new TextDecoder().decode(r.value).match(TITLE);
    if (!m) continue;
    live++;
    titles[m[1]] = (titles[m[1]] ?? 0) + 1;
  }
  return { live, titles };
}

export function main(argv: string[]): number {
  const profile = argv[0];
  if (!profile || profile.startsWith("-")) {
    process.stderr.write("usage: saved-tab-groups.ts <profile-dir>\n");
    return 2;
  }
  const src = join(profile, "Sync Data", "LevelDB");
  if (!existsSync(src)) {
    process.stdout.write(`${JSON.stringify({ error: "no Sync Data/LevelDB in this profile" })}\n`);
    return 3;
  }
  const copy = snapshot(src);
  try {
    const r = savedPlaywrightGroups(readLevelDb(copy));
    process.stdout.write(`${JSON.stringify(r)}\n`);
    return r.live ? 1 : 0;
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
}

if (import.meta.main) process.exit(main(process.argv.slice(2)));
