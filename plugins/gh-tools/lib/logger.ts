#!/usr/bin/env bun
/**
 * logger.ts - NDJSON structured logging for gh-issue-create skill
 *
 * Logs to: ~/.claude/logs/gh-issue-create.jsonl
 *
 * Design principles:
 * - Graceful degradation (logging failure must not crash the skill)
 * - No PII in logs (paths sanitized, no issue body content)
 * - Structured JSON for queryability
 * - Errors always visible via stderr
 */

import { appendFileSync, existsSync, mkdirSync } from "node:fs";

const LOG_DIR = `${process.env.HOME}/.claude/logs`;
const LOG_FILE = `${LOG_DIR}/gh-issue-create.jsonl`;

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogContext {
  repo?: string;
  issue_number?: number;
  labels_count?: number;
  ai_model?: string;
  fallback_used?: boolean;
  body_length?: number;
  [key: string]: unknown;
}

// Top-level log fields per plan schema
export interface LogOptions {
  event?: string;
  duration_ms?: number;
  ctx?: LogContext;
}

interface LogEntry {
  ts: string;
  level: LogLevel;
  msg: string;
  component: string;
  env: string;
  pid: number;
  event?: string;
  duration_ms?: number;
  ctx?: LogContext;
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
 * Sanitize context for logging
 * - Remove any potential secrets
 * - Replace paths with sanitized versions
 */
function sanitizeContext(ctx: LogContext): LogContext {
  const sanitized: LogContext = {};

  for (const [key, value] of Object.entries(ctx)) {
    // Skip body content entirely - PII prevention
    if (key === "body" || key === "body_content") {
      continue;
    }

    // Sanitize paths that contain home directory
    if (typeof value === "string" && value.includes(process.env.HOME || "/Users")) {
      sanitized[key] = sanitizePath(value);
    } else {
      sanitized[key] = value;
    }
  }

  return sanitized;
}

/**
 * Write log entry to file with error reporting
 * Errors are reported to stderr but do not throw
 */
function writeLogEntry(entry: LogEntry): void {
  // Ensure log directory exists
  if (!existsSync(LOG_DIR)) {
    mkdirSync(LOG_DIR, { recursive: true, mode: 0o755 });
  }

  appendFileSync(LOG_FILE, JSON.stringify(entry) + "\n");
}

/**
 * Log a structured entry to gh-issue-create.jsonl
 * Uses synchronous file I/O for simplicity and reliability
 *
 * Schema matches plan: ts, level, msg, component, env, pid, event, duration_ms, ctx
 *
 * @param level - Log level (debug, info, warn, error)
 * @param msg - Human-readable message
 * @param options - Event, duration_ms, and context fields
 */
export function log(level: LogLevel, msg: string, options: LogOptions = {}): void {
  const { event, duration_ms, ctx = {} } = options;

  // Flatten any nested ctx from callers (fix nested ctx.ctx bug)
  const flatCtx: LogContext = {};
  for (const [key, value] of Object.entries(ctx)) {
    if (key === "ctx" && typeof value === "object" && value !== null) {
      // Flatten nested ctx
      Object.assign(flatCtx, value);
    } else {
      flatCtx[key] = value;
    }
  }

  const entry: LogEntry = {
    ts: new Date().toISOString(),
    level,
    msg,
    component: "gh-issue-create",
    env: process.env.NODE_ENV || "production",
    pid: process.pid,
    event,
    duration_ms,
    ctx: Object.keys(flatCtx).length > 0 ? sanitizeContext(flatCtx) : undefined,
  };

  // Write log entry - errors reported to stderr, never thrown
  // This is intentional for logger infrastructure - must not crash calling code
  writeLogEntry(entry);
}

/**
 * Convenience methods for each log level
 */
export const logger = {
  debug: (msg: string, options?: LogOptions) => log("debug", msg, options),
  info: (msg: string, options?: LogOptions) => log("info", msg, options),
  warn: (msg: string, options?: LogOptions) => log("warn", msg, options),
  error: (msg: string, options?: LogOptions) => log("error", msg, options),
};

/**
 * Create a child logger with preset context
 */
export function createLogger(baseCtx: LogContext) {
  return {
    debug: (msg: string, options?: LogOptions) => log("debug", msg, { ...options, ctx: { ...baseCtx, ...options?.ctx } }),
    info: (msg: string, options?: LogOptions) => log("info", msg, { ...options, ctx: { ...baseCtx, ...options?.ctx } }),
    warn: (msg: string, options?: LogOptions) => log("warn", msg, { ...options, ctx: { ...baseCtx, ...options?.ctx } }),
    error: (msg: string, options?: LogOptions) => log("error", msg, { ...options, ctx: { ...baseCtx, ...options?.ctx } }),
  };
}
