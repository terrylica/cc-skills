#!/usr/bin/env bun
/**
 * Shared helpers for PreToolUse hooks.
 * Extracted from pretooluse-{fake-data,process-storm,version}-guard.mjs
 *
 * Includes plan mode detection for hooks that should behave differently
 * during Claude Code's planning phase.
 *
 * ADR: /docs/adr/2026-02-05-plan-mode-detection-hooks.md
 */

import { createHookLogger, type HookLogContext } from "./lib/logger.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import { validateToolInput, TOOL_SCHEMAS } from "./lib/tool-schemas.ts";
import {
  isPlanMode,
  isQuickPlanMode,
  type HookInputWithPlanMode,
  type PlanModeContext,
  type PermissionMode,
} from "./lib/plan-mode-detector.ts";

// Types

/**
 * Permission modes supported by Claude Code.
 * Re-exported from plan-mode-detector for convenience.
 */
export type { PermissionMode };

/**
 * PreToolUse hook input from Claude Code.
 * Includes all documented fields including plan mode indicators.
 */
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
  /** Session identifier for state tracking */
  session_id?: string;
  /** Path to conversation transcript JSONL */
  transcript_path?: string;
  /** Permission mode - "plan" indicates Claude is in planning phase */
  permission_mode?: PermissionMode;
  /** Name of the hook event (always "PreToolUse" for this input) */
  hook_event_name?: string;
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
 * Allow tool execution with schema-validated input mutation.
 *
 * Validates updatedInput against the tool's Zod schema (.strict()).
 * Unknown properties are rejected. Unknown tools get plain allow().
 * Fail-open: on any validation failure, falls back to allow() (no mutation).
 *
 * NEVER for an interactive tool. For AskUserQuestion, `updatedInput` is the channel through which
 * the native dialog (or a hook standing in for it) delivers the user's `answers`. A hook that sends
 * `allow` + `updatedInput` is therefore treated as having ALREADY answered: the dialog never renders
 * and the tool returns "The user did not answer the questions." Measured 2026-09-24 over every
 * session transcript: 86 of 86 rewritten calls went unanswered and unseen, against 465 of 466 plain
 * `allow` calls that rendered and were answered, on every version 2.1.269–2.1.281. A plain `allow`
 * is safe because Claude Code keeps the permission UI for `requiresUserInteraction` tools
 * (anthropics/claude-code#29547). So this refuses, counts the error, and falls back to plain allow.
 * To change what the user sees, `deny` with a reason that tells the agent what to re-ask.
 */
export const TOOLS_WHOSE_UPDATED_INPUT_IS_THE_USERS_ANSWER: ReadonlySet<string> = new Set([
  "AskUserQuestion",
]);

export function allowWithInput(
  hookName: string,
  toolName: string,
  updatedInput: Record<string, unknown>,
): void {
  if (TOOLS_WHOSE_UPDATED_INPUT_IS_THE_USERS_ANSWER.has(toolName)) {
    trackHookError(
      hookName,
      `refused updatedInput for ${toolName}: it would suppress the dialog and return no answers; deny with a re-ask reason instead`,
    );
    allow();
    return;
  }
  const result = validateToolInput(toolName, updatedInput);
  if (!result.valid) {
    trackHookError(hookName, result.error);
    allow();
    return;
  }
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: result.data,
    },
  });
}

/**
 * Check if a tool has a known schema (and thus can receive updatedInput).
 */
export function hasToolSchema(toolName: string): boolean {
  return toolName in TOOL_SCHEMAS;
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
    trackHookError(hookName, `Failed to parse stdin: ${message}`);
    allow();
    return null;
  }
}

// Re-export logger for hooks that need additional logging
export { createHookLogger, type HookLogContext };

// Re-export hook error tracker for fail-open error handling
export { trackHookError } from "./lib/hook-error-tracker.ts";

// Re-export plan mode detection utilities
export { isPlanMode, isQuickPlanMode, type HookInputWithPlanMode, type PlanModeContext };

// Re-export read-only command detection utilities
export {
  isReadOnlyCommand,
  isReadOnly,
  isRemoteCommand,
  type ReadOnlyCheckResult,
} from "./lib/readonly-command-detector.ts";

// Re-export tool schema validation utilities
export { TOOL_SCHEMAS, validateToolInput } from "./lib/tool-schemas.ts";
