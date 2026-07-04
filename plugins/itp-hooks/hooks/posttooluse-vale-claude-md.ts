#!/usr/bin/env bun
/**
 * PostToolUse hook: Vale terminology check on edited CLAUDE.md files —
 * iter-96 dual-mode (standalone CLI + orchestrator-imported classifier).
 *
 * Non-blocking informational check (visibility only). Claude sees
 * terminology violations and can act on them in the next turn. Uses
 * `decision: "block"` JSON for synchronous PostToolUse context injection
 * (iter-66 schema convention — "block" here is the documented Anthropic
 * mechanism for surfacing context post-edit; it does NOT actually block
 * because the tool has already run).
 *
 * Scoping: For Edit tool, only reports issues on lines that were actually
 * changed (±3-line buffer). Write tool checks the entire file (all content
 * is new). Prevents flagging pre-existing issues elsewhere.
 *
 * ─── Iter-96 architectural decisions ──────────────────────────────────────
 *
 * 1. **5th inlined subhook** in the iter-93+ PostToolUse migration arc
 *    (5/15). Same pattern as iter-95's oxlint + biome (async Bun.spawn via
 *    shared lib helpers).
 * 2. **Dual-export naming-drift acknowledgement**:
 *    `classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator`
 *    (precise: encodes that this checks TERMINOLOGY CONFORMANCE, not
 *    grammar/spelling). Symmetric-naming alias:
 *    `classifyValeClaudeMdForPostToolUseOrchestrator`.
 * 3. **Configuration discovery**: walks up from the edited file's directory
 *    looking for `.vale.ini`, falls back to `~/.claude/.vale.ini`. cwd-
 *    agnostic so the hook works from any directory.
 * 4. **Edit-path line scoping**: for Edit operations, computes the changed
 *    line range (±3-line buffer) and filters Vale output to only those
 *    lines. Prevents pre-existing-issue spam.
 * 5. **Twin to iter-91 PreToolUse vale-claude-md-guard**: that one BLOCKS
 *    before edit; this one INFORMS after edit. Different semantic, same
 *    underlying vale invocation.
 */

import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
// Iter-106: import from the dedicated cross-Pre/PostToolUse shared lib (the
// helper's canonical home as of iter-106; relocated from the PostToolUse
// contract lib where iter-104 pragmatically introduced it).
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
import { executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail } from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";
// Iter-124: skip vale linting throwaway CLAUDE.md edited in temp dirs.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

// --- Constants ---

const VALE_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 10000;
const EDITED_LINE_RANGE_CONTEXT_BUFFER_LINES = 3;

// --- Types ---

interface EditedLineRange {
  start: number;
  end: number;
}

interface ValeIssue {
  line: number;
  severity: "error" | "warning" | "suggestion";
  message: string;
  rule: string;
}

// --- Helpers ---

/**
 * Find Vale config file by walking up from file's directory, then fall back
 * to global ~/.claude/.vale.ini. Makes the hook work regardless of cwd.
 */
function locateValeConfigurationFileWalkingUpFromEditedFileDirectoryThenFallingBackToGlobal(
  filePath: string,
): string | null {
  const globalConfig = join(process.env.HOME || "", ".claude", ".vale.ini");

  let dir = dirname(filePath);
  const root = "/";
  while (dir !== root) {
    const candidate = join(dir, ".vale.ini");
    if (existsSync(candidate)) {
      return candidate;
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  if (existsSync(globalConfig)) return globalConfig;
  return null;
}

/**
 * Compute the line range affected by an Edit operation. Returns null for
 * Write (entire file is new) or if range can't be uniquely determined.
 * Uses ±3-line buffer to catch context-dependent issues.
 */
function computeEditedLineRangeFromNewStringWithThreeLineContextBuffer(
  filePath: string,
  newString: string,
): EditedLineRange | null {
  if (!newString || !existsSync(filePath)) return null;

  try {
    const content = readFileSync(filePath, "utf8");
    const lines = content.split("\n");

    const firstLine = newString.split("\n").find((l) => l.trim().length > 0);
    if (!firstLine) return null;

    let matchCount = 0;
    let matchLineNum = -1;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes(firstLine.trim())) {
        matchCount++;
        matchLineNum = i + 1;
      }
    }

    if (matchCount !== 1 || matchLineNum < 1) return null;

    const newLineCount = newString.split("\n").length;
    const start = Math.max(1, matchLineNum - EDITED_LINE_RANGE_CONTEXT_BUFFER_LINES);
    const end = matchLineNum + newLineCount - 1 + EDITED_LINE_RANGE_CONTEXT_BUFFER_LINES;

    return { start, end };
  } catch {
    return null;
  }
}

/**
 * Parse Vale's JSON output into structured issues.
 */
