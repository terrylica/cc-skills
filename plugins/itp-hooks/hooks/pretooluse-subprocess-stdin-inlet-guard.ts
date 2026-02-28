#!/usr/bin/env bun
/**
 * PreToolUse hook: Universal Subprocess Stdin Inlet Guard
 *
 * Problem: Bash commands can spawn subprocesses that inherit
 * Claude Code's stdin, causing TTY suspension.
 *
 * Solution: Pre-disconnect stdin for Bash commands via `< /dev/null` redirection.
 * All other tools are allowed without mutation.
 *
 * Schema safety: Uses allowWithInput() which validates updatedInput against
 * the tool's Zod schema (.strict()). Unknown properties (like `env`) are
 * automatically rejected, preventing schema corruption (GitHub #13439).
 *
 * Previous approach used PASSTHROUGH_TOOLS denylist (16 entries) + env injection.
 * The env injection was a no-op (CC ignores unknown fields in tool input).
 * The denylist was fragile (new tools needed manual addition).
 * Now Zod .strict() handles both concerns automatically.
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

  // Only Bash benefits from command mutation (stdin disconnection)
  if (tool_name === "Bash" && typeof tool_input.command === "string") {
    let command = tool_input.command;
    if (!command.includes("</dev/null") && !command.includes("< /dev/null")) {
      command = `(${command}) < /dev/null`;
    }

    console.warn(
      "🛡️  Subprocess Inlet Guard: Pre-disconnecting stdin for Bash",
    );

    // allowWithInput validates {command} against BashSchema.strict()
    // If Zod rejects it → falls back to allow() (fail-open, no mutation)
    allowWithInput("STDIN-INLET-GUARD", tool_name, { command });
    return;
  }

  // All other tools: allow without mutation (Zod prevents accidental schema corruption)
  allow();
}

main().catch((e) => trackHookError("STDIN-INLET-GUARD", e instanceof Error ? e.message : String(e)));
