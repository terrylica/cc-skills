#!/usr/bin/env bun
/**
 * PreToolUse hook: Cargo TTY Suspension Guard
 *
 * Problem: Running `cargo bench` or `cargo test` in the background within
 * Claude Code causes immediate suspension with "suspended (tty input)".
 *
 * Root cause: Cargo spawns subprocesses that inherit stdin from Claude Code.
 * When backgrounding, these subprocesses create TTY contention → SIGSTOP.
 *
 * Solution: Automatically redirect cargo commands to PUEUE (background daemon)
 * to prevent subprocess stdin inheritance and TTY conflicts.
 *
 * Patterns detected:
 *   - cargo bench ... &
 *   - cargo test ... &
 *   - cargo build ... &
 *   - cargo run ... &
 *
 * Behavior:
 *   1. Detect unsafe cargo background commands
 *   2. Auto-redirect to PUEUE with user warning
 *   3. Return pueue wait wrapper for synchronous execution
 *   4. Fallback: wrap with nohup + stdin redirect if PUEUE unavailable
 *
 * Reference: https://github.com/anthropics/claude-code/issues/11898
 * ADR: docs/adr/2026-02-23-cargo-tty-suspension-prevention.md
 */

import { allow, output, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

/** Cargo commands known to spawn heavy subprocesses */
const CARGO_COMMANDS = /^\s*cargo\s+(bench|test|build|run|check)\b/i;

/** Already backgrounded or detached (properly isolated with nohup, stdin redirect, etc.)
 *  NOTE: Bare & IS the problem case — we want to intercept those!
 *  This catches commands already wrapped for safety.
 */
const ALREADY_DETACHED = /(?:^|\s)nohup\s|>\s*\/dev\/null|<\s*\/dev\/null|\btmux\s|\bscreen\s|>\s*\/tmp\//i;

/** Opt-out escape hatch */
const SKIP_COMMENT = /# *CARGO-TTY-SKIP/i;

/** Opt-in escape hatch */
const FORCE_WRAP_COMMENT = /# *CARGO-TTY-WRAP/i;

/**
 * Detect if cargo command is being backgrounded unsafely.
 * Returns true if command ends with & (or similar backgrounding).
 */
function isUnsafeBackground(command: string): boolean {
  // Must be a cargo command
  if (!CARGO_COMMANDS.test(command)) return false;

  // Already detached or wrapped
  if (ALREADY_DETACHED.test(command)) return false;

  // Explicit opt-out
  if (SKIP_COMMENT.test(command)) return false;

  // Explicit force wrap
  if (FORCE_WRAP_COMMENT.test(command)) return true;

  // Check if trailing & (the problematic pattern)
  return /\s+&\s*$/.test(command);
}

/**
 * Build safe PUEUE wrapper for cargo commands.
 * Pattern: queue → wait → capture output
 */
function buildSafeWrapper(command: string, cwd: string): string {
  // Remove trailing & from command
  const cleanCommand = command.replace(/\s+&\s*$/, "");

  // Escape single quotes for shell
  const escapedCommand = cleanCommand.replace(/'/g, "'\\''");
  const escapedCwd = cwd.replace(/'/g, "'\\''");

  // Build pueue wrapper with proper output capture
  // Returns: queue the job, wait for it, stream the output
  return (
    `(TASK_ID=$(pueue add --print-task-id -w '${escapedCwd}' -- ${escapedCommand} 2>&1 | grep -oE '^[0-9]+$' | head -1) && ` +
    `if [ -n "$TASK_ID" ]; then pueue wait "$TASK_ID" --quiet 2>/dev/null && echo "✓ PUEUE task $TASK_ID completed" && pueue log "$TASK_ID" --full 2>/dev/null; fi) || ` +
    `(echo "⚠️ PUEUE unavailable, falling back to nohup" && nohup ${cleanCommand} </dev/null >/dev/null 2>&1 &)`
  );
}

/**
 * Build fallback nohup wrapper (if PUEUE daemon not running).
 * Pattern: redirect stdin to /dev/null to prevent subprocess inheritance
 */
function buildNohupFallback(command: string): string {
  // Remove trailing &
  const cleanCommand = command.replace(/\s+&\s*$/, "");
  // Wrap with nohup + stdin redirection
  return `nohup ${cleanCommand} </dev/null >/dev/null 2>&1 &`;
}

async function main() {
  const input = await parseStdinOrAllow("CARGO-TTY-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {}, cwd } = input;

  // Only process Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Check if this is an unsafe cargo background command
  if (!isUnsafeBackground(command)) {
    allow();
    return;
  }

  // Check if PUEUE daemon is running
  const daemonCheck = Bun.spawnSync(["pueue", "status"], {
    stdout: "ignore",
    stderr: "ignore",
  });

  const workingDir = cwd || process.cwd();
  let wrappedCommand: string;

  if (daemonCheck.exitCode === 0) {
    // PUEUE is available — use it (best option)
    wrappedCommand = buildSafeWrapper(command, workingDir);
    console.warn(
      "🛡️  Cargo TTY Guard: Redirecting cargo command to PUEUE daemon",
    );
    console.warn("   (Prevents TTY suspension from subprocess stdin conflicts)");
  } else {
    // PUEUE not available — fallback to nohup
    wrappedCommand = buildNohupFallback(command);
    console.warn(
      "⚠️  Cargo TTY Guard: PUEUE daemon not running, using nohup fallback",
    );
  }

  // Emit the transformed command
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
  trackHookError(
    "pretooluse-cargo-tty-guard",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
