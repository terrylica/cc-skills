#!/usr/bin/env bun
/**
 * Stop hook: autonomous-loop stall detector with async rewake
 *
 * Detects when a LOOP_CONTRACT.md-driven session ends without calling a valid
 * waker (ScheduleWakeup, Monitor, Agent, TeamCreate) and the contract is still
 * in an active state. On stall, exits code 2 under asyncRewake to force the
 * model to wake and schedule a waker or flip status honestly.
 *
 * Enforcement layer for the autonomous-loop skill's "Mandatory end-of-firing
 * decision" rule. The skill documents it; this hook enforces it.
 *
 * Gates (all must pass to fire stall):
 *   1. LOOP_CONTRACT.md exists in cwd
 *   2. frontmatter status is NOT {done, saturated, paused, completed, stopped}
 *   3. Session's last user message was a /loop or /autonomous-loop invocation
 *      (distinguishes loop firings from manual sessions in the same project)
 *   4. Last assistant tool_use was NOT a valid waker
 *
 * Escape hatch: set CLAUDE_LOOP_STALL_GUARD_DISABLE=1 to skip.
 *
 * Registration: Stop hook in itp-hooks/hooks/hooks.json with asyncRewake: true
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

interface HookInput {
  session_id?: string;
  transcript_path?: string;
  cwd?: string;
}

const VALID_WAKERS = new Set([
  "ScheduleWakeup", // Tier 2/3 timer
  "Monitor", // Tier 1 reactive waker
  "Agent", // Chain-in-turn via subagent dispatch (Tier 0)
  "TeamCreate", // Multi-agent team spawn (Tier 0)
  "SendMessage", // Team resume (Tier 0)
]);

const TERMINAL_STATES = new Set([
  "done",
  "saturated",
  "completed",
  "complete",
  "paused",
  "stopped",
]);

// Cap transcript size to avoid OOM on huge sessions. 200 MB is plenty for typical loops.
const MAX_TRANSCRIPT_BYTES = 200 * 1024 * 1024;

function noop(): never {
  console.log(JSON.stringify({}));
  process.exit(0);
}

async function main() {
  // Escape hatch (single-purpose hook; env var IS the config surface) // SSoT-OK
  if (process.env.CLAUDE_LOOP_STALL_GUARD_DISABLE === "1") noop();

  // Parse stdin JSON
  let input: HookInput;
  try {
    const raw = await Bun.stdin.text();
    input = JSON.parse(raw);
  } catch {
    noop();
  }

  const cwd = input!.cwd || process.cwd();
  const contractPath = join(cwd, "LOOP_CONTRACT.md");

  // Gate 1: LOOP_CONTRACT.md must exist
  if (!existsSync(contractPath)) noop();

  // Gate 2: status must not be a terminal state
  let contract: string;
  try {
    contract = readFileSync(contractPath, "utf8");
  } catch {
    noop();
  }

  const fmMatch = contract!.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) noop();
  const frontmatter = fmMatch![1];

  const statusMatch = frontmatter.match(/^status:\s*["']?(\S+?)["']?\s*$/m);
  const status = statusMatch ? statusMatch[1].toLowerCase() : "active";

  if (TERMINAL_STATES.has(status)) noop();

  // Gate 3: transcript check — was this session a /loop firing?
  const transcriptPath = input!.transcript_path;
  if (!transcriptPath || !existsSync(transcriptPath)) noop();

  try {
    const size = statSync(transcriptPath!).size;
    if (size > MAX_TRANSCRIPT_BYTES) noop();
  } catch {
    noop();
  }

  let transcriptContent: string;
  try {
    transcriptContent = readFileSync(transcriptPath!, "utf8");
  } catch {
    noop();
  }

  const lines = transcriptContent!.trim().split("\n");

  // Find the LAST real user message (skip tool_result synthetic messages)
  let lastRealUserContent = "";
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const entry = JSON.parse(lines[i]);
      if (entry.type !== "user" || !entry.message?.content) continue;

      const content =
        typeof entry.message.content === "string"
          ? entry.message.content
          : JSON.stringify(entry.message.content);

      // tool_result messages are synthetic; they include tool_use_id
      if (content.includes('"tool_use_id"') || content.includes('"tool_result"')) {
        continue;
      }

      lastRealUserContent = content;
      break;
    } catch {
      // Malformed line — skip
    }
  }

  const isLoopFiring =
    lastRealUserContent.includes("/loop") ||
    lastRealUserContent.includes("/autonomous-loop:start") ||
    lastRealUserContent.includes("autonomous-loop:start");

  if (!isLoopFiring) noop();

  // Gate 4: find the last assistant tool_use
  let lastToolUse: string | null = null;
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const entry = JSON.parse(lines[i]);
      if (entry.type !== "assistant" || !entry.message?.content) continue;

      // Scan content array for tool_use entries, take the last one in this message
      const toolUses: string[] = [];
      for (const c of entry.message.content) {
        if (c.type === "tool_use" && typeof c.name === "string") {
          toolUses.push(c.name);
        }
      }
      if (toolUses.length > 0) {
        lastToolUse = toolUses[toolUses.length - 1];
        break;
      }
    } catch {
      // Malformed line — skip
    }
  }

  if (lastToolUse && VALID_WAKERS.has(lastToolUse)) noop();

  // STALL DETECTED — emit diagnostic and exit 2 for asyncRewake
  const diagnostic = [
    `Autonomous loop stall detected.`,
    ``,
    `Contract: ${contractPath}`,
    `Status:   ${status}`,
    `Last assistant tool_use: ${lastToolUse ?? "(none — firing ended text-only)"}`,
    ``,
    `Per autonomous-loop Mandatory end-of-firing decision, every active-loop`,
    `firing must end with exactly one of these as its literal final tool call:`,
    ``,
    `  1. Chain in-turn (next queue item's first tool call — via Agent or direct)`,
    `  2. Monitor(...)        — reactive waker on a background stream`,
    `  3. ScheduleWakeup(...) — fresh timer (supersedes any pending wake)`,
    `  4. Flip status: SATURATED + PushNotification (3 null-rescues detected)`,
    `  5. Flip status: DONE   + no waker (exit condition met)`,
    ``,
    `RESUME NOW:`,
    `  1. Read ${contractPath}`,
    `  2. Run Phase 3 Revise — update iteration number, Current State, Revision Log`,
    `  3. Commit the contract revision atomically`,
    `  4. Run Phase 4 — pick the cheapest waker tier that fits and call it`,
    `  5. If the queue is empty AND exit condition is met, flip status: DONE and stop honestly`,
    ``,
    `Do NOT defer to a pending prior ScheduleWakeup — it reads stale state.`,
    `If you believe the loop should stop, flip status: DONE or SATURATED explicitly.`,
  ].join("\n");

  console.error(diagnostic);
  process.exit(2);
}

main().catch(() => {
  noop();
});