function parseValeJsonOutputIntoStructuredIssues(stdoutJsonText: string): ValeIssue[] {
  const issues: ValeIssue[] = [];
  if (!stdoutJsonText) return issues;

  try {
    const valeOutput = JSON.parse(stdoutJsonText) as Record<string, unknown>;
    for (const [_file, fileIssues] of Object.entries(valeOutput)) {
      if (Array.isArray(fileIssues)) {
        for (const rawIssue of fileIssues) {
          const i = rawIssue as {
            Line?: number;
            Severity?: string;
            Message?: string;
            Check?: string;
          };
          issues.push({
            line: i.Line || 0,
            severity: (i.Severity?.toLowerCase() || "warning") as ValeIssue["severity"],
            message: i.Message || "Unknown issue",
            rule: i.Check || "",
          });
        }
      }
    }
  } catch {
    // JSON parse failed — return empty issues (fail-open)
  }

  return issues;
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const toolName = input.tool_name || "";
    const filePath = input.tool_input?.file_path || "";

    // Iter-100: honor Write|Edit|MultiEdit via canonical contract helper
    // (closes the MultiEdit coverage gap surfaced by web research).
    if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(toolName)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (!filePath.endsWith("CLAUDE.md")) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (
      isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
        filePath,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (!existsSync(filePath)) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const configPath =
      locateValeConfigurationFileWalkingUpFromEditedFileDirectoryThenFallingBackToGlobal(filePath);
    if (!configPath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Compute changed-line range for Edit (Write reports on whole file)
    let editedLineRange: EditedLineRange | null = null;
    if (toolName === "Edit" && !input.tool_input?.replace_all) {
      const newString = (input.tool_input?.new_string as string) || "";
      editedLineRange = computeEditedLineRangeFromNewStringWithThreeLineContextBuffer(
        filePath,
        newString,
      );
    }

    // Run vale from the file's directory so glob patterns in the config match
    const fileDir = dirname(filePath);
    const fileName = basename(filePath);
    const valeExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        ["vale", "--config", configPath, "--output=JSON", fileName],
        { cwd: fileDir, timeoutMs: VALE_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    // Spawn-failed-to-start (vale not in PATH) → silent noop (no install
    // reminder — vale is OPTIONAL for projects without terminology
    // enforcement; the PreToolUse iter-91 guard handles the "no vale config"
    // case for projects that DO want it)
    if (valeExecutionResult.spawnFailed) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (valeExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const allIssues = parseValeJsonOutputIntoStructuredIssues(valeExecutionResult.stdoutText);
    const scopedIssues = editedLineRange
      ? allIssues.filter(
          (i) => i.line >= editedLineRange.start && i.line <= editedLineRange.end,
        )
      : allIssues;

    if (scopedIssues.length === 0) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const errorCount = scopedIssues.filter((i) => i.severity === "error").length;
    const warningCount = scopedIssues.filter((i) => i.severity === "warning").length;
    const suggestionCount = scopedIssues.filter((i) => i.severity === "suggestion").length;

    const issueLines = scopedIssues
      .map((i) => `  Line ${i.line}: [${i.severity.toUpperCase()}] ${i.message} (${i.rule})`)
      .join("\n");

    const scopeNote = editedLineRange
      ? ` (scoped to changed lines ${editedLineRange.start}-${editedLineRange.end})`
      : "";

    const unboundedRawReason = `[VALE] Found ${errorCount} errors, ${warningCount} warnings, ${suggestionCount} suggestions in ${basename(filePath)}${scopeNote}:

${issueLines}

**Options:**
1. Fix terminology automatically (use acronyms: ITH, TMAEG, MCOT, NAV, CV, dbps)
2. Keep expanded form if this is a definition (Terminology table)
3. Ask user which terms to expand/contract`;

    // Iter-104: defend against Claude's 10,000-character hook-output
    // file-spillover threshold. Vale on a heavily-CLAUDE.md-edited file can
    // emit 50-200+ findings; the issueLines concatenation is unbounded in
    // scopedIssues.length. Without this guard, large vale runs would silently
    // file-spill the diagnostic content — Claude would see a preview stub,
    // never the actual findings. The truncation helper appends an explicit
    // marker so Claude knows there may be additional unseen issues.
    const reason = truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
      unboundedRawReason,
    );

    return buildPostToolUseAdditionalContextDecision(reason);
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

export const classifyValeClaudeMdForPostToolUseOrchestrator =
  classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator;

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  // Iter-96: Bun.stdin.text() one-shot read (2026 idiomatic API)
  const inputText = await Bun.stdin.text();

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision =
    await classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator(input);

  if (decision.kind === "additional_context") {
    console.log(JSON.stringify({ decision: "block", reason: decision.message }));
  }
  process.exit(0);
}

if (import.meta.main) {
  runStandaloneCliMain().catch(() => {
    process.exit(0);
  });
}
