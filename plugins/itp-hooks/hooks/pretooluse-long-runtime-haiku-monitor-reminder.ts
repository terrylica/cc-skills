#!/usr/bin/env bun
/**
 * PreToolUse:Bash reminder: a run that may take more than 5 minutes gets intermittent health checks
 * from a background Haiku monitor, and that monitor names the model by the bare `haiku` alias.
 *
 * Motivation (operator, 2026-10-18): a gate that normally takes 7 to 9 minutes ran for 77 minutes,
 * hung, before anyone looked. The operator then had to ask by hand for "intermittent monitoring with
 * haiku 5.5 agent for healthy progress". This reminder makes that the default for every long run.
 *
 * "Always the latest Haiku": the Agent tool's `model: "haiku"` is an ALIAS that Claude Code resolves
 * to the newest Haiku release at call time. A dated id (claude-haiku-4-5-..., "haiku 5.5") is
 * correct the day it is written and stale from the next release on, so the reminder forbids writing
 * one. Nothing here hard-codes a version, so nothing here needs bumping when a new Haiku ships.
 *
 * Soft: it adds context and allows, never denies. Following it is the model's choice, which is the
 * point: whether a run deserves a monitor depends on what it is, and the hook cannot see that.
 *
 * Fires when ANY of these holds (the signals a Bash call carries about its own duration):
 *   - `run_in_background: true` (the harness reports completion, but not a hang);
 *   - an explicit `timeout` above 300000 ms (the caller expects more than 5 minutes);
 *   - `pueue add` at a command position (queued jobs are long by this fleet's convention).
 * At most once per 20 minutes per session, so a burst of background calls produces one reminder.
 *
 * Escape: HAIKU-MONITOR-SKIP anywhere in the command. Fails open.
 * Spoke: docs/long-runtime-haiku-monitor-reminder.md.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { allow, output, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { perUserGateDirectory } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";

/** Runs at or under this long need no monitor; the operator's threshold. */
export const LONG_RUNTIME_THRESHOLD_MS = 5 * 60 * 1000;
/** Minimum gap between two reminders in one session. */
export const REMINDER_COOLDOWN_MS = 20 * 60 * 1000;

const ESCAPE_MARKER = "HAIKU-MONITOR-SKIP";
const PUEUE_ADD_AT_COMMAND_POSITION = /(?:^|[;&|(]\s*|\n\s*)(?:\S+\/)?pueue\s+(?:--?\S+\s+)*add\b/;

export interface BashToolInput {
  command?: string;
  run_in_background?: boolean;
  timeout?: number;
}

/** Why this call is likely to run past the threshold, or null if nothing says it will. */
export function longRuntimeSignal(toolInput: BashToolInput): string | null {
  const command = typeof toolInput.command === "string" ? toolInput.command : "";
  if (command.includes(ESCAPE_MARKER)) return null;
  if (toolInput.run_in_background === true) return "it runs in the background";
  if (typeof toolInput.timeout === "number" && toolInput.timeout > LONG_RUNTIME_THRESHOLD_MS) {
    return `its timeout is ${Math.round(toolInput.timeout / 60000)} minutes`;
  }
  if (PUEUE_ADD_AT_COMMAND_POSITION.test(command)) return "it queues a pueue job";
  return null;
}

/**
 * True when the cooldown has elapsed (and records now). Without a session id there is nothing to key
 * on, so it fires; a filesystem error also fires, because a missed reminder costs more than a repeat.
 */
export function claimCooldown(sessionId: unknown, nowMs: number = Date.now(), baseDir: string = tmpdir()): boolean {
  if (typeof sessionId !== "string" || sessionId === "" || /[/\\]/.test(sessionId)) return true;
  // os.tmpdir() honours TMPDIR: the per-user /var/folders/... on macOS, /tmp on most Linux hosts.
  const directory = perUserGateDirectory(join(baseDir, ".claude-haiku-monitor-reminder"));
  const stamp = join(directory, `${sessionId}.last`);
  try {
    const last = Number(readFileSync(stamp, "utf8"));
    if (Number.isFinite(last) && nowMs - last < REMINDER_COOLDOWN_MS) return false;
  } catch {
    // No stamp yet: first reminder of the session.
  }
  try {
    mkdirSync(directory, { recursive: true });
    writeFileSync(stamp, String(nowMs));
  } catch {
    // Unwritable /tmp: remind anyway.
  }
  return true;
}

export function buildReminder(signal: string): string {
  return [
    `[LONG-RUNTIME-HEALTH-CHECK] This command may run past 5 minutes (${signal}). Do not wait blind: give it intermittent health checks.`,
    "- Start a monitor with the Agent tool: `model: \"haiku\"`, `run_in_background: true`. Write the bare alias `haiku`. It resolves to the newest Haiku release when the agent starts. Never write a dated or numbered id (claude-haiku-4-5-..., \"haiku 5.5\"): a pinned id goes stale at the next release.",
    "- Give the monitor: the PID or pueue task id, the log path, the expected duration, what healthy looks like (the log keeps growing, CPU above zero, a progress counter advancing) and what a stall looks like.",
    "- Cadence: one check about every 4 minutes (`sleep 240` between checks, under the 5-minute prompt-cache window). It ends with its report as its final answer, which reaches you as a completion notification, and it ends only on a stall, a failure, an overrun of about twice the expected duration, or completion.",
    "- The monitor observes and reports. It never kills or restarts anything; you check its report and decide.",
    `- Skip when the run is known to be short or something else already watches it: put ${ESCAPE_MARKER} in the command.`,
  ].join("\n");
}

export async function main() {
  const input = await parseStdinOrAllow("LONG-RUNTIME-HAIKU-MONITOR-REMINDER");
  if (!input) return;
  if (input.tool_name !== "Bash") {
    allow();
    return;
  }
  const signal = longRuntimeSignal((input.tool_input ?? {}) as BashToolInput);
  if (signal === null || !claimCooldown(input.session_id)) {
    allow();
    return;
  }
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: buildReminder(signal),
    },
  });
}

// Standalone entry point. The Bash orchestrator imports `main` and runs it in-process.
if (import.meta.main) void main().catch((err) => {
  trackHookError(
    "pretooluse-long-runtime-haiku-monitor-reminder",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
