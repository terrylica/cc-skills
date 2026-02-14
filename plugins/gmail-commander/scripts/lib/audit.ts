/**
 * NDJSON Audit Logger
 *
 * Writes structured events to daily log files.
 * Pattern reused from claude-telegram-sync/src/utils/audit-log.ts
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { appendFileSync, mkdirSync, readdirSync, unlinkSync } from "fs";
import { join } from "path";

const RETENTION_DAYS = 14;

let auditDir: string;

/**
 * Set the audit log directory. Must be called before logging.
 * Default: ~/own/amonic/logs/audit (set by launcher scripts via AUDIT_DIR env).
 */
export function setAuditDir(dir: string): void {
  auditDir = dir;
}

function getDir(): string {
  if (auditDir) return auditDir;
  const envDir = Bun.env.AUDIT_DIR;
  if (envDir) {
    auditDir = envDir;
    return auditDir;
  }
  auditDir = join(process.env.HOME || "~", "own", "amonic", "logs", "audit");
  return auditDir;
}

function getLogPath(): string {
  const date = new Date().toISOString().slice(0, 10);
  return join(getDir(), `${date}.ndjson`);
}

export function auditLog(event: string, data?: Record<string, unknown>): void {
  try {
    mkdirSync(getDir(), { recursive: true });
    const entry = {
      ts: new Date().toISOString(),
      event,
      pid: process.pid,
      ...data,
    };
    appendFileSync(getLogPath(), JSON.stringify(entry) + "\n");
  } catch {
    // Audit logging should never crash the main process
  }
}

export function pruneOldLogs(): void {
  try {
    const dir = getDir();
    const files = readdirSync(dir).filter((f) => f.endsWith(".ndjson"));
    const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;

    for (const file of files) {
      const dateStr = file.replace(".ndjson", "");
      const fileDate = new Date(dateStr).getTime();
      if (fileDate < cutoff) {
        unlinkSync(join(dir, file));
      }
    }
  } catch {
    // Non-critical
  }
}
