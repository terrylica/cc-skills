#!/usr/bin/env bun
/**
 * stop-hook-error-summary.ts - Session-end hook error aggregate report
 *
 * Stop hook that reads hook-errors.jsonl for the current session and
 * outputs a summary if any errors occurred. Uses additionalContext for
 * informational, non-blocking output.
 *
 * Registration: Stop hook in ~/.claude/settings.json and hooks.json
 */

import { getSessionErrors, getSessionId } from "./lib/hook-error-tracker.ts";

function main(): void {
  const sessionId = getSessionId();
  const errorsByHook = getSessionErrors(sessionId);

  if (errorsByHook.size === 0) {
    // No errors this session - output empty JSON (no noise)
    console.log(JSON.stringify({}));
    return;
  }

  // Build summary
  let totalErrors = 0;
  const hookSummaries: string[] = [];

  for (const [hook, entries] of errorsByHook) {
    totalErrors += entries.length;
    const lastError = entries[entries.length - 1];
    // Truncate long messages
    const lastMsg =
      lastError.message.length > 60
        ? lastError.message.slice(0, 57) + "..."
        : lastError.message;
    hookSummaries.push(`  ${hook}: ${entries.length} errors — last: "${lastMsg}"`);
  }

  const summary = [
    `[hooks] Session error summary (${errorsByHook.size} hook${errorsByHook.size > 1 ? "s" : ""}, ${totalErrors} error${totalErrors > 1 ? "s" : ""}):`,
    ...hookSummaries,
    `Details: ~/.claude/logs/hook-errors.jsonl`,
  ].join("\n");

  // Output as Stop hook JSON with additionalContext
  const output = {
    additionalContext: summary,
  };

  console.log(JSON.stringify(output));
}

try {
  main();
} catch {
  // Graceful degradation - summary failure must not block session end
  console.log(JSON.stringify({}));
}
