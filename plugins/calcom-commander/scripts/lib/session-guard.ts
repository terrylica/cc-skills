// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * PID-file based mutex lock — prevents duplicate bot/sync instances.
 */

import { existsSync, readFileSync, writeFileSync } from "fs";

export async function sessionGuard(pidFile: string): Promise<void> {
  if (existsSync(pidFile)) {
    const pid = parseInt(readFileSync(pidFile, "utf-8").trim(), 10);
    try {
      process.kill(pid, 0); // Check if alive
      console.error(`Another instance is running (PID ${pid}). Exiting.`);
      process.exit(1);
    } catch {
      // Stale PID file — process not running, safe to continue
    }
  }

  writeFileSync(pidFile, String(process.pid));
}
