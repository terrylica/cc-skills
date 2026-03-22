/**
 * Single Instance Guard (PID Lock)
 *
 * Prevents multiple instances of a process from running simultaneously.
 * Uses a PID file with liveness checks.
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync } from "fs";

export function acquireLock(pidFile: string): boolean {
  if (existsSync(pidFile)) {
    const existingPid = readFileSync(pidFile, "utf-8").trim();
    try {
      process.kill(Number(existingPid), 0); // Check if alive
      return false; // Another instance is running
    } catch {
      // Stale PID file — process is gone
    }
  }
  writeFileSync(pidFile, String(process.pid));
  return true;
}

export function releaseLock(pidFile: string): void {
  try {
    unlinkSync(pidFile);
  } catch {
    // Non-critical
  }
}
