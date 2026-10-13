#!/usr/bin/env bun
/**
 * PreToolUse hook: Pueue Auto-Wrap Guard + 1Password Token Injection
 *
 * Two responsibilities (combined due to GitHub #15897):
 *
 * 1. OP TOKEN INJECTION: Prepends OP_SERVICE_ACCOUNT_TOKEN for commands
 *    targeting the "Claude Automation" 1Password vault. Avoids biometric prompts.
 *    Token source: OP_SA_TOKEN_CMD or OP_SA_TOKEN_FILE (see lib/op-token-injector.ts)
 *
 * 2. PUEUE WRAPPING: Wraps known long-running Bash commands with pueue.
 *    Uses allowlist approach: ONLY wraps commands matching LONG_RUNNING_PATTERNS.
 *
 * Pipeline: originalCommand → maybeInjectOpToken → shouldWrap → spool + wrap
 *           (lib/pueue-wrap-transport.ts) → `<shell> -n` self-check → output
 *
 * IMPORTANT: This MUST be the LAST PreToolUse entry in hooks.json.
 * Reason: GitHub #15897 — multi-hook updatedInput aggregation bug means the
 * last hook's updatedInput wins unconditionally (even if undefined).
 *
 * Opt-in:  # PUEUE-WRAP comment forces wrapping for any command
 * Opt-out: # PUEUE-SKIP comment prevents wrapping even for long-running patterns
 * Op-token bypass: OP_SERVICE_ACCOUNT_TOKEN already in command → skip injection
 *
 * Reference: /plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897 (updatedInput aggregation bug)
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/11282 (ask + updatedInput broken)
 */

import { allow, allowWithInput, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { maybeInjectOpToken } from "./lib/op-token-injector.ts";
import { buildWrappedCommand, parses, payloadShell, spoolCommand } from "./lib/pueue-wrap-transport.ts";
import { rmSync } from "node:fs";

/** File where we record pueue task IDs for session-scoped cleanup.
 *  The stop hook reads this to kill only OUR jobs, not all jobs. */
const SESSION_TASK_LOG = `/tmp/claude-pueue-tasks-${process.env.CLAUDE_SESSION_ID || process.ppid}.txt`;

/** Opt-in escape hatch — force wrapping */
const WRAP_COMMENT = /# *PUEUE-WRAP/i;

/** Opt-out escape hatch — prevent wrapping */
const SKIP_COMMENT = /# *PUEUE-SKIP/i;

/** Commands that are already pueue-related (local or via SSH) */
const PUEUE_COMMANDS = /\bpueue\s+(add|status|log|wait|restart|send|kill|remove|clean|reset|follow|group)\b/i;

/** Scripts that ARE pueue wrappers (e.g., pueue-populate.sh, pueue-setup.sh) */
const PUEUE_SCRIPTS = /pueue[_-]/i;

/** Already backgrounded commands */
const BACKGROUNDED = /\bnohup\s|&\s*$|\bscreen\s|\btmux\s/i;

/** Fast local commands that should never be wrapped, even if their arguments
 *  (commit messages, branch names, file paths) happen to match LONG_RUNNING_PATTERNS.
 *  Includes linters/formatters whose file path arguments can trigger false positives
 *  (e.g., `ruff check scripts/populate_full_cache.py` matching "populate_cache"). */
const NEVER_WRAP = /^\s*(git|ruff|mypy|pyright|pylint|flake8|black|isort|prettier|eslint|biome|mise|cargo\s+(check|build|test|clippy|fmt|doc|nextest|bench|run|publish|install|update|add|remove))\s/i;

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
  // Shell loops with known long-running inner commands (populate, bulk, python)
  // Simple loops (curl, echo, git) are NOT wrapped — they complete quickly
  /for\s+\w+\s+in.*;\s*do[^;]*(populate|bulk|cache|python|uv\s+run)/i,
  /while.*;\s*do[^;]*(populate|bulk|cache|python|uv\s+run)/i,

  // SSH commands are EXCLUDED from auto-wrapping (opt-in only via # PUEUE-WRAP).
  // Reason: SSH commands already run remotely — local pueue wrapping adds no value
  // but creates quoting hell (zsh → pueue add → SSH → remote bash = 4 quote layers).
  // The PostToolUse pueue-reminder still suggests pueue for SSH long-running commands.
  // Evidence: opendeviationbar session 3774932e — 3 consecutive failures from
  // quote mangling when auto-wrapping `ssh <remote-host> 'for sym in ...; do curl ...; done'`.
];

