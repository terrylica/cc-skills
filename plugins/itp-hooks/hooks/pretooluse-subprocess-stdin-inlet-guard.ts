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
 * Tools that never spawn subprocesses. Returning updatedInput for these
 * corrupts their schema (e.g., AskUserQuestion expects only {questions}).
 * See: GitHub Issues #13439, #10400
 */
const PASSTHROUGH_TOOLS = new Set([
  "AskUserQuestion",
  "EnterPlanMode",
  "ExitPlanMode",
  "TaskCreate",
  "TaskUpdate",
  "TaskList",
  "TaskGet",
  "TodoWrite",
  "TodoRead",
  "Read",
  "Glob",
  "Grep",
  "WebSearch",
  "WebFetch",
  "Agent",
  "Skill",
]);

async function main() {
  const input = await parseStdinOrAllow("STDIN-INLET-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Tools that never spawn subprocesses — allow without any input mutation
  if (PASSTHROUGH_TOOLS.has(tool_name)) {
    allow();
    return;
  }

  // Bash: stdin disconnection + env injection (the primary use case)
  if (tool_name === "Bash" && typeof tool_input.command === "string") {
    const enhanced_env = { ...SUBPROCESS_DISABLING_ENV };

    let command = tool_input.command;
    if (
      !command.includes("</dev/null") &&
      !command.includes("< /dev/null")
    ) {
      command = buildStdinDisconnectedCommand(tool_name, command);
    }

    console.warn(
      "🛡️  Subprocess Inlet Guard: Pre-disconnecting stdin for Bash",
    );

    output({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {
          ...tool_input,
          command,
          env: enhanced_env,
        },
      },
    });
    return;
  }

  // Write/Edit/NotebookEdit/LSP: env injection only (no command mutation)
  if (["Write", "Edit", "NotebookEdit", "LSP"].includes(tool_name)) {
    const enhanced_env = { ...SUBPROCESS_DISABLING_ENV };

    output({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {
          ...tool_input,
          env: enhanced_env,
        },
      },
    });
    return;
  }

  // Unknown tools: allow without mutation (safe default — avoids schema corruption)
  allow();
}

main().catch((e) => trackHookError("STDIN-INLET-GUARD", e instanceof Error ? e.message : String(e)));
