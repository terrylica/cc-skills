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
 *   2. Preflight: ensure PUEUE daemon is running (auto-start if down)
 *   3. Auto-redirect to PUEUE with user warning
 *   4. Return pueue wait wrapper for synchronous execution
 *   5. If PUEUE cannot be started, DENY the command (nohup is unsafe —
 *      it doesn't prevent cargo from opening /dev/tty directly)
 *
 * Reference: https://github.com/anthropics/claude-code/issues/11898
 * ADR: docs/adr/2026-02-23-cargo-tty-suspension-prevention.md
 */

import { allow, allowWithInput, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

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
 * Detect if cargo command needs TTY protection.
 * Now wraps BOTH foreground and background cargo commands with PUEUE
 * to prevent subprocess from directly opening /dev/tty and causing suspension.
 *
 * Previously only protected background commands (`&`), but `< /dev/null`
 * doesn't prevent cargo from explicitly opening /dev/tty via libc open().
 * PUEUE process isolation is the only reliable protection.
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

  // NOW: Wrap ALL cargo commands (foreground and background) for TTY protection
  // This prevents cargo from opening /dev/tty directly, which bypasses stdin redirect
  return true;
}

/**
 * Preflight: ensure PUEUE daemon is running.
 * Tries `pueue status` first. If that fails, attempts `pueued -d` to start it.
 * Returns true if PUEUE is available after preflight.
 */
function ensurePueueDaemon(): boolean {
  const check = Bun.spawnSync(["pueue", "status"], {
    stdout: "ignore",
    stderr: "ignore",
  });
  if (check.exitCode === 0) return true;

  // Daemon not running — attempt auto-start
  console.warn("🔄 Cargo TTY Guard: PUEUE daemon not running, auto-starting...");
  const start = Bun.spawnSync(["pueued", "-d"], {
    stdout: "ignore",
    stderr: "ignore",
  });
  if (start.exitCode !== 0) return false;

  // Verify daemon is responsive after start
  const verify = Bun.spawnSync(["pueue", "status"], {
    stdout: "ignore",
    stderr: "ignore",
  });
  return verify.exitCode === 0;
}

/**
 * Build safe PUEUE wrapper for cargo commands (foreground and background).
 * Provides full process isolation to prevent cargo from opening /dev/tty directly.
 * Pattern: queue → wait → capture output
 *
 * Works for:
 * - Foreground: `cargo test -p module` → queued, waits synchronously
 * - Background: `cargo test -p module &` → queued, waits synchronously (& removed)
 *
 * ANSI stripping: pueue can emit color codes even with --print-task-id when
 * its config has color output enabled. We strip ANSI escape sequences with sed
 * before extracting the task ID to prevent empty/corrupt IDs.
 *
 * No nohup fallback: nohup + </dev/null does NOT prevent cargo from opening
 * /dev/tty directly via libc open(). PUEUE process isolation is the ONLY
 * reliable protection. If PUEUE is unavailable, the command is denied.
 */
function buildSafeWrapper(command: string, cwd: string): string {
  // Remove trailing & from command (if present)
  const cleanCommand = command.replace(/\s+&\s*$/, "");

  // Note: No quote escaping needed - the '--' in pueue separates options from command
  // pueue passes everything after '--' as the command string as-is
  const escapedCwd = cwd.replace(/'/g, "'\\''");

  // Strip ANSI escape codes from pueue output before extracting task ID.
  // sed pattern removes CSI sequences (\x1b[...m) that pueue emits with color enabled.
  const stripAnsi = `sed 's/\\x1b\\[[0-9;]*m//g'`;

  // Build pueue wrapper with proper output capture
  // Returns: queue the job, wait for it, stream the output
  return (
    `TASK_ID=$(pueue add --print-task-id -w '${escapedCwd}' -- ${cleanCommand} 2>/dev/null | ${stripAnsi} | tail -1 | tr -cd '0-9') && ` +
    `if [ -n "$TASK_ID" ]; then ` +
    `echo "ℹ️  PUEUE task $TASK_ID queued" && ` +
    `pueue wait "$TASK_ID" --quiet 2>/dev/null && ` +
    `echo "✓ PUEUE task $TASK_ID completed" && ` +
    `pueue log "$TASK_ID" 2>/dev/null; ` +
    `else echo "⚠️ PUEUE task ID extraction failed — check pueue status" && exit 1; fi`
  );
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

  // Check if this is a cargo command requiring TTY protection
  // (both foreground and background commands now wrapped with PUEUE)
  if (!isUnsafeBackground(command)) {
    allow();
    return;
  }

  // Preflight: ensure PUEUE daemon is running (auto-start if down)
  if (!ensurePueueDaemon()) {
    // PUEUE cannot be started — DENY the command.
    // nohup fallback is unsafe: </dev/null doesn't prevent cargo from
    // opening /dev/tty directly via libc open(), causing TTY contention
    // that disrupts Claude Code sessions.
    deny(
      "🛡️ Cargo TTY Guard: PUEUE daemon required but not running.\n" +
      "   Cannot safely execute cargo commands without PUEUE process isolation.\n" +
      "   nohup fallback is unsafe (cargo opens /dev/tty directly, causing session kicks).\n\n" +
      "   Fix: run `pueued -d` or `brew services start pueue` to start the daemon,\n" +
      "   then retry this command.\n\n" +
      "   Escape hatch: add `# CARGO-TTY-SKIP` to bypass this guard.",
    );
    return;
  }

  const workingDir = cwd || process.cwd();
  const wrappedCommand = buildSafeWrapper(command, workingDir);

  console.warn(
    "🛡️  Cargo TTY Guard: Redirecting cargo command to PUEUE daemon",
  );
  console.warn("   (Prevents TTY suspension from subprocess stdin conflicts)");

  // Emit the transformed command (Zod-validated against BashSchema.strict())
  allowWithInput("CARGO-TTY-GUARD", tool_name, { command: wrappedCommand });
}

main().catch((err) => {
  trackHookError(
    "pretooluse-cargo-tty-guard",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