/**
 * Check if a command matches known long-running patterns.
 * Returns true ONLY for commands that should be wrapped.
 */
export function shouldWrap(command: string): boolean {
  // Opt-in: explicit wrap request
  if (WRAP_COMMENT.test(command)) return true;

  // Opt-out: explicit skip request
  if (SKIP_COMMENT.test(command)) return false;

  // Never wrap pueue commands or pueue management scripts
  if (PUEUE_COMMANDS.test(command)) return false;
  if (PUEUE_SCRIPTS.test(command)) return false;

  // Never wrap already-backgrounded commands
  if (BACKGROUNDED.test(command)) return false;

  // Never wrap fast local commands (git commit messages can contain any text)
  if (NEVER_WRAP.test(command)) return false;

  // Check against known long-running patterns
  return LONG_RUNNING_PATTERNS.some((p) => p.test(command));
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

  const originalCommand = tool_input.command || "";

  // Step 1: Maybe inject OP_SERVICE_ACCOUNT_TOKEN for Claude Automation vault
  const command = await maybeInjectOpToken(originalCommand);
  const opTokenInjected = command !== originalCommand;

  // Step 2: Allowlist check — only wrap known long-running commands
  if (!shouldWrap(command)) {
    if (opTokenInjected) {
      // Token was injected but no pueue wrapping needed — still emit updatedInput
      allowWithInput("PUEUE-WRAP-GUARD", tool_name, { command });
    } else {
      allow();
    }
    return;
  }

  // Check pueue daemon is running and default group is not paused (fail-open if down)
  const daemonCheck = Bun.spawnSync(["pueue", "status", "--json"], {
    stdout: "pipe",
    stderr: "ignore",
  });
  if (daemonCheck.exitCode !== 0) {
    // Daemon not running — still apply token injection if present
    if (opTokenInjected) {
      allowWithInput("PUEUE-WRAP-GUARD", tool_name, { command });
    } else {
      allow();
    }
    return;
  }
  // Check if default group is paused — queued tasks never run in a paused group
  try {
    const status = JSON.parse(daemonCheck.stdout.toString());
    const defaultGroup = status?.groups?.default;
    if (defaultGroup === "Paused" || defaultGroup?.status === "Paused") {
      if (opTokenInjected) {
        allowWithInput("PUEUE-WRAP-GUARD", tool_name, { command });
      } else {
        allow();
      }
      return;
    }
  } catch {
    // JSON parse failed — fail-open
  }

  // Wrap tier. The command travels to pueue as a spool FILE, never as quoted
  // text (lib/pueue-wrap-transport.ts explains the defect this replaced).
  // Fail-open to the unwrapped command whenever the result cannot be proven to
  // parse: a payload that does not parse gets the shell's own error unwrapped,
  // and a wrapper that does not parse is a bug in this hook, recorded as such.
  const shell = payloadShell();
  const passThrough = () =>
    opTokenInjected ? allowWithInput("PUEUE-WRAP-GUARD", tool_name, { command }) : allow();
  const paths = spoolCommand(command);
  if (!parses(shell, [paths.script])) {
    rmSync(paths.script, { force: true });
    passThrough();
    return;
  }
  const wrappedCommand = buildWrappedCommand({
    shell,
    cwd: cwd || process.cwd(),
    paths,
    taskLog: SESSION_TASK_LOG,
  });
  if (!parses(shell, ["-c", wrappedCommand])) {
    rmSync(paths.script, { force: true });
    trackHookError("pretooluse-pueue-wrap-guard", "built a wrapper that does not parse; passed the command through unwrapped");
    passThrough();
    return;
  }

  allowWithInput("PUEUE-WRAP-GUARD", tool_name, { command: wrappedCommand });
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError("pretooluse-pueue-wrap-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
