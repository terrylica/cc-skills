/**
 * logger.ts - Structured NDJSON logging with graceful degradation
 *
 * Logs to: ~/.claude/logs/session-registry.jsonl
 *
 * Design principles:
 * - Silent fail (never crash on logging)
 * - No PII in logs (paths sanitized)
 * - Structured JSON for queryability
 */

import { appendFileSync, existsSync, mkdirSync } from "fs";

const LOG_DIR = `${process.env.HOME}/.claude/logs`;
const LOG_FILE = `${LOG_DIR}/session-registry.jsonl`;

interface LogEntry {
  ts: string;
  level: "debug" | "info" | "warn" | "error";
  msg: string;
  component: string;
  pid: number;
  session_id?: string;
  project_path?: string;
  event?: string;
  duration_ms?: number;
  ctx?: Record<string, unknown>;
}

/**
 * Sanitize path for logging (PII prevention)
 * Replaces home directory with ~
 */
function sanitizePath(path: string): string {
  const home = process.env.HOME || "";
  return path.replace(home, "~");
}

/**
 * Log a structured entry to session-registry.jsonl
 *
 * @param level - Log level (debug, info, warn, error)
 * @param msg - Human-readable message
 * @param ctx - Additional structured context
 */
export function log(
  level: LogEntry["level"],
  msg: string,
  ctx: Partial<Omit<LogEntry, "ts" | "level" | "msg" | "component" | "pid">> = {}
): void {
  try {
    // Ensure log directory exists
    if (!existsSync(LOG_DIR)) {
      mkdirSync(LOG_DIR, { recursive: true, mode: 0o755 });
    }

    // Sanitize project_path if present
    const sanitizedCtx = { ...ctx };
    if (sanitizedCtx.project_path) {
      sanitizedCtx.project_path = sanitizePath(sanitizedCtx.project_path);
    }

    const entry: LogEntry = {
      ts: new Date().toISOString(),
      level,
      msg,
      component: "session-registry",
      pid: process.pid,
      ...sanitizedCtx,
    };

    appendFileSync(LOG_FILE, JSON.stringify(entry) + "\n");
  } catch (e) {
    // Intentional graceful degradation - logging failure must not block statusline
    // Write to stderr only (doesn't affect stdout which statusline uses)
    console.error("[session-registry] Log write failed:", e);
  }
}

/**
 * Convenience methods for each log level
 */
export const logger = {
  debug: (msg: string, ctx?: Parameters<typeof log>[2]) => log("debug", msg, ctx),
  info: (msg: string, ctx?: Parameters<typeof log>[2]) => log("info", msg, ctx),
  warn: (msg: string, ctx?: Parameters<typeof log>[2]) => log("warn", msg, ctx),
  error: (msg: string, ctx?: Parameters<typeof log>[2]) => log("error", msg, ctx),
};
