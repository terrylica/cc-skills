#!/usr/bin/env bun
/**
 * hook-error-tracker.ts - Smart error tracking for Claude Code hooks
 *
 * Replaces console.error() in fail-open paths to eliminate spurious
 * "hook error" UI messages. Hooks should NEVER write to stderr on exit 0
 * (per official Claude Code docs and examples).
 *
 * Behavior:
 * - All errors logged to JSONL file silently
 * - First 2 errors per hook per session: silent (file only)
 * - 3rd error from same hook: ONE stderr escalation line
 * - 4th+ errors: silent again (no more stderr)
 *
 * Storage:
 * - Log: ~/.claude/logs/hook-errors.jsonl (append-only JSONL)
 * - Counts: /tmp/.claude-hook-error-counts-{uid}.json
 */

import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";

// --- Paths ---

function getLogDir(): string {
  return `${process.env.HOME}/.claude/logs`;
}

function getLogFile(): string {
  return `${getLogDir()}/hook-errors.jsonl`;
}

function getCountsFile(): string {
  return `/tmp/.claude-hook-error-counts-${process.getuid?.() ?? "unknown"}.json`;
}

// --- Types ---

export interface HookErrorEntry {
  ts: string;
  hook: string;
  message: string;
  session_id: string;
}

interface ErrorCounts {
  [sessionHookKey: string]: number;
}

// --- Session ID ---

/**
 * Derive session ID from environment or fallback.
 * Claude Code sets CLAUDE_SESSION_ID when hooks run.
 * Falls back to parent PID (groups hooks from same session).
 */
export function getSessionId(): string {
  return (
    process.env.CLAUDE_SESSION_ID ||
    process.env.CLAUDE_CONVERSATION_ID ||
    `ppid-${process.ppid}`
  );
}

// --- Core ---

const ESCALATION_THRESHOLD = 3;

/**
 * Track a hook error silently, with threshold-based stderr escalation.
 *
 * @param hookName - Short identifier (e.g., "posttooluse-reminder")
 * @param message - Error message to log
 * @param sessionId - Optional session ID override (for testing)
 */
export function trackHookError(
  hookName: string,
  message: string,
  sessionId?: string,
): void {
  const sid = sessionId ?? getSessionId();

  // 1. Always log to JSONL file
  logToFile(hookName, message, sid);

  // 2. Increment count and check threshold
  const count = incrementCount(hookName, sid);

  // 3. Escalate on exactly the threshold (one-shot)
  if (count === ESCALATION_THRESHOLD) {
    console.error(
      `[hooks] ${hookName} has failed ${count} times this session — check ~/.claude/logs/hook-errors.jsonl`,
    );
  }
}

/**
 * Append error entry to JSONL log file.
 */
function logToFile(hook: string, message: string, sessionId: string): void {
  try {
    const logDir = getLogDir();
    if (!existsSync(logDir)) {
      mkdirSync(logDir, { recursive: true, mode: 0o755 });
    }

    const entry: HookErrorEntry = {
      ts: new Date().toISOString(),
      hook,
      message,
      session_id: sessionId,
    };

    appendFileSync(getLogFile(), JSON.stringify(entry) + "\n");
  } catch {
    // Graceful degradation - tracking failure must not crash hook
  }
}

/**
 * Increment and return the error count for a hook in this session.
 */
function incrementCount(hookName: string, sessionId: string): number {
  const key = `${sessionId}:${hookName}`;
  const countsFile = getCountsFile();

  try {
    let counts: ErrorCounts = {};

    if (existsSync(countsFile)) {
      const raw = readFileSync(countsFile, "utf8");
      counts = JSON.parse(raw);
    }

    counts[key] = (counts[key] || 0) + 1;
    writeFileSync(countsFile, JSON.stringify(counts));

    return counts[key];
  } catch {
    // If counts file is corrupted, start fresh
    try {
      const fresh: ErrorCounts = { [key]: 1 };
      writeFileSync(countsFile, JSON.stringify(fresh));
      return 1;
    } catch {
      // Total failure - return 1 (silent, no escalation)
      return 1;
    }
  }
}

// --- Query (for Stop hook summary) ---

/**
 * Read all errors for a given session from the JSONL log.
 * Returns entries grouped by hook name.
 */
export function getSessionErrors(
  sessionId?: string,
): Map<string, HookErrorEntry[]> {
  const sid = sessionId ?? getSessionId();
  const result = new Map<string, HookErrorEntry[]>();

  try {
    const logFile = getLogFile();
    if (!existsSync(logFile)) return result;

    const lines = readFileSync(logFile, "utf8").trim().split("\n");

    for (const line of lines) {
      if (!line) continue;
      try {
        const entry: HookErrorEntry = JSON.parse(line);
        if (entry.session_id === sid) {
          const existing = result.get(entry.hook) || [];
          existing.push(entry);
          result.set(entry.hook, existing);
        }
      } catch {
        // Skip malformed lines
      }
    }
  } catch {
    // Graceful degradation
  }

  return result;
}
