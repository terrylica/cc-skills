#!/usr/bin/env bun
/**
 * PreToolUse hook: Vale CLAUDE.md Terminology Guard (iter-91 orchestrator-inlined — FINAL SUBHOOK OF MIGRATION ARC)
 *
 * Rejects Edit/Write on `CLAUDE.md` files if `vale` lint (terminology config
 * at `~/.claude/.vale.ini`) finds warning-or-error issues. For Edit, scopes
 * to the changed-line range ± 3-line buffer so pre-existing issues elsewhere
 * in the file don't false-positive.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Iter-91: COMPLETES the iter-84 → iter-91 PreToolUse Write|Edit migration arc
 * ════════════════════════════════════════════════════════════════════════
 *
 * After this migration the orchestrator owns ALL 8 PreToolUse Write|Edit
 * subhooks. Final-state empirical savings projection per iter-87
 * microbenchmark: (8-1) × ~17ms = ~119ms per Write|Edit tool call (NOT
 * iter-81's optimistic 308ms based on iter-80's inflated 44ms estimate).
 *
 * Vale is the heaviest classifier in the registry: it spawns the external
 * `vale` subprocess and writes proposed content to a tempfile before
 * linting. Wall-clock latency for vale on a typical CLAUDE.md is 100-300ms.
 * The orchestrator's per-subhook cooperative timeout MUST be ≥10000ms for
 * vale's registry entry to avoid spurious AbortSignal.timeout() trips on
 * slow-disk machines.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Iter-91 dual-use contract (mirrors iter-85/86/87/88/89/90 migrations):
 * ════════════════════════════════════════════════════════════════════════
 *
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-vale-claude-md-guard.ts < payload.json` runs main()
 *     under `import.meta.main` guard.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports
 *     `classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator`
 *     (with backward-compat alias `classifyValeClaudeMdGuardForOrchestrator`)
 *     and invokes it directly in the single bun process.
 *
 * MUST NOT emit `hookSpecificOutput.additionalContext` per iter-90 GH #15664
 * marketplace invariant.
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { $ } from "bun";
import {
  allow,
  deny,
  ask,
  parseStdinOrAllow,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  askDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
// Iter-105: cross-lib import of the canonical truncation helper from the
// PostToolUse contract lib. The helper is pure string truncation against
// Claude's 10K-character hook-output file-spillover threshold and is
// semantically shared across both PreToolUse + PostToolUse paths (per
// iter-104 design rationale). Iter-106+ candidate: extract to a dedicated
// shared lib file once more cross-Pre/PostToolUse helpers emerge.
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// ============================================================================
// Configuration
// ============================================================================

const VALE_CLAUDE_MD_GUARD_USER_HOME_DIRECTORY = process.env.HOME || "";
const VALE_CLAUDE_MD_GUARD_VALE_INI_CONFIG_FILE_PATH = join(
  VALE_CLAUDE_MD_GUARD_USER_HOME_DIRECTORY,
  ".claude/.vale.ini",
);

/** Hard block when issues found (Claude autonomously fixes terminology). */
const VALE_CLAUDE_MD_GUARD_ENFORCEMENT_MODE: "deny" | "ask" = "deny";

/** "warning" includes warnings + errors; "error" includes errors only. */
const VALE_CLAUDE_MD_GUARD_SEVERITY_INCLUSION_THRESHOLD: "warning" | "error" = "warning";

/** Edit-scoping buffer: lines around the changed region also fall in-scope. */
const VALE_CLAUDE_MD_GUARD_EDIT_LINE_RANGE_BUFFER_LINE_COUNT = 3;

// ============================================================================
// Types
// ============================================================================

interface ValeLintFinding {
  severity: string;
  message: string;
  line: number;
}

interface EditApplicationResult {
  /** Synthesized post-edit content used as vale's input. */
  content: string;
  /** 1-based inclusive line range covering the changed region ± buffer, or null if old_string not found. */
  lineRange: { start: number; end: number } | null;
}

// ============================================================================
// Pure helpers (no I/O dependencies on Claude Code hook framework)
// ============================================================================

/**
 * Apply an Edit's `old_string` → `new_string` to existing on-disk content
 * and compute the affected 1-based line range. If `old_string` isn't found,
 * returns the original content and `lineRange: null` (caller's downstream
 * vale lint should still proceed; Claude Code itself will error on the
 * actual Edit tool invocation if old_string is missing).
 */
