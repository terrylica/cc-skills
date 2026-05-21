#!/usr/bin/env bun
/**
 * PostToolUse hook: biome complementary lint checker — iter-95 dual-mode.
 *
 * Runs `biome lint <file>` after every Write/Edit of a JS/TS file.
 * biome is ~40-80ms so it's hook-viable. Runs ALONGSIDE oxlint
 * (orchestrator parallelism: both fire on the same .ts edit, neither
 * preempts the other) to catch rules oxlint misses with default config:
 *
 *   - useConst (`let` that should be `const`)
 *   - noDoubleEquals (`==` vs `===`)
 *   - useNodejsImportProtocol (prefer `node:fs` over `fs`)
 *   - noImplicitAnyLet (`let x;` without type)
 *   - noAssignInExpressions (assignment in conditions)
 *
 * If biome is not installed, surfaces a once-per-session install reminder.
 *
 * Iter-95 architectural decisions (mirror the iter-94/iter-95 conventions):
 *   1. Async Bun.spawn from inception (no spawnSync legacy)
 *   2. Dual-export naming-drift acknowledgement: precise algorithm name
 *      `classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator`
 *      explicitly encodes the COMPLEMENTARY-TO-OXLINT invariant; the alias
 *      `classifyBiomeLintForPostToolUseOrchestrator` matches sibling
 *      symmetric naming.
 *   3. Shared lib/ helpers for async-spawn + install-reminder gate file
 *   4. import.meta.main standalone guard
 *
 * Suppressed rules (from iter-94 standalone hook, preserved): the 6
 * highest-noise rules that triggered 67% of false positives on real
 * codebases (noExplicitAny, useNodejsImportProtocol, noUnusedVariables,
 * noNonNullAssertion, useTemplate, noUnusedImports). These are best
 * handled by config-level enforcement in biome.json, not hook rejection.
 */

import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  truncateHookOutputToStayBelowClaudeFileSpilloverThreshold,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
  tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";

// --- Constants ---

const JAVASCRIPT_TYPESCRIPT_EXTENSIONS_BIOME_LINT_AT_HOOK_TIME: readonly string[] = [
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
  ".mts",
  ".cts",
];
const BIOME_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

/**
 * The 6 biome rules suppressed for hook-time enforcement because they
 * produced ~67% false-positive rates on real codebases per the iter-94
 * forensic baseline. Operators wanting these rules enforced should add
 * them to a project-level biome.json (config-level enforcement, not
 * hook-level rejection).
 */
const BIOME_LINT_RULES_SUPPRESSED_AT_HOOK_TIME_BECAUSE_TOO_NOISY_FOR_REAL_CODEBASES: readonly string[] = [
  "lint/suspicious/noExplicitAny",
  "lint/style/useNodejsImportProtocol",
  "lint/correctness/noUnusedVariables",
  "lint/style/noNonNullAssertion",
  "lint/style/useTemplate",
  "lint/correctness/noUnusedImports",
];

function filePathHasJavaScriptOrTypeScriptExtensionLinterEligible(filePath: string): boolean {
  return JAVASCRIPT_TYPESCRIPT_EXTENSIONS_BIOME_LINT_AT_HOOK_TIME.some((ext) =>
    filePath.endsWith(ext),
  );
}

function buildBiomeLintSubprocessArgvForEditedFile(filePath: string): readonly string[] {
  const argv: string[] = [
    "biome", "lint",
    "--no-errors-on-unmatched",
    "--max-diagnostics=20",
    "--error-on-warnings",
    "--diagnostic-level=info",
  ];
  for (const ruleId of BIOME_LINT_RULES_SUPPRESSED_AT_HOOK_TIME_BECAUSE_TOO_NOISY_FOR_REAL_CODEBASES) {
    argv.push(`--skip=${ruleId}`);
  }
  argv.push(filePath);
  return argv;
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (!filePathHasJavaScriptOrTypeScriptExtensionLinterEligible(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (filePath.includes("/node_modules/")) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const biomeExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        buildBiomeLintSubprocessArgvForEditedFile(filePath),
        { timeoutMs: BIOME_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    if (biomeExecutionResult.spawnFailed) {
      const sessionId = input.session_id || "unknown";
      if (
        !tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName("biome", sessionId)
      ) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[BIOME] Biome linter not installed. Install for complementary JS/TS lint checks (catches rules oxlint misses):

  bun add -g @biomejs/biome

Unique catches: useConst, noDoubleEquals, useNodejsImportProtocol, noImplicitAnyLet, noAssignInExpressions.`,
      );
    }

    if (biomeExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // biome writes diagnostics to stderr, summary to stdout
    // Exit 1 = warnings/errors found (via --error-on-warnings).
    // Also check stderr for info-level diagnostics that don't trigger
    // exit 1 (e.g., useNodejsImportProtocol is info-level).
    const biomeStderr = biomeExecutionResult.stderrText;
    const hasFindings = biomeExecutionResult.exitCode !== 0 || /\blint\//.test(biomeStderr);
    if (!hasFindings) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Prefer stderr (has actual diagnostics), fall back to stdout (summary)
    const biomeOutputTextForOperator = biomeStderr || biomeExecutionResult.stdoutText;
    if (!biomeOutputTextForOperator) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Iter-105: defense-in-depth against Claude's 10K-character file-spillover threshold.
    return buildPostToolUseAdditionalContextDecision(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
        `[BIOME] Lint issues in ${filePath.split("/").pop()}:\n\n${biomeOutputTextForOperator}`,
      ),
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

export const classifyBiomeLintForPostToolUseOrchestrator =
  classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator;

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
    await classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator(
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
