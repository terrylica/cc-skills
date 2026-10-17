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
 * HOW IT RUNS NOW (2026-10-17). This module is a LIBRARY of pretooluse-pueue-wrap-guard.ts, the one
 * hook allowed to rewrite a Bash command. From 2026-10-01 it ran inside the Bash guard orchestrator,
 * which does not apply `updatedInput` (anthropics/claude-code#15897), so its rewrite was dropped on
 * every call while the deny path (pueue down) and the `pueued -d` side effect still fired. Folding it
 * into the rewriting hook makes the documented behaviour real again, for the case the incident was
 * about: a BACKGROUNDED cargo (`cargo bench … &`), plus any cargo command marked CARGO-TTY-WRAP.
 * Foreground cargo is not wrapped: pueue-wrap-guard's NEVER_WRAP already lists cargo's subcommands
 * as fast local commands, and that is what has been in force since 2026-10-01. The wrapper now quotes
 * the command as one argument, so `cargo test && cargo bench &` cannot leak `&&` outside pueue.
 *
 * Reference: https://github.com/anthropics/claude-code/issues/11898
 * ADR: docs/adr/2026-02-23-cargo-tty-suspension-prevention.md
 */

import { allow, allowWithInput, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { buildPueueWrapper } from "./lib/pueue-safe-wrap.ts";

/** Cargo commands known to spawn heavy subprocesses */
const CARGO_COMMANDS = /^\s*cargo\s+(bench|test|build|run|check)\b/i;

/** Already backgrounded or detached (properly isolated with nohup, stdin redirect, etc.)
 *  NOTE: Bare & IS the problem case — we want to intercept those!
 *  This catches commands already wrapped for safety.
 */
const ALREADY_DETACHED = /(?:^|\s)nohup\s|>\s*\/dev\/null|<\s*\/dev\/null|\btmux\s|\bscreen\s|>\s*\/tmp\//i;

// Iter-109: migrated to the iter-107 canonical shared escape-hatch-marker
// detection helper. Behavior-preserving: BOTH markers (opt-out SKIP and
// opt-in WRAP) detected file-wide with CASE_INSENSITIVE matching (preserves
// pre-iter-109 `/i` flag on both regexes). This is the first hook in the
// iter-107+ migration cohort to use TWO marker configurations — proves the
// helper composes cleanly for multi-marker hooks.
import {
  hasFileWideEscapeHatchMarkerInContent,
  type EscapeHatchMarkerDetectionConfiguration,
} from "./lib/escape-hatch-marker-detection-iter107.ts";
const CARGO_TTY_GUARD_OPT_OUT_SKIP_ESCAPE_HATCH_CONFIGURATION: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "caseSensitivityMode"
> = {
  markerNameTokenIncludingSuffix: "CARGO-TTY-SKIP",
  caseSensitivityMode: "CASE_INSENSITIVE",
};
const CARGO_TTY_GUARD_OPT_IN_FORCE_WRAP_ESCAPE_HATCH_CONFIGURATION: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "caseSensitivityMode"
> = {
  markerNameTokenIncludingSuffix: "CARGO-TTY-WRAP",
  caseSensitivityMode: "CASE_INSENSITIVE",
};

/** A trailing `&`: the command is backgrounded in the Bash tool's shell. */
const BACKGROUNDED = /\s&\s*$/;

/**
 * Does this cargo command need pueue isolation?
 *
 * Yes for a backgrounded cargo (`cargo bench … &`), the case anthropics/claude-code#11898 is about,
 * and for any cargo command marked CARGO-TTY-WRAP. No when it is already detached (nohup, stdin
 * from /dev/null, tmux, screen, output to /tmp), marked CARGO-TTY-SKIP, or in the foreground.
 */
export function cargoCommandNeedsPueueIsolation(command: string): boolean {
  if (!CARGO_COMMANDS.test(command)) return false;
  if (ALREADY_DETACHED.test(command)) return false;
  if (hasFileWideEscapeHatchMarkerInContent(command, CARGO_TTY_GUARD_OPT_OUT_SKIP_ESCAPE_HATCH_CONFIGURATION)) return false;
  if (hasFileWideEscapeHatchMarkerInContent(command, CARGO_TTY_GUARD_OPT_IN_FORCE_WRAP_ESCAPE_HATCH_CONFIGURATION)) return true;
  return BACKGROUNDED.test(command);
}

/**
 * Preflight: ensure PUEUE daemon is running.
 * Tries `pueue status` first. If that fails, attempts `pueued -d` to start it.
 * Returns true if PUEUE is available after preflight.
 */
export function ensurePueueDaemon(): boolean {
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
 * Task id: `--print-task-id` prints the bare id; the wrapper keeps only a line
 * that is all digits (the earlier GNU-only `sed 's/\x1b…//'` did nothing on
 * macOS's BSD sed). The wrapper ends with the TASK's exit code, read from
 * `pueue status --json`, because `pueue wait` exits 0 for a failed task.
 *
 * No nohup fallback: nohup + </dev/null does NOT prevent cargo from opening
 * /dev/tty directly via libc open(). PUEUE process isolation is the ONLY
 * reliable protection. If PUEUE is unavailable, the command is denied.
 */
export function buildSafeWrapper(command: string, cwd: string): string {
  // Remove trailing & from command (if present): pueue is the background now.
  const cleanCommand = command.replace(/\s+&\s*$/, "");
  // One quoted argument (lib/pueue-safe-wrap.ts): pasting it unquoted after `--` let `&&`, `|` and
  // quotes in the command be parsed by the outer shell. No run-directly fallback, for the reason
  // above: without pueue the command is exactly the one that suspends the session.
  return buildPueueWrapper({ command: cleanCommand, cwd, onQueueFailure: "fail", label: "cargo-tty-guard" });
}

export async function main() {
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
  if (!cargoCommandNeedsPueueIsolation(command)) {
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

// Standalone entry point. The Bash orchestrator (#111) imports `main` and runs it in-process.
if (import.meta.main) void main().catch((err) => {
  trackHookError(
    "pretooluse-cargo-tty-guard",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
