// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * NDJSON daily audit logs with 14-day retention.
 */

import { appendFileSync, existsSync, mkdirSync, readdirSync, unlinkSync } from "fs";
import { join } from "path";

const AUDIT_DIR = process.env.AUDIT_DIR || `${process.env.HOME}/own/amonic/logs/audit`;
const RETENTION_DAYS = 14;

function getLogPath(): string {
  const date = new Date().toISOString().slice(0, 10);
  return join(AUDIT_DIR, `${date}.ndjson`);
}

export async function audit(event: string, data: Record<string, unknown> = {}): Promise<void> {
  try {
    if (!existsSync(AUDIT_DIR)) {
      mkdirSync(AUDIT_DIR, { recursive: true });
    }

    const entry = {
      timestamp: new Date().toISOString(),
      event,
      pid: process.pid,
      service: "calcom-commander",
      ...data,
    };

    appendFileSync(getLogPath(), JSON.stringify(entry) + "\n");

    // Prune old logs
    pruneOldLogs();
  } catch {
    // Best-effort audit logging
  }
}

function pruneOldLogs(): void {
  try {
    const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
    const files = readdirSync(AUDIT_DIR).filter((f) => f.endsWith(".ndjson"));

    for (const file of files) {
      const dateStr = file.replace(".ndjson", "");
      const fileDate = new Date(dateStr).getTime();
      if (fileDate < cutoff) {
        unlinkSync(join(AUDIT_DIR, file));
      }
    }
  } catch {
    // Best-effort pruning
  }
}