function synthesizeEditApplicationResult(
  existingFileContent: string,
  oldStringToReplace: string,
  newStringReplacement: string,
): EditApplicationResult {
  const matchOffset = existingFileContent.indexOf(oldStringToReplace);
  if (matchOffset === -1) {
    return { content: existingFileContent, lineRange: null };
  }
  const synthesizedContent =
    existingFileContent.slice(0, matchOffset) +
    newStringReplacement +
    existingFileContent.slice(matchOffset + oldStringToReplace.length);
  const oneBasedLineWhereEditStarts = existingFileContent.slice(0, matchOffset).split("\n").length;
  const newStringLineCount = newStringReplacement.split("\n").length;
  const lineRangeStart = Math.max(1, oneBasedLineWhereEditStarts - VALE_CLAUDE_MD_GUARD_EDIT_LINE_RANGE_BUFFER_LINE_COUNT);
  const lineRangeEnd =
    oneBasedLineWhereEditStarts +
    newStringLineCount -
    1 +
    VALE_CLAUDE_MD_GUARD_EDIT_LINE_RANGE_BUFFER_LINE_COUNT;
  return { content: synthesizedContent, lineRange: { start: lineRangeStart, end: lineRangeEnd } };
}

/**
 * Spawn `vale --output=JSON` against a tempfile containing the proposed
 * content. Returns parsed findings (empty array if vale errors or no issues).
 * The caller owns severity filtering and edit-range scoping.
 */
async function runValeAgainstProposedContentTempfileAndParseJsonFindings(
  proposedContent: string,
): Promise<ValeLintFinding[]> {
  const valeTempfileWorkingDirectory = mkdtempSync(join(tmpdir(), "vale-claude-md-guard-"));
  const valeTempfilePath = join(valeTempfileWorkingDirectory, "CLAUDE.md");

  try {
    writeFileSync(valeTempfilePath, proposedContent);

    // Vale exit codes: 0 = no issues, 1 = issues found (both expected); others = vale-internal error.
    const valeSubprocessResult = await $`vale --config=${VALE_CLAUDE_MD_GUARD_VALE_INI_CONFIG_FILE_PATH} --output=JSON ${valeTempfilePath}`
      .quiet()
      .nothrow();

    if (valeSubprocessResult.exitCode !== 0 && valeSubprocessResult.exitCode !== 1) {
      trackHookError(
        "pretooluse-vale-claude-md-guard",
        `Vale subprocess error (exit=${valeSubprocessResult.exitCode}): ${valeSubprocessResult.stderr.toString()}`,
      );
      return [];
    }

    const valeStdoutText = valeSubprocessResult.stdout.toString().trim();
    if (!valeStdoutText) return [];

    const valeJsonParsedOutput = JSON.parse(valeStdoutText) as Record<string, unknown>;
    const accumulatedFindings: ValeLintFinding[] = [];
    for (const [, perFileFindingsArray] of Object.entries(valeJsonParsedOutput)) {
      if (Array.isArray(perFileFindingsArray)) {
        for (const rawFinding of perFileFindingsArray) {
          const findingRecord = rawFinding as { Severity?: string; Message?: string; Line?: number };
          accumulatedFindings.push({
            severity: findingRecord.Severity?.toLowerCase() || "warning",
            message: findingRecord.Message || "Unknown issue",
            line: findingRecord.Line || 0,
          });
        }
      }
    }
    return accumulatedFindings;
  } finally {
    try {
      unlinkSync(valeTempfilePath);
    } catch {
      // Ignore cleanup errors
    }
  }
}

/** Filter vale findings by the configured severity inclusion threshold. */
function filterValeFindingsBySeverityInclusionThreshold(
  findings: ValeLintFinding[],
  thresholdSeverity: "warning" | "error",
): ValeLintFinding[] {
  if (thresholdSeverity === "error") return findings.filter((f) => f.severity === "error");
  return findings.filter((f) => f.severity === "warning" || f.severity === "error");
}

/** Format vale findings as a human-readable bulleted list for the deny message. */
function formatValeFindingsForOperatorDisplay(findings: ValeLintFinding[]): string {
  return findings
    .map((f) => `  Line ${f.line}: [${f.severity.toUpperCase()}] ${f.message}`)
    .join("\n");
}

