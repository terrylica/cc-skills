#!/usr/bin/env bun
/**
 * stop-cron-gc.ts — Stop hook: Cron Registry Garbage Collection (Layer 2 of 3)
 *
 * Defense-in-depth stale cron cleanup. When a session exits, reconcile
 * ~/.claude/state/active-crons.json against the system crontab. Entries
 * whose job ID no longer appears in `crontab -l` are stale — the cron was
 * deleted, the session died without CronDelete, or the user manually killed it.
 *
 * Pattern: Consul anti-entropy sync adapted for local JSON registry.
 *   - Layer 1: Render-time GC in custom-statusline.sh (every ~10s)
 *   - Layer 2: This Stop hook (on session exit)            ← YOU ARE HERE
 *   - Layer 3: TTL backstop in cron-tracker.ts (on next CronCreate/Delete/List)
 *
 * Any single layer is sufficient for cleanup. All three together make the
 * system anti-fragile — resilient to missed events, killed processes, and
 * clock drift.
 */

import { readFileSync, writeFileSync, mkdirSync, appendFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

const HOME = homedir();
const STATE_FILE = join(HOME, ".claude", "state", "active-crons.json");
const LOG_FILE = join(HOME, ".claude", "logs", "cron-tracker.jsonl");

interface CronEntry {
  id: string;
  schedule: string;
  description: string;
  session_id: string;
  project_path: string;
  prompt_file: string;
  created_at: string;
}

function log(event: string, ctx: Record<string, unknown> = {}): void {
  try {
    mkdirSync(join(HOME, ".claude", "logs"), { recursive: true });
    appendFileSync(
      LOG_FILE,
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "info",
        component: "stop-cron-gc",
        event,
        pid: process.pid,
        ...ctx,
      }) + "\n"
    );
  } catch { /* silent */ }
}

function main(): void {
  // Fast exit: no state file or empty
  if (!existsSync(STATE_FILE)) {
    process.stdout.write("{}");
    process.exit(0);
  }

  let entries: CronEntry[];
  try {
    entries = JSON.parse(readFileSync(STATE_FILE, "utf-8"));
  } catch {
    process.stdout.write("{}");
    process.exit(0);
  }

  if (entries.length === 0) {
    process.stdout.write("{}");
    process.exit(0);
  }

  // Get live crontab snapshot
  const crontabResult = Bun.spawnSync(["crontab", "-l"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const crontab = crontabResult.stdout.toString();

  // Cross-check: find entries whose ID is NOT in crontab
  const staleIds: string[] = [];
  const liveIds: string[] = [];

  for (const entry of entries) {
    if (crontab.includes(entry.id)) {
      liveIds.push(entry.id);
    } else {
      staleIds.push(entry.id);
    }
  }

  if (staleIds.length > 0) {
    // Atomic write: keep only live entries
    const live = entries.filter((e) => !staleIds.includes(e.id));
    try {
      writeFileSync(STATE_FILE, JSON.stringify(live, null, 2));
      log("stop_gc_pruned", {
        pruned: staleIds,
        remaining: liveIds,
        pruned_count: staleIds.length,
      });
    } catch (e) {
      log("stop_gc_write_error", { error: String(e) });
    }
  } else {
    log("stop_gc_all_live", { count: entries.length });
  }

  // Stop hooks return {} to allow session exit
  process.stdout.write("{}");
}

main();
