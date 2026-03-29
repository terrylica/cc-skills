#!/usr/bin/env bun
/**
 * stop-cron-gc.ts — Stop hook: Cron Registry Garbage Collection (Layer 2 of 3)
 *
 * Defense-in-depth stale cron cleanup. When a session exits, reconcile
 * ~/.claude/state/active-crons.json using two signals:
 *   1. System crontab (`crontab -l`) — catches durable crons
 *   2. Session JSONL mtime — catches session-only crons (durable=false)
 *
 * Claude Code's CronCreate with durable=false creates in-process crons
 * that never appear in the system crontab. Checking crontab alone causes
 * 100% false-positive pruning of these session-only crons.
 *
 * For entries from the DYING session (this one): prune if not in crontab,
 * since session-only crons die with the session.
 * For entries from OTHER sessions: prune only if not in crontab AND
 * session JSONL is stale (mtime > 1h) or missing.
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

/** Resolve current session ID from most recently modified JSONL in project dir. */
function resolveSessionId(cwd: string): string {
  try {
    const encoded = "-" + cwd.replace(/\//g, "-").replace(/^-/, "");
    const projectDir = join(HOME, ".claude", "projects", encoded);
    const result = Bun.spawnSync(
      ["bash", "-c", `ls -t "${projectDir}"/*.jsonl 2>/dev/null | head -1`],
      { stdout: "pipe", stderr: "pipe" }
    );
    const latest = result.stdout.toString().trim();
    if (!latest) return "";
    return latest.replace(/^.*\//, "").replace(/\.jsonl$/, "");
  } catch {
    return "";
  }
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

  // Resolve the dying session's ID
  const dyingSessionId = resolveSessionId(process.cwd());

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

    // Signal 2: session liveness
    if (entry.session_id === dyingSessionId) {
      // This session is dying — session-only crons from it are dead
      staleIds.push(entry.id);
    } else if (isSessionAlive(entry.session_id, entry.project_path)) {
      // Other session is still alive → keep
      liveIds.push(entry.id);
    } else {
      // Other session is dead and cron not in crontab → stale
      staleIds.push(entry.id);
    }
  }

  if (staleIds.length > 0) {
    const live = entries.filter((e) => !staleIds.includes(e.id));
    try {
      writeFileSync(STATE_FILE, JSON.stringify(live, null, 2));
      log("stop_gc_pruned", {
        dying_session: dyingSessionId.slice(0, 8),
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
