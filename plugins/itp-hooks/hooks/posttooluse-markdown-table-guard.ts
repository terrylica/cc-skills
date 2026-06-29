#!/usr/bin/env bun
/**
 * PostToolUse hook: per-edit Markdown table structural guard.
 *
 * Fires on Write/Edit/MultiEdit of a `.md`/`.markdown` file. Reads the file
 * from disk (already written by the time PostToolUse runs), runs the shared
 * detector, and — ONLY when there is a render-breaking ERROR (unescaped pipe /
 * column mismatch / indented table / misplaced alignment colon) — emits the
 * Claude-visible reminder `{ decision: "block", reason }`. Info-class nits
 * (short rows, missing blank lines) are auto-fixed by the Stop-hook formatter,
 * so the per-edit hook stays silent on them to keep the signal high.
 *
 * Output channel: `{ decision: "block", reason }` is the documented PostToolUse
 * context-injection surface (ADR 2025-12-17) — it does NOT undo the edit; it
 * surfaces `reason` as a system reminder next to the tool result so Claude can
 * fix the pipes immediately.
 *
 * Escape hatch: a file containing `MD-TABLE-OK` (any comment style) suppresses
 * the reminder for that file (iter-111 canonical registry).
 *
 * Fail-open everywhere: any error → exit 0, no output.
 */

import { existsSync } from "node:fs";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  buildTableReminder,
  detectBrokenTables,
  hasTableErrors,
} from "./lib/markdown-table-detector.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

const HOOK_NAME = "posttooluse-markdown-table-guard";
const MD_TABLE_OK_MARKER = "MD-TABLE-OK";

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
}

const FILE_EDIT_TOOL_NAMES: ReadonlySet<string> = new Set(["Write", "Edit", "MultiEdit"]);

/** Match `.md` / `.markdown` (case-insensitive). */
function isMarkdownFilePath(filePath: string): boolean {
  return /\.(?:md|markdown)$/i.test(filePath);
}

/**
 * Pure activation gate (exported for tests): act only on a Write/Edit/MultiEdit
 * of a durable `.md` file, never on a throwaway copy in a temp scratch dir.
 */
export function isMarkdownTableGuardEligibleTarget(toolName: string, filePath: string): boolean {
  if (!FILE_EDIT_TOOL_NAMES.has(toolName)) return false;
  if (!filePath || !isMarkdownFilePath(filePath)) return false;
  if (
    isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
      filePath,
    )
  ) {
    return false;
  }
  return true;
}

/**
 * Pure evaluation (exported for tests): given the file content, return the
 * Claude-visible reminder string when there is a render-breaking table error,
 * or `null` when the file is clean / only has auto-fixed info nits / is
 * suppressed via the `MD-TABLE-OK` marker.
 */
export function evaluateMarkdownTableContent(filePath: string, content: string): string | null {
  if (hasFileWideEscapeHatchMarkerInContent(content, { markerNameTokenIncludingSuffix: MD_TABLE_OK_MARKER })) {
    return null;
  }
  const issues = detectBrokenTables(content);
  if (!hasTableErrors(issues)) return null;
  return buildTableReminder(filePath, issues);
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
  if (!isMarkdownTableGuardEligibleTarget(input.tool_name, filePath)) return null;
  if (!existsSync(filePath)) return null;

  const content = await Bun.file(filePath).text();
  return evaluateMarkdownTableContent(filePath, content);
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
