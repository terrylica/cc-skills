/**
 * Per-sub-hook timing for the itp-hooks orchestrators, written only inside an operator-opened, self-closing window.
 *
 * The four orchestrators (Bash guards, PreToolUse and PostToolUse Write/Edit, Stop) run 57 sub-hooks between them;
 * Claude Code records nothing for a hook that prints nothing, and the orchestrators measured each sub-hook's time and
 * threw it away. This module keeps that number, and nothing else: orchestrator, event, sub-hook name, tool name, the
 * tool_use_id and session id (to join with transcripts), elapsed milliseconds, the verdict and whether it timed out
 * or threw. Never a command, file path, file content or prompt: the record is built from a fixed key list.
 *
 * The window: lines are appended to <dir>/timing-<YYYY-MM-DD>.jsonl only while <dir>/timing-window.json exists and its
 * "until" (ISO date or date-time) is in the future, so a window closes on its own date with no settings change.
 * <dir> is $ITP_HOOKS_HOOK_CENSUS_DIR or ~/.claude/state/hook-census. Read by scripts/hook-census.ts (`timing`).
 *
 * Fail-open by construction: any error here is swallowed, because a measurement must never change a hook's verdict.
 */
import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type SubhookVerdict = "allow" | "deny" | "ask" | "context" | "block" | "noop" | "timeout" | "error";

export interface SubhookTimingRecord {
  orchestrator: string;
  event: string;
  subhook: string;
  toolName?: string | undefined;
  toolUseId?: string | undefined;
  sessionId?: string | undefined;
  elapsedMs: number;
  verdict: SubhookVerdict;
  timedOut?: boolean | undefined;
  errored?: boolean | undefined;
}

/** The only keys ever written; anything else a caller passes is dropped. */
export const SUBHOOK_TIMING_KEYS = [
  "orchestrator",
  "event",
  "subhook",
  "toolName",
  "toolUseId",
  "sessionId",
  "elapsedMs",
  "verdict",
  "timedOut",
  "errored",
] as const;

export function hookCensusDir(): string {
  return process.env.ITP_HOOKS_HOOK_CENSUS_DIR || join(homedir(), ".claude", "state", "hook-census");
}

let cachedWindow: { dir: string; open: boolean } | undefined;

/** True while timing-window.json exists with a future "until". Cached per process (hooks are short-lived). */
export function timingWindowOpen(dir: string = hookCensusDir(), now: number = Date.now()): boolean {
  if (cachedWindow?.dir === dir) return cachedWindow.open;
  let open = false;
  try {
    const parsed = JSON.parse(readFileSync(join(dir, "timing-window.json"), "utf8")) as { until?: unknown };
    const until = typeof parsed.until === "string" ? Date.parse(parsed.until) : Number.NaN;
    open = Number.isFinite(until) && until > now;
  } catch {
    open = false;
  }
  cachedWindow = { dir, open };
  return open;
}

/** Test seam: forget the cached window decision. */
export function resetTimingWindowCache(): void {
  cachedWindow = undefined;
}

/** Keep only the allowed keys, with sane types; never throws. */
export function sanitizeSubhookTimingRecord(record: SubhookTimingRecord): Record<string, unknown> {
  const out: Record<string, unknown> = { ts: new Date().toISOString() };
  const source = record as unknown as Record<string, unknown>;
  for (const key of SUBHOOK_TIMING_KEYS) {
    const value = source[key];
    if (value === undefined) continue;
    if (key === "elapsedMs") {
      if (typeof value === "number" && Number.isFinite(value)) out[key] = Math.round(value * 10) / 10;
      continue;
    }
    if (key === "timedOut" || key === "errored") {
      if (typeof value === "boolean") out[key] = value;
      continue;
    }
    if (typeof value === "string") out[key] = value.slice(0, 120);
  }
  return out;
}

/** Append one timing line when the window is open. Fail-open: never throws, never blocks a verdict. */
export function recordSubhookTiming(record: SubhookTimingRecord, dir: string = hookCensusDir()): void {
  try {
    if (!timingWindowOpen(dir)) return;
    mkdirSync(dir, { recursive: true });
    const line = sanitizeSubhookTimingRecord(record);
    const day = String(line.ts).slice(0, 10);
    appendFileSync(join(dir, `timing-${day}.jsonl`), `${JSON.stringify(line)}\n`);
  } catch {
    // A measurement must never change what a hook decides.
  }
}
