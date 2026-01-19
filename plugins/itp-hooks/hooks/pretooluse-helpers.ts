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
export function output(response: object): void {
  console.log(JSON.stringify(response));
}

export function allow(): void {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  });
}

export function deny(reason: string): void {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  });
}

export function ask(reason: string): void {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: reason,
    },
  });
}

// Stdin parsing with allow-on-error semantics + logging
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
