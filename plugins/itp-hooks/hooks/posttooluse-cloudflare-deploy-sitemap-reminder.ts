#!/usr/bin/env bun
/**
 * PostToolUse (Bash): after a Cloudflare Workers / Pages deploy command, record it and remind the agent to update
 * the sitemap of every Workers link (operator, 2026-11-15). The Stop subhook stop-cloudflare-sitemap-pending.ts then
 * refuses to end the turn until the sitemap is newer than the deploy. Logic and config: lib/cloudflare-deploy-sitemap.ts.
 *
 * Channel: `{decision:"block", reason}` is this repository's proven Claude-visible PostToolUse channel (ADR
 * 2025-12-17); it does not undo the finished command, it only surfaces the reminder.
 * Escape hatch: `CF-SITEMAP-OK` in the command (a deploy that publishes no link, e.g. a Worker without pages).
 * Fail-open: any error exits 0 silently.
 */

import { isDeployCommand, markCommand, recordDeploy, updateCommand } from "./lib/cloudflare-deploy-sitemap.ts";

async function main(): Promise<void> {
  const raw = await Bun.stdin.text();
  const input = JSON.parse(raw);
  if (input.tool_name !== "Bash") return;
  const cmd: string = input.tool_input?.command ?? "";
  if (cmd.includes("CF-SITEMAP-OK") || !isDeployCommand(cmd)) return;
  recordDeploy({
    at: new Date().toISOString(),
    session: String(input.session_id ?? ""),
    cwd: String(input.cwd ?? ""),
    command: cmd.slice(0, 300),
  });
  const reason =
    "[CF-SITEMAP] A Cloudflare Workers/Pages deploy just ran. Every published link belongs on the sitemap with its " +
    "provenance (operator, 2026-11-15). Once the deploy is recorded in its repository's registry (merged), update " +
    `the sitemap: ${updateCommand()}. If that runs on another machine, then mark it here: ${markCommand()}. ` +
    "The turn cannot end until the sitemap is newer than this deploy. A deploy that publishes no link: add CF-SITEMAP-OK " +
    "to the command next time.";
  console.log(JSON.stringify({ decision: "block", reason }));
}

main().catch(() => process.exit(0));
