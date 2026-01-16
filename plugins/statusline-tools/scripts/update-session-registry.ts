#!/usr/bin/env bun
/**
 * update-session-registry.ts - CLI entry point for session registry updates
 *
 * Usage: bun update-session-registry.ts <session-id> <cwd> [model] [cost] [branch]
 *
 * Called by custom-statusline.sh in fire-and-forget mode.
 * Logs to: ~/.claude/logs/session-registry.jsonl
 */

import { updateRegistry } from "../lib/session-registry";
import { log } from "../lib/logger";

const [sessionId, cwd, model, costStr] = process.argv.slice(2);

if (!sessionId || !cwd) {
  console.error("Usage: bun update-session-registry.ts <session-id> <cwd> [model] [cost]");
  process.exit(1);
}

const cost = costStr ? parseFloat(costStr) : undefined;

try {
  const success = updateRegistry(sessionId, cwd, model, cost);
  if (!success) {
    // Non-fatal - registry update skipped (disabled, CC writes detected, etc.)
    process.exit(0);
  }
} catch (e) {
  // Log error and exit gracefully - must not affect statusline
  log("warn", "Registry update threw exception", {
    session_id: sessionId,
    project_path: cwd,
    event: "update_exception",
    ctx: { message: e instanceof Error ? e.message : String(e) },
  });
  console.error("[session-registry] Update failed:", e);
  process.exit(0); // Exit 0 to not block statusline
}
