#!/usr/bin/env bun
/**
 * plan-mode-detector.ts - Detect Claude Code plan mode in hooks
 *
 * Plan mode detection uses multiple signals:
 * 1. `permission_mode: "plan"` in hook input (primary, most reliable)
 * 2. File path patterns matching `/plans/*.md` (secondary)
 * 3. Active plan files in `~/.claude/plans/` (tertiary, least reliable)
 *
 * Usage:
 *   import { isPlanMode, PlanModeContext } from "./lib/plan-mode-detector.ts";
 *   const ctx = isPlanMode(input);
 *   if (ctx.inPlanMode) { allow(); return; }
 *
 * ADR: /docs/adr/2026-02-05-plan-mode-detection-hooks.md
 */

import { existsSync, readdirSync } from "node:fs";
import { createHookLogger } from "./logger.ts";

const logger = createHookLogger("plan-mode-detector");

// ============================================================================
// Types
// ============================================================================

/**
 * Permission modes supported by Claude Code.
 * - "default": Normal interactive mode
 * - "plan": Plan mode (EnterPlanMode active)
 * - "acceptEdits": Auto-accept file edits
 * - "dontAsk": Skip confirmation dialogs
 * - "bypassPermissions": Skip all permission checks
 */
export type PermissionMode =
  | "default"
  | "plan"
  | "acceptEdits"
  | "dontAsk"
  | "bypassPermissions";

/**
 * Extended hook input with all fields from Claude Code.
 * Extends the base PreToolUseInput with plan-mode-relevant fields.
 */
export interface HookInputWithPlanMode {
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
  session_id?: string;
  transcript_path?: string;
  permission_mode?: PermissionMode;
  hook_event_name?: string;
}

/**
 * Result of plan mode detection with detailed context.
 */
export interface PlanModeContext {
  /** True if any plan mode signal detected */
  inPlanMode: boolean;

  /** Which signals triggered detection */
  signals: {
    /** permission_mode === "plan" */
    permissionModeIsPlan: boolean;
    /** File path matches /plans/*.md pattern */
    filePathIsPlanFile: boolean;
    /** Active plan files exist in ~/.claude/plans/ */
    activePlanFilesExist: boolean;
  };

  /** Raw permission_mode value from input */
  permissionMode: PermissionMode | undefined;

  /** File path being operated on (if any) */
  filePath: string | undefined;

  /** Human-readable reason for detection */
  reason: string;
}

// ============================================================================
// Configuration
// ============================================================================

const CONFIG = {
  /** Directory where Claude stores active plan files */
  planDirectory: `${process.env.HOME}/.claude/plans`,

  /** Patterns that indicate a plan file path */
  planFilePatterns: [
    /\/plans\/.*\.md$/i, // Any /plans/*.md path
    /\/\.claude\/plans\//i, // ~/.claude/plans/ specifically
    /\/tmp\/plans\//i, // Temporary plan archives
  ],

  /** File extensions to consider as plan files */
  planExtensions: [".md"],
};

// ============================================================================
// Detection Functions
// ============================================================================

/**
 * Check if permission_mode indicates plan mode.
 * This is the primary and most reliable signal.
 */
function checkPermissionMode(
  permissionMode: PermissionMode | undefined
): boolean {
  return permissionMode === "plan";
}

/**
 * Check if file path matches plan file patterns.
 * Secondary signal - catches writes to plan directories.
 */
function checkFilePath(filePath: string | undefined): boolean {
  if (!filePath) return false;
  return CONFIG.planFilePatterns.some((pattern) => pattern.test(filePath));
}

/**
 * Check if active plan files exist in ~/.claude/plans/.
 * Tertiary signal - least reliable as plans may be stale.
 */
function checkActivePlanFiles(): boolean {
  try {
    if (!existsSync(CONFIG.planDirectory)) {
      return false;
    }
    const files = readdirSync(CONFIG.planDirectory);
    // Filter for .md files that look like plan files (adjective-noun pattern)
    const planFiles = files.filter(
      (f) => f.endsWith(".md") && !f.startsWith(".")
    );
    return planFiles.length > 0;
  } catch {
    // Directory doesn't exist or can't be read
    return false;
  }
}

