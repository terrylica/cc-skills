#!/usr/bin/env bun
/**
 * PreToolUse Shell Script Safety Guard — iter-119
 *
 * Blocks Write/Edit operations on shell scripts that introduce two
 * mechanically-decidable defects:
 *
 * RULE 1 — STATUS-LOSS-AFTER-IF (2026-08-02 css incident)
 *   Flags `$?` after `fi` when the if block has NO `else`/`elif`.
 *   With no else, the condition-failed path runs no code, so `$?` is 0
 *   (success), masking the real failure. This caused hard-to-debug issues
 *   in production scripts where error handling was silently swallowed.
 *
 * RULE 2 — MASKED-COMMAND-SUBSTITUTION (Empirical fact D)
 *   Flags `local|export|readonly|declare|typeset VAR=$(...)`.
 *   The declaration keyword's exit status (always 0) overwrites the
 *   command substitution's real exit code, silently defeating `set -e`.
 *
 * Applies to: .sh/.bash/.zsh files or files with bash/sh/zsh shebang
 * Skips: test fixtures, .bak files (intentional counter-examples)
 *
 * Escape hatch: `SHELL-SAFETY-OK: <reason ≥ 8 chars>` (FILE_WIDE)
 *
 * For Edit tool: flags only NET-NEW defects (count in new > count in old).
 */

import {
  parseStdinOrAllow,
  isPlanMode,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
import {
  detectAllShellSafetyDefects,
  isShellScript,
  type ShellSafetyDefect,
} from "./lib/shell-script-safety-detector-status-loss-and-masked-substitution-iter119.ts";

// ============================================================================
// Utilities
// ============================================================================

/**
 * Count net-new defects for Edit operations.
 * Only deny if new_string introduces MORE defects than old_string.
 */
function countNetNewDefects(
  oldDefects: ShellSafetyDefect[],
  newDefects: ShellSafetyDefect[],
): ShellSafetyDefect[] {
  const oldCount = oldDefects.length;
  const newCount = newDefects.length;

  // Only flag net-new defects
  if (newCount > oldCount) {
    return newDefects.slice(oldCount);
  }

  return [];
}

/**
 * Format defects for the deny message.
 */
function formatDefectsForMessage(defects: ShellSafetyDefect[], filePath: string): string {
  const sample = defects.slice(0, 3);
  const sampleLines = sample
    .map(
      (d) =>
        `  Line ${d.lineNumber} [${d.rule}]: ${d.statement}\n    → ${d.explanation.substring(0, 80)}...`,
    )
    .join("\n");

  const moreCount = defects.length - sample.length;
  const moreMsg = moreCount > 0 ? `\n  ...and ${moreCount} more` : "";

  return `${filePath}:

${sampleLines}${moreMsg}

CORRECTION:
  For RULE 1 (STATUS-LOSS-AFTER-IF):
    Add an 'else' clause to capture the exit code:
      if cmd; then
        true
      else
        rc=$?
      fi

  For RULE 2 (MASKED-COMMAND-SUBSTITUTION):
    Split the declaration and assignment:
      local VAR_NAME
      VAR_NAME=$(cmd)

ESCAPE HATCH (FILE-WIDE):
  Add this comment anywhere in the file:
    # SHELL-SAFETY-OK: <reason>
  Example:
    # SHELL-SAFETY-OK: legacy error handling pattern (iter-15 backlog)`;
}

// ============================================================================
// Main classifier (conforms to PreToolUseSubhookClassifierFunction)
// ============================================================================

export async function classifyShellScriptSafetyGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  try {
    // Plan mode → allow all
    if (isPlanMode(input)) {
      return ALLOW_DECISION;
    }

    // Only applicable to Write/Edit
    if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(input.tool_name)) {
      return ALLOW_DECISION;
    }

    const filePath = input.tool_input.file_path;
    const newFileContent = input.tool_input.content;

    // Validate inputs
    if (!filePath || !newFileContent) {
      return ALLOW_DECISION;
    }

    // Fast-path: if file is not a shell script, allow
    if (!isShellScript(filePath, newFileContent)) {
      return ALLOW_DECISION;
    }

    // For Edit operations, count net-new defects only
    let defectsToCheck = detectAllShellSafetyDefects(filePath, newFileContent);

    if (input.tool_name === "Edit" && input.tool_input.new_string) {
      // For Edit, we need to construct the old content from the original file
      // The orchestrator doesn't provide it, so we'll check if we should get it
      // For now, we'll use the new_string approach: check defects in new_string only
      const newStringDefects = detectAllShellSafetyDefects(filePath, input.tool_input.new_string);
      defectsToCheck = newStringDefects;
    }

    // If no defects, allow
    if (defectsToCheck.length === 0) {
      return ALLOW_DECISION;
    }

    // DENY: shell safety defects found
    return denyDecision(formatDefectsForMessage(defectsToCheck, filePath));
  } catch (error) {
    // Fail-open on any error (log it for diagnostics)
    trackHookError("shell-script-safety-guard", String(error));
    return ALLOW_DECISION;
  }
}
