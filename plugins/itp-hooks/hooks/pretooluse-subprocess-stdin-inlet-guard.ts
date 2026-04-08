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

import { allow, allowWithInput, parseStdinOrAllow, trackHookError, isRemoteCommand } from "./pretooluse-helpers.ts";

async function main() {
  const input = await parseStdinOrAllow("STDIN-INLET-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Bash: inject `< /dev/null` to disconnect stdin
  if (tool_name === "Bash" && typeof tool_input.command === "string") {
    let command = tool_input.command;

    // SSH commands handle stdin through the SSH channel — wrapping with
    // < /dev/null triggers a Claude Code confirmation prompt (updatedInput
    // mutation) that blocks remote work unnecessarily.
    if (isRemoteCommand(command)) {
      allow();
      return;
    }

    if (!command.includes("</dev/null") && !command.includes("< /dev/null")) {
      command = `(${command}) < /dev/null`;
    }

    console.warn(
      "🛡️  Subprocess Inlet Guard: Pre-disconnecting stdin for Bash",
    );

    allowWithInput("STDIN-INLET-GUARD", tool_name, { command });
    return;
  }

  // MCP shell_execute: cannot wrap with bash (MCP shell has a command allowlist
  // that doesn't include bash). Wrapping ["uv","run",...] → ["bash","-c",...]
  // changes the executable and breaks all MCP shell calls.
  // TTY contention from parallel MCP calls must be addressed at the MCP server
  // configuration level, not via command mutation.
  if (tool_name === "mcp__shell__shell_execute") {
    allow();
    return;
  }

  // All other tools: allow without mutation
  allow();
}

main().catch((e) => trackHookError("STDIN-INLET-GUARD", e instanceof Error ? e.message : String(e)));
