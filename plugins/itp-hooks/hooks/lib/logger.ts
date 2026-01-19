#!/usr/bin/env bun
/**
 * logger.ts - NDJSON structured logging for itp-hooks
 *
 * Logs to: ~/.claude/logs/itp-hooks.jsonl
 *
 * Design principles:
 * - Graceful degradation (logging failure must not crash hooks)
 * - No PII in logs (paths sanitized)
 * - Structured JSON for queryability
 * - Correlation via trace_id (from tool_use_id)
 */

import { appendFileSync, existsSync, mkdirSync } from "node:fs";

// Compute paths dynamically to support testing with modified HOME
function getLogDir(): string {
  return `${process.env.HOME}/.claude/logs`;
}

function getLogFile(): string {
  return `${getLogDir()}/itp-hooks.jsonl`;
}

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface HookLogContext {
  hook_event?: "PreToolUse" | "PostToolUse";
  decision?: "allow" | "deny" | "ask";
  tool_name?: string;
  trace_id?: string; // Correlation ID from tool_use_id
  duration_ms?: number;
  file_path?: string; // Sanitized
  pattern_matched?: string;
  error?: string;
  [key: string]: unknown;
}

interface LogEntry {
  ts: string; // UTC ISO-8601
  level: LogLevel;
  msg: string;
  component: string; // Hook name
  env: string;
  pid: number;
  hook_event?: string;
  decision?: string;
  tool_name?: string;
  trace_id?: string;
  duration_ms?: number;
  ctx?: HookLogContext;
}

function sanitizePath(path: string): string {
  const home = process.env.HOME || "";
  return path.replace(home, "~");
}

function sanitizeContext(ctx: HookLogContext): HookLogContext {
  const sanitized: HookLogContext = {};
  for (const [key, value] of Object.entries(ctx)) {
    if (typeof value === "string" && value.includes(process.env.HOME || "/Users")) {
      sanitized[key] = sanitizePath(value);
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

export function log(
  component: string,
  level: LogLevel,
  msg: string,
  ctx: HookLogContext = {}
): void {
  try {
    const logDir = getLogDir();
    const logFile = getLogFile();

    if (!existsSync(logDir)) {
      mkdirSync(logDir, { recursive: true, mode: 0o755 });
    }

    const { hook_event, decision, tool_name, trace_id, duration_ms, ...rest } = ctx;

    const entry: LogEntry = {
      ts: new Date().toISOString(),
      level,
      msg,
      component,
      env: process.env.NODE_ENV || "production",
      pid: process.pid,
      hook_event,
      decision,
      tool_name,
      trace_id,
      duration_ms,
      ctx: Object.keys(rest).length > 0 ? sanitizeContext(rest) : undefined,
    };

    appendFileSync(logFile, JSON.stringify(entry) + "\n");
  } catch {
    // Graceful degradation - logging failure must not crash hook
  }
}

export function createHookLogger(component: string) {
  return {
    debug: (msg: string, ctx?: HookLogContext) => log(component, "debug", msg, ctx),
    info: (msg: string, ctx?: HookLogContext) => log(component, "info", msg, ctx),
    warn: (msg: string, ctx?: HookLogContext) => log(component, "warn", msg, ctx),
    error: (msg: string, ctx?: HookLogContext) => log(component, "error", msg, ctx),
  };
}
