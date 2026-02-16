#!/usr/bin/env bun
/**
 * PreToolUse hook: CWD Deletion Guard
 *
 * Prevents commands that would delete the current working directory.
 * When CWD is deleted, the shell becomes permanently broken — every
 * subsequent command (including cd) fails with exit code 1.
 *
 * Two lessons encoded:
 * 1. NEVER rm -rf the CWD without cd-ing elsewhere first
 * 2. For git re-clone operations, prefer git remote set-url + fetch + reset
 *
 * Usage:
 *   Installed via hooks.json in itp-hooks plugin
 *   Escape hatch: # CWD-DELETE-OK comment
 *
 * ADR: /docs/adr/2026-02-09-cwd-deletion-guard.md
 */

import { detectCwdDeletion, formatDenial } from "./cwd-deletion-patterns.mjs";
import { allow, deny, parseStdinOrAllow, isReadOnly, trackHookError } from "./pretooluse-helpers.ts";

async function main() {
  const input = await parseStdinOrAllow("CWD-DELETION-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {}, cwd } = input;

  // Only check Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Skip read-only commands (can't delete anything)
  if (isReadOnly(command)) {
    allow();
    return;
  }

  // Skip if no CWD provided (can't compare)
  if (!cwd) {
    allow();
    return;
  }

  // Skip if command doesn't contain rm (fast path)
  if (!/\brm\b/.test(command)) {
    allow();
    return;
  }

  // Detect CWD deletion
  const result = detectCwdDeletion(command, cwd);

  if (!result.detected) {
    allow();
    return;
  }

  const message = formatDenial(result.target || "unknown", cwd, result.isGitOperation);
  deny(message);
}

main().catch((err) => {
  trackHookError("pretooluse-cwd-deletion-guard", err instanceof Error ? err.message : String(err));
  allow();
});