// ============================================================================
// Pure classifier (iter-91 orchestrator-inlineable contract)
// ============================================================================

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Short-circuit order (cheap → expensive):
 *   1. tool_name not Write/Edit → ALLOW
 *   2. file_path does NOT endsWith CLAUDE.md → ALLOW (O(1) suffix check)
 *   3. ~/.claude/.vale.ini missing → ALLOW (no config = no enforcement)
 *   4. Edit + existing file missing → ALLOW (can't validate edit)
 *   5. Spawn vale subprocess (heaviest step) → DENY/ASK on findings
 *
 * MUST NOT call allow()/deny()/ask() or touch stdin/stdout/process.exit.
 * MUST NOT emit `additionalContext` (silently dropped per iter-90 audit GH #15664).
 */
export async function classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input } = input;

  // Iter-102: route through canonical contract helper (closes iter-101 residual gap).
  if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(tool_name)) {
    return ALLOW_DECISION;
  }
  // Iter-102 staged-migration short-circuit: MultiEdit payload-shape
  // adaptation is iter-103+ per-classifier work. Preserves status quo
  // (vale-claude-md-guard's downstream Write/Edit content-extraction
  // branches don't yet handle tool_input.edits[]).
  if (tool_name === "MultiEdit") {
    return ALLOW_DECISION;
  }

  const filePath = (tool_input?.file_path as string) || "";
  if (!filePath.endsWith("CLAUDE.md")) {
    return ALLOW_DECISION;
  }

  if (!existsSync(VALE_CLAUDE_MD_GUARD_VALE_INI_CONFIG_FILE_PATH)) {
    return ALLOW_DECISION;
  }

  let proposedContent: string;
  let editLineRange: { start: number; end: number } | null = null;

  if (tool_name === "Write") {
    proposedContent = (tool_input?.content as string) || "";
  } else {
    // Edit path
    const oldString = (tool_input?.old_string as string) || "";
    const newString = (tool_input?.new_string as string) || "";

    if (!existsSync(filePath)) {
      return ALLOW_DECISION;
    }

    const existingFileContent = readFileSync(filePath, "utf8");
    const editResult = synthesizeEditApplicationResult(existingFileContent, oldString, newString);
    proposedContent = editResult.content;
    editLineRange = editResult.lineRange;
  }

  const allValeFindings = await runValeAgainstProposedContentTempfileAndParseJsonFindings(proposedContent);
  const severityFilteredFindings = filterValeFindingsBySeverityInclusionThreshold(
    allValeFindings,
    VALE_CLAUDE_MD_GUARD_SEVERITY_INCLUSION_THRESHOLD,
  );

  // Edit-scoping: only report findings within the changed-line range ± buffer
  const inScopeFindings = editLineRange
    ? severityFilteredFindings.filter(
        (f) => f.line >= editLineRange!.start && f.line <= editLineRange!.end,
      )
    : severityFilteredFindings;

  if (inScopeFindings.length === 0) {
    return ALLOW_DECISION;
  }

  const claudeMdFileName = filePath.split("/").pop() || "CLAUDE.md";
  const editScopeAnnotation = editLineRange
    ? ` (scoped to changed lines ${editLineRange.start}-${editLineRange.end})`
    : "";

  const denyReasonUnbounded = [
    `[VALE-CLAUDE-MD-GUARD] Found ${inScopeFindings.length} terminology issue(s) in ${claudeMdFileName}${editScopeAnnotation}:`,
    "",
    formatValeFindingsForOperatorDisplay(inScopeFindings),
    "",
    "Fix the issues before saving. Check ~/.claude/docs/GLOSSARY.md for correct terminology.",
  ].join("\n");

  // Iter-105: defense-in-depth against Claude's 10K-character hook-output
  // file-spillover threshold. inScopeFindings count is unbounded — a
  // heavily-edited CLAUDE.md can trigger 50-200+ findings producing 10K+
  // chars. Cross-lib import of the canonical truncation helper from the
  // PostToolUse contract lib (helper is pure string truncation, semantically
  // shared across both Pre/PostToolUse paths per iter-104 design).
  const denyReason = truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
    denyReasonUnbounded,
  );

  return VALE_CLAUDE_MD_GUARD_ENFORCEMENT_MODE === "deny"
    ? denyDecision(denyReason)
    : askDecision(denyReason);
}

/**
 * Backward-compat alias for symmetric naming with sibling iter-84/85/86/87/88/89/90
 * subhook cohort (`classify<FilenamePrefix>ForOrchestrator`). The precise
 * algorithm-encoding name (`classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator`)
 * is what should be read for understanding the actual policy.
 */
export const classifyValeClaudeMdGuardForOrchestrator = classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator;

// ============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("vale-claude-md-guard");
  if (!input) return;

  const decision = await classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator(input);
  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      return ask(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

if (import.meta.main) {
  main().catch((err: unknown) => {
    trackHookError("pretooluse-vale-claude-md-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
