#!/usr/bin/env bun
/**
 * Shared helpers for PreToolUse hooks.
 * Extracted from pretooluse-{fake-data,process-storm,version}-guard.mjs
 */

import { createHookLogger, type HookLogContext } from "./lib/logger.ts";

// Types
export interface PreToolUseInput {
  tool_name: string;
  tool_input: {
    command?: string;
    file_path?: string;
    content?: string;
    new_string?: string;
    [key: string]: unknown;
  };
  tool_use_id?: string;
  cwd?: string;
}

export interface PreToolUseResponse {
  hookSpecificOutput: {
    hookEventName: "PreToolUse";
    permissionDecision: "allow" | "deny" | "ask";
    permissionDecisionReason?: string;
  };
}

// Output helpers

/** Write a JSON response to stdout for Claude Code hook protocol */
export function output(response: object): void {
  console.log(JSON.stringify(response));
}

/** Allow the tool to execute without modification */
export function allow(): void {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  });
}

/** Deny the tool execution with an explanation shown to user */
export function deny(reason: string): void {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  });
}

/** Show a confirmation dialog to the user before proceeding */
export function ask(reason: string): void {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: reason,
    },
  });
}

/**
 * Parse stdin JSON and return PreToolUseInput, or null if parsing fails.
 * On parse failure, automatically calls allow() and returns null (fail-open).
 */
export async function parseStdinOrAllow(
  hookName: string
): Promise<PreToolUseInput | null> {
  const logger = createHookLogger(hookName);
  try {
    const stdin = await Bun.stdin.text();
    const input = JSON.parse(stdin) as PreToolUseInput;
    logger.debug("Parsed stdin", {
      hook_event: "PreToolUse",
      tool_name: input.tool_name,
      trace_id: input.tool_use_id,
    });
    return input;
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    logger.error("Failed to parse stdin", { hook_event: "PreToolUse", error: message });
    console.error(`[${hookName}] Failed to parse stdin: ${message}`);
    allow();
    return null;
  }
}

// Re-export logger for hooks that need additional logging
export { createHookLogger, type HookLogContext };
