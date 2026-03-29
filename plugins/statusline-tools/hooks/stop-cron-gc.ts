#!/usr/bin/env bun
/**
 * stop-cron-gc.ts — Stop hook: Cron Registry Garbage Collection (Layer 2 of 3)
 *
 * Defense-in-depth stale cron cleanup. When any session exits, reconcile
 * ~/.claude/state/active-crons.json using two signals:
 *   1. System crontab (`crontab -l`) — catches durable crons
 *   2. Session JSONL mtime — catches session-only crons (durable=false)
 *
 * Claude Code's CronCreate with durable=false creates in-process crons
 * that never appear in the system crontab. Checking crontab alone causes
 * 100% false-positive pruning of these session-only crons.
 *
 * IMPORTANT: We cannot use "dying session" detection here because cron-
 * triggered child sessions share the same project dir as the parent.
 * resolveSessionId picks the parent's JSONL (most recently modified),
 * causing the Stop hook to falsely prune the parent's live crons.
 * Instead, we use JSONL mtime freshness for ALL entries — if the parent
 * session is alive, its JSONL is fresh and entries survive.
 *
 * Issue: https://github.com/terrylica/cc-skills/issues/75
 * Pattern: Consul anti-entropy sync adapted for local JSON registry.
 *   - Layer 1: Render-time GC in custom-statusline.sh (every ~10s)
 *   - Layer 2: This Stop hook (on session exit)            ← YOU ARE HERE
 *   - Layer 3: TTL backstop in cron-tracker.ts (on next CronCreate/Delete/List)
 */

import { readFileSync, writeFileSync, mkdirSync, appendFileSync, existsSync, statSync } from "fs";
import { join } from "path";
import { homedir } from "os";

const HOME = homedir();
const STATE_FILE = join(HOME, ".claude", "state", "active-crons.json");
const LOG_FILE = join(HOME, ".claude", "logs", "cron-tracker.jsonl");
const SESSION_STALE_MS = 60 * 60 * 1000; // 1 hour

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

/** Check if a session's JSONL file was recently modified. */
function isSessionAlive(sessionId: string, projectPath: string): boolean {
  try {
    const fullPath = projectPath.replace(/^~/, HOME);
    const encodedDir = "-" + fullPath.replace(/\//g, "-").replace(/^-/, "");
    const jsonlFile = join(HOME, ".claude", "projects", encodedDir, `${sessionId}.jsonl`);
    if (!existsSync(jsonlFile)) return false;
    const mtime = statSync(jsonlFile).mtimeMs;
    return (Date.now() - mtime) < SESSION_STALE_MS;
  } catch {
    return false;
  }
}

function main(): void {
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

  const staleIds: string[] = [];
  const liveIds: string[] = [];

  for (const entry of entries) {
    // Signal 1: durable cron in system crontab → live
    if (crontab.includes(entry.id)) {
      liveIds.push(entry.id);
      continue;
    }

    // Signal 2: session JSONL mtime freshness
    if (isSessionAlive(entry.session_id, entry.project_path)) {
      liveIds.push(entry.id);
    } else {
      staleIds.push(entry.id);
    }
  }

  if (staleIds.length > 0) {
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

  process.stdout.write("{}");
}

main();
