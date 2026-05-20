#!/usr/bin/env bun
/**
 * PreToolUse hook: Bash Subprocess Stdin Inlet Guard
 *
 * Problem: Bash commands spawn subprocesses that inherit Claude Code's stdin,
 * causing TTY suspension (SIGSTOP) when backgrounded or when the subprocess
 * tries to read from /dev/tty.
 *
 * Solution: Pre-disconnect stdin via `< /dev/null` redirection wrapped around
 * the original command.
 *
 * Schema safety: Uses allowWithInput() which validates updatedInput against
 * the Bash tool's Zod schema (.strict()). Unknown properties (e.g., `env`)
 * are automatically rejected, preventing schema corruption (GitHub #13439).
 *
 * iter-63 perf optimization: hooks.json matcher narrowed from "*" to "Bash"
 * because the previous "all other tools" + "mcp__shell__shell_execute"
 * branches were no-op stubs (just called allow()) — Claude Code cold-started
 * bun on every Read/Glob/Grep/Edit/Write/mcp__* call (~12-17ms per call)
 * only to execute a no-op. The matcher narrowing eliminates that waste.
 * Historical context preserved here for the future if a non-Bash subprocess-
 * spawning tool emerges:
 *
 *   - mcp__shell__shell_execute had a no-op branch (NOT a working wrap)
 *     because the MCP shell command-allowlist excludes bash — wrapping
 *     ["uv","run",...] → ["bash","-c",...] changes the executable and
 *     breaks all MCP shell calls. TTY contention from parallel MCP calls
 *     must be addressed at the MCP server configuration level.
 *
 *   - If a future tool category emerges (e.g., a hypothetical Python
 *     subprocess tool), widen the hooks.json matcher to include it AND
 *     add a corresponding handler branch here.
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

  // Defensive non-Bash early-exit: in normal operation Claude Code only
  // invokes this hook for Bash because the matcher is "Bash" (iter-63).
  // This guard catches the edge case where an operator widens the matcher
  // (e.g., to debug a non-Bash subprocess issue) without also widening the
  // handler branches. Without this guard a non-Bash tool would still hit
  // allowWithInput() with a `command` field the schema rejects, causing
  // a fail-open allow() with a tracked error.
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  if (typeof tool_input.command !== "string") {
    allow();
    return;
  }

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
}

main().catch((e) => trackHookError("STDIN-INLET-GUARD", e instanceof Error ? e.message : String(e)));
