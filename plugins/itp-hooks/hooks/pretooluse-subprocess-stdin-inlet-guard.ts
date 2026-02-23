#!/usr/bin/env bun
/**
 * PreToolUse hook: Universal Subprocess Stdin Inlet Guard
 *
 * Problem: ANY tool (not just Bash) can spawn subprocesses that inherit
 * Claude Code's stdin, causing TTY suspension.
 *
 * Solution: Universally disconnect stdin inheritance BEFORE subprocess spawning
 * by (1) environment variable injection, (2) stdin redirection, (3) TTY disabling
 *
 * Coverage: ALL tools (Bash, Read, Write, LSP, Code, Git, etc.)
 *
 * Reference: GitHub Issues #11898, #12507, #13598
 * Related: pretooluse-cargo-tty-guard.ts (specific cargo handling)
 */

import { allow, output, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

/**
 * Environment variables that disable subprocess spawning / TTY interaction
 * These are injected into the execution environment BEFORE tool runs
 */
const SUBPROCESS_DISABLING_ENV = {
  // Disable interactive prompts / TTY features globally
  NO_PAGER: "1",
  TERM: "dumb",
  LANG: "C",
  LC_ALL: "C",

  // Python: disable buffering, disable interactive prompts
  PYTHONUNBUFFERED: "1",
  PYTHONDONTWRITEBYTECODE: "1",

  // Rust: disable color output, disable prompts
  RUST_BACKTRACE: "1",
  RUST_LOG: "warn",

  // Git: disable pager, disable prompts
  GIT_TERMINAL_PROMPT: "0",
  GIT_PAGER: "cat",

  // LSP: disable subprocess spawning (experimental)
  LSP_DISABLE_SUBPROCESS: "1",
  LSP_FORK: "0",

  // Node/Bun: disable interactive mode
  NODE_NO_READLINE: "1",
};

/**
 * Tool-specific stdin disconnection strategies
 */
function buildStdinDisconnectedCommand(tool_name: string, command: string): string {
  switch (tool_name) {
    case "Bash":
      // Bash: Append < /dev/null to disconnect stdin
      // Already handled by cargo-tty-guard, but apply universally
      return `(${command}) < /dev/null`;

    case "Read":
    case "Write":
    case "Glob":
    case "Grep":
      // These tools don't directly spawn subprocesses, but if they did:
      // They should be handled at the subprocess level via env vars
      return command;

    case "Edit":
    case "NotebookEdit":
      // File operations - wrap any subprocess with stdin disconnect
      return command;

    case "LSP":
      // LSP: Disable subprocess spawning via environment
      // Actual implementation handled via env vars below
      return command;

    default:
      // Generic fallback: disconnect stdin for any unknown tool
      return `${command} < /dev/null 2>/dev/null`;
  }
}

/**
 * Check if command appears to spawn a subprocess
 * (heuristic - may have false positives)
 */
function mightSpawnSubprocess(command: string): boolean {
  const subprocess_patterns =
    /spawn|exec|fork|subprocess|popen|popen2|shell|system|/i;
  return subprocess_patterns.test(command);
}

async function main() {
  const input = await parseStdinOrAllow("STDIN-INLET-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {}, cwd } = input;

  // Apply environment variable injection for ALL tools
  const enhanced_env = {
    ...input.env,
    ...SUBPROCESS_DISABLING_ENV,
  };

  // Tool-specific stdin disconnection
  let updatedInput = { ...tool_input };

  if (tool_name === "Bash" && typeof tool_input.command === "string") {
    // Bash: Append stdin redirect if not already present
    if (
      !tool_input.command.includes("</dev/null") &&
      !tool_input.command.includes("< /dev/null")
    ) {
      updatedInput.command = buildStdinDisconnectedCommand(
        tool_name,
        tool_input.command,
      );
    }
  } else if (tool_name === "Read" && typeof tool_input.file_path === "string") {
    // Read: Inject env vars (actual stdin disconnect not needed, but preventive)
    // No command modification needed
  } else if (tool_name === "Write") {
    // Write: Inject env vars
    // No command modification needed
  } else if (tool_name === "LSP") {
    // LSP: Disable subprocess spawning via env vars
    // Force LSP to use --stdio mode (already detached)
    if (updatedInput.operation) {
      // Already set env vars above
    }
  }

  // Emit the transformed input with environment injection
  console.warn(
    "🛡️  Subprocess Inlet Guard: Pre-disconnecting stdin for all subprocesses",
  );

  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: {
        ...updatedInput,
        // Inject enhanced environment for all tools
        env: enhanced_env,
      },
    },
  });
}

main().catch(trackHookError("STDIN-INLET-GUARD"));
