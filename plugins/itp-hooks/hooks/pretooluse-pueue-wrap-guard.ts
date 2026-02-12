#!/usr/bin/env bun
/**
 * PreToolUse hook: Pueue Auto-Wrap Guard
 *
 * Silently wraps non-trivial Bash commands with pueue for universal CLI telemetry.
 * Uses `permissionDecision: "allow"` + `updatedInput` for invisible command rewriting.
 *
 * Two tiers:
 *   Skip  — read-only, trivial, interactive, pueue commands → allow() with no updatedInput
 *   Wrap  — everything else → allow + updatedInput with synchronous pueue wrapper
 *
 * IMPORTANT: This MUST be the LAST PreToolUse entry in hooks.json.
 * Reason: GitHub #15897 — multi-hook updatedInput aggregation bug means the
 * last hook's updatedInput wins unconditionally (even if undefined).
 *
 * Escape hatch: # PUEUE-SKIP comment in command
 *
 * Reference: /plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897 (updatedInput aggregation bug)
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/11282 (ask + updatedInput broken)
 */

import { allow, output, parseStdinOrAllow, isReadOnly } from "./pretooluse-helpers.ts";

/** Commands that are already pueue-related */
const PUEUE_COMMANDS = /^\s*(?:pueue|pueued)\b/i;

/** Interactive/credential operations that can't be wrapped */
const INTERACTIVE_PATTERNS = [
  /\bgit\s+commit\b/i,
  /\bgit\s+push\b/i,
  /\bgit\s+pull\b/i,
  /\bgit\s+rebase\b/i,
  /\bgit\s+merge\b/i,
  /\bnano\b|\bvim?\b|\bemacs\b/i,
  /\bpython3?\s*$/i, // bare python REPL
  /\bnode\s*$/i, // bare node REPL
  /\birb\s*$/i,
  /\bssh\s+\S+\s*$/i, // interactive SSH (no command)
];

/** Already backgrounded commands */
const BACKGROUNDED = /\bnohup\s|&\s*$|\bscreen\s|\btmux\s/i;

/** Quick flags that indicate non-executable inspection */
const QUICK_FLAGS = /--status|--plan|--help\b|-h\b|--version\b/i;

/** Documentation/print commands */
const PRINT_ONLY = /^\s*(echo|printf|#)\b/i;

/** Composite task managers that manage their own subprocesses */
const TASK_MANAGERS = /\bmise\s+run\b/i;

/** Minimum command length worth wrapping */
const MIN_COMMAND_LENGTH = 10;

/** Escape hatch comment */
const SKIP_COMMENT = /# *PUEUE-SKIP/i;

function shouldSkip(command: string): boolean {
  // Escape hatch
  if (SKIP_COMMENT.test(command)) return true;

  // Read-only commands (ls, cat, grep, git status, etc.)
  if (isReadOnly(command)) return true;

  // Already using pueue
  if (PUEUE_COMMANDS.test(command)) return true;

  // Quick flags
  if (QUICK_FLAGS.test(command)) return true;

  // Print/documentation only
  if (PRINT_ONLY.test(command)) return true;

  // Already backgrounded
  if (BACKGROUNDED.test(command)) return true;

  // Interactive/credential operations
  for (const pattern of INTERACTIVE_PATTERNS) {
    if (pattern.test(command)) return true;
  }

  // Composite task managers
  if (TASK_MANAGERS.test(command)) return true;

  // Very short commands (pwd, date, whoami, etc.)
  if (command.trim().length < MIN_COMMAND_LENGTH) return true;

  return false;
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
    `TASK_ID=$(pueue add --print-task-id -w '${escapedCwd}' -- ${escapedCommand}) && ` +
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

  // Skip tier: allow without wrapping
  if (shouldSkip(command)) {
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

  // Silent wrap tier: rewrite command with pueue wrapper
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
