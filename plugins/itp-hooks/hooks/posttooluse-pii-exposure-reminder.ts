#!/usr/bin/env bun
/**
 * PostToolUse hook: third-party-PII exposure reminder.
 *
 * Fires after a Write/Edit/MultiEdit of a durable text file whose POST-EDIT
 * content contains a third-party email address or telephone number, and injects
 * a Claude-visible reminder that the data may not belong in a published tree.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  The incident
 * ════════════════════════════════════════════════════════════════════════
 *
 * In the 23-repo audit, a third-party contact's real name, business email and
 * phone number were found in the published tree — reintroduced SIX DAYS after
 * an eleven-agent scrub of 2,602 files removed them. That is the whole argument
 * for an edit-time hook: a one-time sweep does not hold, because the next agent
 * re-derives the same content from the same upstream source and pastes it back.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this NEVER blocks
 * ════════════════════════════════════════════════════════════════════════
 *
 * An email address in a doc is frequently legitimate — a vendor's support
 * address, an RFC author, a git commit trailer, a maintainer contact in a
 * plugin manifest. A guard that denied on that would be wrong several times a
 * day, and a guard that is wrong several times a day gets disabled — which is
 * strictly worse than no guard at all. So this returns `decision: "block"` in
 * the PostToolUse sense only: a system reminder that does NOT undo the edit,
 * carries no deny, and costs nothing but a few tokens.
 *
 * The high-confidence credential half of the same incident IS blocked, by
 * `pretooluse-secret-exposure-guard.ts`.
 *
 * Escape hatch: a `PII-SCAN-OK` comment anywhere in the file — no reason
 * required, because unlike a credential, intentionally published contact
 * information is an ordinary and defensible thing to have.
 */

import { existsSync } from "node:fs";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  buildPiiReminder,
  detectThirdPartyPiiExposure,
} from "./lib/secret-and-pii-exposure-detector.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

const HOOK_NAME = "posttooluse-pii-exposure-reminder";
const PII_SCAN_OK_MARKER = "PII-SCAN-OK";

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
}

const FILE_EDIT_TOOL_NAMES: ReadonlySet<string> = new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Documentation and configuration surfaces only.
 *
 * The audit's finding #4 is the calibration: `docs/` is the dangerous
 * directory, not `src/`. Restricting to prose-and-config extensions removes
 * the whole class of false positives from test fixtures, vendored corpora and
 * source files that legitimately embed contact strings in code.
 */
const PII_SCANNED_EXTENSION_PATTERN =
  /\.(?:md|markdown|txt|rst|adoc|json|jsonc|ya?ml|toml|ini|cfg|conf|env|csv|html)$/i;

/** Pure activation gate (exported for tests). */
export function isPiiReminderEligibleTarget(toolName: string, filePath: string): boolean {
  if (!FILE_EDIT_TOOL_NAMES.has(toolName)) return false;
  if (!filePath || !PII_SCANNED_EXTENSION_PATTERN.test(filePath)) return false;
  return !isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
    filePath,
  );
}

/**
 * Pure evaluation (exported for tests): the Claude-visible reminder string, or
 * `null` when the file is clean or carries the `PII-SCAN-OK` marker.
 */
export function evaluatePiiExposureContent(filePath: string, content: string): string | null {
  if (
    hasFileWideEscapeHatchMarkerInContent(content, {
      markerNameTokenIncludingSuffix: PII_SCAN_OK_MARKER,
      requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 0,
    })
  ) {
    return null;
  }
  const findings = detectThirdPartyPiiExposure(content);
  if (findings.length === 0) return null;
  return buildPiiReminder(filePath, findings);
}

async function parseStdin(): Promise<PostToolUseInput | null> {
  try {
    const stdin = await Bun.stdin.text();
    if (!stdin.trim()) return null;
    return JSON.parse(stdin) as PostToolUseInput;
  } catch {
    return null;
  }
}

async function runHook(): Promise<string | null> {
  const input = await parseStdin();
  if (!input) return null;

  const filePath = input.tool_input?.file_path || "";
  if (!isPiiReminderEligibleTarget(input.tool_name, filePath)) return null;
  if (!existsSync(filePath)) return null;

  const content = await Bun.file(filePath).text();
  return evaluatePiiExposureContent(filePath, content);
}

async function main(): Promise<never> {
  let reminder: string | null = null;
  try {
    reminder = await runHook();
  } catch (err: unknown) {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    return process.exit(0);
  }

  if (reminder) {
    console.log(JSON.stringify({ decision: "block", reason: reminder }));
  }
  return process.exit(0);
}

// Run only as a hook entrypoint; stay importable by tests.
if (import.meta.main) {
  void main();
}
