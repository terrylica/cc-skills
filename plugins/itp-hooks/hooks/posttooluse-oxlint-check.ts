#!/usr/bin/env bun
/**
 * PostToolUse hook: oxlint correctness+suspicious lint checker — iter-95
 * dual-mode (standalone CLI + orchestrator-imported classifier).
 *
 * Runs `oxlint -D correctness -D suspicious` after every Write/Edit of a
 * .ts/.tsx/.js/.jsx/.mjs/.cjs/.mts/.cts file. oxlint is the Oxc Rust-based
 * linter (~40-65ms on single files), hook-viable for every edit.
 *
 * If oxlint is not installed, surfaces a once-per-session install reminder.
 *
 * Iter-95 architectural decisions (mirror the iter-94 tsgo conventions):
 *   1. Async Bun.spawn from inception (no spawnSync legacy)
 *   2. Dual-export naming-drift acknowledgement: precise algorithm-encoding
 *      name `classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`
 *      (the categories are what differentiates this from a generic
 *      "oxlint check" — correctness+suspicious are oxlint's two strictest
 *      categories per the Oxc docs). Symmetric-naming alias:
 *      `classifyOxlintCheckForPostToolUseOrchestrator`.
 *   3. Shared lib/ helpers for async-spawn + install-reminder gate file
 *   4. import.meta.main standalone guard preserves backward-compat
 *
 * Why correctness+suspicious (not all categories): these are the only
 * oxlint categories that catch RUNTIME bugs (const reassignment, duplicate
 * keys, debugger statements, etc.) — the rest are style preferences best
 * handled by config-level enforcement, not hook-level rejection. Matches
 * the iter-93+ context-injecting hook philosophy: surface bugs Claude
 * should fix, don't surface style preferences.
 */

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
  tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";
// Iter-124: skip linting throwaway scripts edited in temp dirs.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

// --- Constants ---

const JAVASCRIPT_TYPESCRIPT_EXTENSIONS_OXLINT_AND_BIOME_LINT_AT_HOOK_TIME: readonly string[] = [
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
  ".mts",
  ".cts",
];
const OXLINT_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

function filePathHasJavaScriptOrTypeScriptExtensionLinterEligible(filePath: string): boolean {
  return JAVASCRIPT_TYPESCRIPT_EXTENSIONS_OXLINT_AND_BIOME_LINT_AT_HOOK_TIME.some((ext) =>
    filePath.endsWith(ext),
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // O(1) extension filter (lightest-first registry position)
    if (!filePathHasJavaScriptOrTypeScriptExtensionLinterEligible(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (filePath.includes("/node_modules/")) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (
      isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
        filePath,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const oxlintExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        [
          "oxlint",
          "-D", "correctness",
          "-D", "suspicious",
          "-A", "no-unused-vars",
          "-A", "no-empty-file",
          "-f", "unix",
          filePath,
        ],
        { timeoutMs: OXLINT_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    if (oxlintExecutionResult.spawnFailed) {
      const sessionId = input.session_id || "unknown";
      if (
        !tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName("oxlint", sessionId)
      ) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[OXLINT] JavaScript/TypeScript linter not installed. Install for instant correctness checking after every edit:

  bun add -g oxlint

oxlint runs in ~40-65ms — fast enough to run on every edit. Catches real bugs: const reassignment, duplicate keys, debugger statements, and more.`,
      );
    }

    if (oxlintExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (oxlintExecutionResult.exitCode === 0) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const oxlintOutputTextForOperator =
      oxlintExecutionResult.stdoutText || oxlintExecutionResult.stderrText;
    if (!oxlintOutputTextForOperator) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Strip the summary line (e.g., "3 problems" or "Found 2 diagnostics")
    // so Claude sees only the actionable per-line diagnostics.
    const filteredDiagnosticLines = oxlintOutputTextForOperator
      .split("\n")
      .filter((line) => !line.match(/^Found \d+ diagnostic/) && !line.match(/^\d+ problem/));
    const filteredDiagnosticOutput = filteredDiagnosticLines.join("\n").trim();

    if (!filteredDiagnosticOutput) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Iter-105: defense-in-depth against Claude's 10K-character file-spillover threshold.
    return buildPostToolUseAdditionalContextDecision(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
        `[OXLINT] Lint issues in ${filePath.split("/").pop()}:\n\n${filteredDiagnosticOutput}`,
      ),
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

export const classifyOxlintCheckForPostToolUseOrchestrator =
  classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator;

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
    await classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator(
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
