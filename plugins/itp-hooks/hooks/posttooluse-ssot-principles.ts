#!/usr/bin/env bun
/**
 * PostToolUse hook: SSoT/DI principles reminder with ast-grep detection.
 * Triggers ONCE PER SESSION on first Write/Edit of a code file.
 *
 * ─── Iter-97 architectural change ─────────────────────────────────────────
 *
 * Iter-97 inlines this hook as the SIXTH PostToolUse orchestrator subhook
 * (6/15 in the iter-93+ migration arc). This is the FIRST migration that
 * creates REAL Promise.all parallel fan-out — ssot-principles overlaps:
 *   - `.py`            with ty (existing iter-93 subhook)
 *   - `.ts`/`.tsx`     with tsgo + oxlint + biome (iter-94/95 subhooks)
 *   - `.js`/`.jsx`     with oxlint + biome (iter-95 subhooks)
 *
 * Pre-iter-97 the orchestrator's parallelism was THEORETICAL — no two
 * subhooks shared extension filters, so each Write|Edit triggered at most
 * one classifier doing real work. Iter-97 finally exercises the
 * `Promise.all` parallel-spawn machinery: on a .ts edit, the orchestrator
 * now fans out to tsgo + oxlint + biome + ssot-principles concurrently,
 * with the wall-clock close to MAX(subhook) rather than SUM(subhook).
 *
 * ─── Iter-97 adversarial audit findings (also remediated here) ────────────
 *
 * (1) LATENT TEMP-FILE RACE — pre-iter-97 used `/tmp/.claude-ssot-scan${ext}`
 *     as a fixed-path scratch buffer for the Write-tool branch. Two
 *     simultaneous Claude sessions writing .ts files would corrupt each
 *     other's scan. Iter-97 fix: PostToolUse fires AFTER the tool executes
 *     so the file IS on disk with new content — scan filePath directly,
 *     eliminating the temp-file branch entirely (no race possible).
 *
 * (2) SHELL OVERHEAD — pre-iter-97 used Bun's `$` template literal which
 *     spawns a shell process for parsing. Iter-97 migrates to the iter-95
 *     shared helper
 *     `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail`,
 *     which uses `Bun.spawn` directly (no shell) — saves ~5-10ms per call
 *     AND applies the iter-96 256KiB maxBuffer safety net to ast-grep's
 *     potentially-huge JSON output.
 *
 * (3) NO COOPERATIVE TIMEOUT — pre-iter-97 used `$.quiet().nothrow()` with
 *     NO timeout enforcement. A pathological ast-grep run could hang the
 *     entire orchestrator. Iter-97 inherits the shared helper's
 *     AbortSignal.timeout()-driven cancellation.
 *
 * ─── Standalone CLI path retained ─────────────────────────────────────────
 *
 * The `import.meta.main` guard preserves direct-CLI invocation for tests
 * and ad-hoc audits. Standalone path uses the SAME classifier function as
 * the orchestrator path — only the I/O wrapper differs.
 *
 * GitHub Issue: https://github.com/terrylica/cc-skills/issues/28
 */

import { existsSync } from "node:fs";
import { join, extname, dirname } from "node:path";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
// Iter-106: import from the dedicated cross-Pre/PostToolUse shared lib (the
// helper's canonical home as of iter-106; relocated from the PostToolUse
// contract lib where iter-104 pragmatically introduced it).
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
  tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";
import { isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
// Iter-124: skip ast-grep scanning throwaway scripts edited in temp dirs.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Constants
// ══════════════════════════════════════════════════════════════════════════

// Iter-98: gate-file directory namespace is now constructed by the shared
// `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName`
// helper (gate dir = `/tmp/.claude-${reminderName}-reminder`). The classifier
// only supplies the reminder name; the on-disk gate path stays at
// `/tmp/.claude-ssot-principles-reminder/${sessionId}.reminded`, identical
// to iter-97 — backward-compat preserved at the filesystem layer.
const SSOT_PRINCIPLES_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE = "ssot-principles";

const AST_GREP_SSOT_RULES_PROJECT_DIRECTORY_ABSOLUTE_PATH = join(
  dirname(import.meta.path),
  "ast-grep-ssot",
);
const AST_GREP_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 2000;
const MAX_RENDERED_AST_GREP_FINDINGS_BEFORE_TRUNCATION = 10;

const CODE_FILE_EXTENSIONS_SCANNED_FOR_SSOT_VIOLATIONS = new Set([
  ".py",
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".rs",
  ".go",
  ".java",
  ".kt",
  ".rb",
]);

const TEST_FILE_PATH_PATTERNS_EXCLUDED_FROM_SSOT_SCAN: readonly RegExp[] = [
  /\/test_/,
  /\/tests\//,
  /_test\./,
  /_spec\./,
  /\.test\./,
  /\.spec\./,
  /\/conftest\.py$/,
  /\/__tests__\//,
];

// ══════════════════════════════════════════════════════════════════════════
//  Once-per-session gate (delegated to iter-98 shared helper)
// ══════════════════════════════════════════════════════════════════════════
//
// Iter-98 hoist: the iter-97-era local
// `tryAtomicallyClaimOncePerSessionSsotPrinciplesReminderGateFile` helper
// has been REMOVED in favor of the shared
// `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName`
// at lib/posttooluse-subhook-async-subprocess-execution-and-once-per-
// session-reminder-gate-file-helpers-iter95.ts. The on-disk gate path is
// identical (`/tmp/.claude-ssot-principles-reminder/${sessionId}.reminded`)
// so existing sessions are NOT re-reminded after the upgrade.

// ══════════════════════════════════════════════════════════════════════════
//  ast-grep findings
// ══════════════════════════════════════════════════════════════════════════

interface AstGrepFinding {
  ruleId: string;
  text: string;
  message: string;
  range: { start: { line: number; column: number } };
  file: string;
}

function isCodeFileExtensionEligibleForSsotPrinciplesScan(filePath: string): boolean {
  return CODE_FILE_EXTENSIONS_SCANNED_FOR_SSOT_VIOLATIONS.has(extname(filePath));
}

function isTestFilePathExcludedFromSsotPrinciplesScan(filePath: string): boolean {
  return TEST_FILE_PATH_PATTERNS_EXCLUDED_FROM_SSOT_SCAN.some((pattern) => pattern.test(filePath));
}

function hasSsotOkEscapeHatchCommentInProposedContent(content: string | undefined): boolean {
  if (!content) return false;
  return /(?:#|\/\/)\s*SSoT-OK/.test(content);
}

/**
 * Run ast-grep on the edited file using the iter-95 shared async-spawn
 * helper. PostToolUse invariant: the file is already written to disk by
 * the time we run, so we scan filePath directly — no temp-file dance.
 *
 * Iter-97 hardening vs pre-iter-97 implementation:
 *   - No shell spawn (was: `bun $` template literal → shell)
 *   - AbortSignal.timeout cooperative cancellation (was: no timeout)
 *   - 256KiB maxBuffer safety net (was: no bound on JSON output size)
 *   - Standardized error handling (was: bespoke try/catch + .nothrow())
 *
 * Returns empty array on any error (fail-open — the principles reminder
 * itself still fires).
 */
async function runAstGrepScanOnEditedFileAndParseJsonFindingsAsynchronously(
  filePath: string,
): Promise<AstGrepFinding[]> {
  if (!existsSync(AST_GREP_SSOT_RULES_PROJECT_DIRECTORY_ABSOLUTE_PATH)) return [];

  const astGrepExecutionResult =
    await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
      ["ast-grep", "scan", filePath, "--json"],
      {
        cwd: AST_GREP_SSOT_RULES_PROJECT_DIRECTORY_ABSOLUTE_PATH,
        timeoutMs: AST_GREP_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS,
      },
    );

  if (astGrepExecutionResult.spawnFailed) return [];
  if (astGrepExecutionResult.timedOut) return [];

  // ast-grep exits non-zero when no findings — but emits `[]` JSON. We
  // tolerate non-zero exit as long as stdout parses to a valid array.
  const stdoutText = astGrepExecutionResult.stdoutText;
  if (!stdoutText || stdoutText === "[]") return [];

  try {
    const parsed = JSON.parse(stdoutText);
    if (!Array.isArray(parsed)) return [];
    return parsed as AstGrepFinding[];
  } catch {
    return [];
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Reminder message builder
// ══════════════════════════════════════════════════════════════════════════

const SSOT_PRINCIPLES_REMINDER_BASE_MESSAGE = `[SSoT-PRINCIPLES] When writing code, prefer these patterns for maintainability:

1. CONFIG SINGLETON over scattered env var calls
   → Centralize config in one validated object; add constructor validation for fail-fast

2. NONE-DEFAULT + RESOLVER over hardcoded defaults
   → def foo(mode: str | None = None) + resolve from config if None
   → Changing the system default = one env var, not 10 file edits

3. ENTRY-POINT VALIDATION over deep-in-logic checks
   → Validate all inputs at public API boundaries, not in inner functions

4. HIERARCHICAL LOOKUP over flat defaults
   → Per-item override → registry → class default → fallback (with warning)

Escape hatch: # SSoT-OK (same as version-guard)
Skill: /itp:impl-standards → references/ssot-dependency-injection.md
Batch audit: /itp:code-hardcode-audit (adds ast-grep to Ruff+Semgrep+jscpd+gitleaks)`;

function buildSsotPrinciplesReminderMessageWithAstGrepFindingsAppended(
  findings: readonly AstGrepFinding[],
  filePath: string,
): string {
  if (findings.length === 0) return SSOT_PRINCIPLES_REMINDER_BASE_MESSAGE;

  // Deduplicate by ruleId+line so the same anti-pattern across N lines
  // doesn't spam the reminder.
  const seenRuleAtLineKeys = new Set<string>();
  const renderedFindingLines: string[] = [];
  for (const f of findings) {
    const dedupKey = `${f.ruleId}:${f.range.start.line}`;
    if (seenRuleAtLineKeys.has(dedupKey)) continue;
    seenRuleAtLineKeys.add(dedupKey);
    if (renderedFindingLines.length >= MAX_RENDERED_AST_GREP_FINDINGS_BEFORE_TRUNCATION) break;
    const oneBasedLineNumber = f.range.start.line + 1;
    const truncatedMatchText = f.text.length > 60 ? `${f.text.slice(0, 57)}...` : f.text;
    const firstLineOfMessage = f.message.split("\n")[0]?.trim() ?? "";
    renderedFindingLines.push(
      `  • ${filePath}:${oneBasedLineNumber} — ${firstLineOfMessage} (${truncatedMatchText})`,
    );
  }

  const remainingCount = findings.length - renderedFindingLines.length;
  const truncationFooter =
    remainingCount > 0
      ? `\n  ... (${remainingCount} more finding(s) suppressed; full audit via /itp:code-hardcode-audit)`
      : "";

  return `${SSOT_PRINCIPLES_REMINDER_BASE_MESSAGE}\n\nDETECTED in current edit:\n${renderedFindingLines.join("\n")}${truncationFooter}`;
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Classify a PostToolUse Write|Edit event for SSoT-principles relevance.
 *
 *   - Returns `additional_context` ONCE PER SESSION on the first eligible
 *     code-file edit (gated atomically via O_EXCL).
 *   - All subsequent edits in the same session return `noop` (gate already
 *     claimed). The orchestrator's `Promise.all` parallelism is unaffected
 *     — the gate check + early-return is a sub-millisecond filesystem
 *     `mkdirSync` + `openSync(... O_EXCL)` round-trip.
 *   - Skips test files (test fixtures legitimately hardcode values).
 *   - Honors `# SSoT-OK` / `// SSoT-OK` escape-hatch comment in the
 *     proposed content (suppresses the reminder for files explicitly
 *     marked as exempt by the author).
 */
export async function classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    // Iter-100: honor Write|Edit|MultiEdit via canonical contract helper
    // (closes the MultiEdit coverage gap surfaced by web research).
    if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(input.tool_name)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (!isCodeFileExtensionEligibleForSsotPrinciplesScan(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (isTestFilePathExcludedFromSsotPrinciplesScan(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (
      isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
        filePath,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const proposedContent =
      (typeof input.tool_input?.content === "string" ? input.tool_input.content : undefined) ||
      (typeof input.tool_input?.new_string === "string"
        ? input.tool_input.new_string
        : undefined);

    if (hasSsotOkEscapeHatchCommentInProposedContent(proposedContent)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || "unknown";
    if (
      !tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(
        SSOT_PRINCIPLES_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE,
        sessionId,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // PostToolUse invariant: file is on disk with proposed content by the
    // time we run. No temp-file scratch buffer needed.
    if (!existsSync(filePath)) {
      // The file should exist (PostToolUse fires after Write/Edit), but
      // in edge cases (e.g., concurrent file deletion) we still want to
      // fire the principles reminder even without ast-grep findings.
      return buildPostToolUseAdditionalContextDecision(SSOT_PRINCIPLES_REMINDER_BASE_MESSAGE);
    }

    const astGrepFindings = await runAstGrepScanOnEditedFileAndParseJsonFindingsAsynchronously(filePath);

    // Filter out findings whose matched text already includes the SSoT-OK
    // escape hatch (per-finding suppression — e.g., `default = "..."  # SSoT-OK`).
    const findingsExcludingPerLineEscapeHatch = astGrepFindings.filter(
      (f) => !/SSoT-OK/.test(f.text),
    );

    // Iter-105: defense-in-depth against Claude's 10K-character file-spillover threshold
    // (astGrepFindings count is unbounded per edited file).
    return buildPostToolUseAdditionalContextDecision(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
        buildSsotPrinciplesReminderMessageWithAstGrepFindingsAppended(
          findingsExcludingPerLineEscapeHatch,
          filePath,
        ),
      ),
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

/**
 * Symmetric-naming alias matching the sibling subhooks (ty, tsgo, oxlint,
 * biome, vale). The precise algorithm-encoding name above carries the
 * "AstGrep-based" detail; the alias is what the orchestrator imports.
 */
export const classifySsotPrinciplesForPostToolUseOrchestrator =
  classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator;

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  // Iter-96 idiom: Bun.stdin.text() one-shot read
  const inputText = await Bun.stdin.text();

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision =
    await classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator(
      input,
    );

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
