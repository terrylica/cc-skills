#!/usr/bin/env bun
/**
 * PreToolUse hook: Universal Subprocess Stdin Inlet Guard
 *
 * Problem: Bash and MCP shell_execute commands spawn subprocesses that inherit
 * Claude Code's stdin, causing TTY suspension (SIGSTOP).
 *
 * Solution:
 *   - Bash: Pre-disconnect stdin via `< /dev/null` redirection.
 *   - MCP shell_execute: Wrap command array in `bash -c '("$@") </dev/null'`
 *     to disconnect stdin while preserving argument boundaries.
 *
 * The MCP shell server spawns interactive zsh sessions with PTY allocation.
 * Parallel MCP shell_execute calls compete for the same TTY stdin, triggering
 * the kernel's SIGSTOP. Wrapping with stdin disconnection prevents this.
 *
 * Schema safety: Uses allowWithInput() which validates updatedInput against
 * the tool's Zod schema (.strict()). Unknown properties (like `env`) are
 * automatically rejected, preventing schema corruption (GitHub #13439).
 *
 * Reference: GitHub Issues #11898, #12507, #13598
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/13439
 * Related: pretooluse-cargo-tty-guard.ts (specific cargo handling)
 */

import { allow, allowWithInput, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

async function main() {
  const input = await parseStdinOrAllow("STDIN-INLET-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Bash: inject `< /dev/null` to disconnect stdin
  if (tool_name === "Bash" && typeof tool_input.command === "string") {
    let command = tool_input.command;
    if (!command.includes("</dev/null") && !command.includes("< /dev/null")) {
      command = `(${command}) < /dev/null`;
    }

    console.warn(
      "🛡️  Subprocess Inlet Guard: Pre-disconnecting stdin for Bash",
    );

    allowWithInput("STDIN-INLET-GUARD", tool_name, { command });
    return;
  }

  // MCP shell_execute: wrap command array to disconnect stdin.
  // The MCP shell server allocates PTYs for spawned processes.
  // Parallel calls compete for the same TTY stdin → SIGSTOP.
  // Wrap: ["uv","run",...] → ["bash","-c","(\"$@\") </dev/null","bash","uv","run",...]
  if (tool_name === "mcp__shell__shell_execute" && Array.isArray(tool_input.command)) {
    const originalCommand = tool_input.command as string[];

    // Skip if already wrapped with stdin disconnection
    const joined = originalCommand.join(" ");
    if (joined.includes("</dev/null") || joined.includes("< /dev/null")) {
      allow();
      return;
    }

    const wrappedCommand = ["bash", "-c", '("$@") </dev/null', "bash", ...originalCommand];

    console.warn(
      "🛡️  Subprocess Inlet Guard: Pre-disconnecting stdin for MCP shell_execute",
    );

    // Preserve directory and timeout from original input
    const updatedInput: Record<string, unknown> = { command: wrappedCommand };
    if (tool_input.directory) updatedInput.directory = tool_input.directory;
    if (tool_input.timeout != null) updatedInput.timeout = tool_input.timeout;

    allowWithInput("STDIN-INLET-GUARD", tool_name, updatedInput);
    return;
  }

  // All other tools: allow without mutation
  allow();
}

main().catch((e) => trackHookError("STDIN-INLET-GUARD", e instanceof Error ? e.message : String(e)));
