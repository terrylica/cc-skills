#!/usr/bin/env bun
/**
 * PreToolUse hook: Pueue Auto-Wrap Guard
 *
 * Wraps known long-running Bash commands with pueue for CLI telemetry.
 * Uses allowlist approach: ONLY wraps commands matching LONG_RUNNING_PATTERNS.
 * All other commands pass through unchanged.
 *
 * Two tiers:
 *   Allow — everything by default → allow() with no updatedInput
 *   Wrap  — known long-running patterns → allow + updatedInput with synchronous pueue wrapper
 *
 * IMPORTANT: This MUST be the LAST PreToolUse entry in hooks.json.
 * Reason: GitHub #15897 — multi-hook updatedInput aggregation bug means the
 * last hook's updatedInput wins unconditionally (even if undefined).
 *
 * Opt-in:  # PUEUE-WRAP comment forces wrapping for any command
 * Opt-out: # PUEUE-SKIP comment prevents wrapping even for long-running patterns
 *
 * Reference: /plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897 (updatedInput aggregation bug)
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/11282 (ask + updatedInput broken)
 */

import { allow, output, parseStdinOrAllow } from "./pretooluse-helpers.ts";

/** Opt-in escape hatch — force wrapping */
const WRAP_COMMENT = /# *PUEUE-WRAP/i;

/** Opt-out escape hatch — prevent wrapping */
const SKIP_COMMENT = /# *PUEUE-SKIP/i;

/** Commands that are already pueue-related */
const PUEUE_COMMANDS = /^\s*(?:pueue|pueued)\b/i;

/** Already backgrounded commands */
const BACKGROUNDED = /\bnohup\s|&\s*$|\bscreen\s|\btmux\s/i;

/**
 * Known long-running patterns that benefit from pueue wrapping.
 * Mirrors posttooluse-reminder.ts detection patterns (SSoT alignment).
 */
const LONG_RUNNING_PATTERNS = [
  // Data population/cache scripts
  /populate[_-]?(cache|full|data)/i,
  /cache[_-]?populat/i,
  /bulk[_-]?(insert|load|import)/i,

  // Batch processing with multiple items
  /--phase\s+\d/i,
  /for\s+\w+\s+in.*;\s*do/i,
  /while.*;\s*do/i,

  // SSH with long-running remote commands
  /ssh\s+\S+\s+["']?.*populate/i,
  /ssh\s+\S+\s+["']?.*--phase/i,
];

/**
 * Check if a command matches known long-running patterns.
 * Returns true ONLY for commands that should be wrapped.
 */
function shouldWrap(command: string): boolean {
  // Opt-in: explicit wrap request
  if (WRAP_COMMENT.test(command)) return true;

  // Opt-out: explicit skip request
  if (SKIP_COMMENT.test(command)) return false;

  // Never wrap pueue commands themselves
  if (PUEUE_COMMANDS.test(command)) return false;

  // Never wrap already-backgrounded commands
  if (BACKGROUNDED.test(command)) return false;

  // Check against known long-running patterns
  return LONG_RUNNING_PATTERNS.some((p) => p.test(command));
}

/**
 * Build the synchronous pueue wrapper command.
 * Pattern: queue → wait → log (stdout flows back to Claude Code)
 */
function buildWrappedCommand(command: string, cwd: string): string {
  // Escape single quotes in command for shell safety
  const escapedCommand = command.replace(/'/g, "'\\''");
  const escapedCwd = cwd.replace(/'/g, "'\\''");

  return (
    `TASK_ID=$(pueue add --print-task-id -w '${escapedCwd}' -- ${escapedCommand} 2>/dev/null | grep -oE '^[0-9]+$' | tail -1) && ` +
    `[ -n "$TASK_ID" ] && ` +
    `pueue wait "$TASK_ID" --quiet && ` +
    `pueue log "$TASK_ID" --full`
  );
}

async function main() {
  const input = await parseStdinOrAllow("PUEUE-WRAP-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {}, cwd } = input;

  // Only process Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Allowlist check: only wrap known long-running commands
  if (!shouldWrap(command)) {
    allow();
    return;
  }

  // Check pueue daemon is running (fail-open if down)
  const daemonCheck = Bun.spawnSync(["pueue", "status"], {
    stdout: "ignore",
    stderr: "ignore",
  });
  if (daemonCheck.exitCode !== 0) {
    // Daemon not running — allow original command through
    allow();
    return;
  }

  // Wrap tier: rewrite command with pueue wrapper
  const workingDir = cwd || process.cwd();
  const wrappedCommand = buildWrappedCommand(command, workingDir);

  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: {
        command: wrappedCommand,
      },
    },
  });
}

main().catch((err) => {
  console.error(`[PUEUE-WRAP-GUARD] Unhandled error: ${err.message}`);
  allow();
});