/**
 * Build human-readable reason string for plan mode detection.
 */
function buildReason(signals: PlanModeContext["signals"]): string {
  const reasons: string[] = [];

  if (signals.permissionModeIsPlan) {
    reasons.push("permission_mode is 'plan'");
  }
  if (signals.filePathIsPlanFile) {
    reasons.push("file path matches plan directory pattern");
  }
  if (signals.activePlanFilesExist) {
    reasons.push("active plan files exist in ~/.claude/plans/");
  }

  if (reasons.length === 0) {
    return "no plan mode signals detected";
  }

  return reasons.join("; ");
}

// ============================================================================
// Main API
// ============================================================================

/**
 * Detect if Claude Code is currently in plan mode.
 *
 * @param input - Hook input JSON (PreToolUse or PostToolUse)
 * @param options - Detection options
 * @returns PlanModeContext with detection results
 *
 * @example
 * const input = await parseStdinOrAllow("MY-HOOK");
 * const ctx = isPlanMode(input);
 * if (ctx.inPlanMode) {
 *   logger.debug("Skipping check in plan mode", { reason: ctx.reason });
 *   return allow();
 * }
 */
export function isPlanMode(
  input: HookInputWithPlanMode | null,
  options: {
    /** Check permission_mode field (default: true) */
    checkPermission?: boolean;
    /** Check file path patterns (default: true) */
    checkPath?: boolean;
    /** Check for active plan files (default: false - expensive) */
    checkActiveFiles?: boolean;
    /** Log detection results (default: false) */
    log?: boolean;
  } = {}
): PlanModeContext {
  const {
    checkPermission = true,
    checkPath = true,
    checkActiveFiles = false,
    log: shouldLog = false,
  } = options;

  // Handle null input (parse failure)
  if (!input) {
    return {
      inPlanMode: false,
      signals: {
        permissionModeIsPlan: false,
        filePathIsPlanFile: false,
        activePlanFilesExist: false,
      },
      permissionMode: undefined,
      filePath: undefined,
      reason: "no input provided",
    };
  }

  const permissionMode = input.permission_mode;
  const filePath = input.tool_input?.file_path;

  // Build signals
  const signals: PlanModeContext["signals"] = {
    permissionModeIsPlan: checkPermission
      ? checkPermissionMode(permissionMode)
      : false,
    filePathIsPlanFile: checkPath ? checkFilePath(filePath) : false,
    activePlanFilesExist: checkActiveFiles ? checkActivePlanFiles() : false,
  };

  // Determine if in plan mode (any signal is sufficient)
  const inPlanMode =
    signals.permissionModeIsPlan ||
    signals.filePathIsPlanFile ||
    signals.activePlanFilesExist;

  const reason = buildReason(signals);

  const result: PlanModeContext = {
    inPlanMode,
    signals,
    permissionMode,
    filePath,
    reason,
  };

  // Optional debug logging
  if (shouldLog) {
    logger.debug("Plan mode detection", {
      tool_name: input.tool_name,
      trace_id: input.tool_use_id,
      in_plan_mode: inPlanMode,
      reason,
      permission_mode: permissionMode,
    });
  }

  return result;
}

/**
 * Quick check for plan mode (primary signal only).
 * Use when you only need a boolean and don't need detailed context.
 *
 * @example
 * if (isQuickPlanMode(input)) {
 *   return allow();
 * }
 */
export function isQuickPlanMode(input: HookInputWithPlanMode | null): boolean {
  if (!input) return false;
  return (
    input.permission_mode === "plan" ||
    checkFilePath(input.tool_input?.file_path)
  );
}

/**
 * Get list of active plan files in ~/.claude/plans/.
 * Useful for debugging or detailed logging.
 */
export function getActivePlanFiles(): string[] {
  try {
    if (!existsSync(CONFIG.planDirectory)) {
      return [];
    }
    return readdirSync(CONFIG.planDirectory).filter(
      (f) => f.endsWith(".md") && !f.startsWith(".")
    );
  } catch {
    return [];
  }
}

// Export config for testing
export const PLAN_MODE_CONFIG = CONFIG;
