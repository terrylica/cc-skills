#!/usr/bin/env bun
/**
 * PostToolUse hook: ty type checker (iter-93 dual-mode + iter-94 async-spawn
 * + iter-95 shared-lib-helpers refactor).
 *
 * Runs `ty check <file>` after every Write/Edit of a .py/.pyi file.
 * ty is ~60x faster than mypy (4.7ms incremental) so it's hook-viable.
 *
 * CRITICAL: Always runs with --python-version 3.13. Uses --output-format
 * concise for one-line diagnostics. If ty is not installed, surfaces a
 * once-per-session install reminder via the iter-95 shared helper.
 * Tracks .py edits via gate file for the Stop hook
 * (stop-ty-project-check.ts).
 *
 * Fail-open everywhere — every catch returns a `noop` (orchestrator path)
 * or exits 0 (standalone path).
 *
 * ─── Iter-95 architectural change ─────────────────────────────────────────
 *
 * Iter-94 inlined the async-spawn + install-reminder gate-file helpers
 * directly in this file (verbatim copies between ty + tsgo). With iter-95
 * adding oxlint + biome (3rd + 4th subhooks), 4 copies of the same
 * helpers would drift. Iter-95 hoists them to
 * `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`
 * so every classifier imports the same implementation. Iter-95 also adds
 * a `maxBuffer` (default 8MiB per Bun docs) safety net to bound runaway
 * subprocess output.
 */

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, basename } from "node:path";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
  tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";

// --- Constants ---

const PYTHON_EDIT_GATE_DIRECTORY_FOR_STOP_HOOK_HANDOFF = "/tmp/.claude-ty-edits";
const MAX_TYPE_CHECK_DIAGNOSTIC_LINES_BEFORE_TRUNCATION = 30;
const TY_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

function touchPythonEditGateFileForStopHookHandoffSwallowingAllFilesystemErrors(
  sessionId: string,
): void {
  try {
    mkdirSync(PYTHON_EDIT_GATE_DIRECTORY_FOR_STOP_HOOK_HANDOFF, { recursive: true });
    writeFileSync(
      join(PYTHON_EDIT_GATE_DIRECTORY_FOR_STOP_HOOK_HANDOFF, `${sessionId}.edited`),
      "",
      { flag: "w" },
    );
  } catch {
    // Gate file failure is non-critical — continue
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (!filePath.endsWith(".py") && !filePath.endsWith(".pyi")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (filePath.includes("/.venv/") || filePath.includes("/node_modules/")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (!existsSync(filePath)) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || "unknown";
    touchPythonEditGateFileForStopHookHandoffSwallowingAllFilesystemErrors(sessionId);

    const tyExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        ["ty", "check", filePath, "--python-version", "3.13", "--output-format", "concise"],
        { timeoutMs: TY_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    if (tyExecutionResult.spawnFailed) {
      const sessionIdForGate = input.session_id || "unknown";
      if (
        !tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName(
          "ty",
          sessionIdForGate,
        )
      ) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[TY] Python type checker not installed. Install for instant type checking after every .py edit:

  uv tool install ty

ty is 60x faster than mypy (4.7ms incremental) — fast enough to run on every edit.`,
      );
    }

    if (tyExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (tyExecutionResult.exitCode === 2 || tyExecutionResult.exitCode === 101) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (tyExecutionResult.exitCode === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const tyOutputTextForOperator = tyExecutionResult.stdoutText || tyExecutionResult.stderrText;
    if (!tyOutputTextForOperator) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const diagnosticLines = tyOutputTextForOperator.split("\n").filter((l) => l.trim() !== "");
    const tyErrorDiagnosticCount = diagnosticLines.filter((l) => l.includes(": error:")).length;
    const tyWarningDiagnosticCount = diagnosticLines.filter((l) => l.includes(": warning:")).length;
    const editedFileBaseName = basename(filePath);

    let renderedDiagnostics: string;
    if (diagnosticLines.length > MAX_TYPE_CHECK_DIAGNOSTIC_LINES_BEFORE_TRUNCATION) {
      renderedDiagnostics =
        diagnosticLines.slice(0, MAX_TYPE_CHECK_DIAGNOSTIC_LINES_BEFORE_TRUNCATION).join("\n") +
        `\n... (${diagnosticLines.length} total diagnostics, showing first ${MAX_TYPE_CHECK_DIAGNOSTIC_LINES_BEFORE_TRUNCATION})`;
    } else {
      renderedDiagnostics = diagnosticLines.join("\n");
    }

    const diagnosticSummaryLine =
      tyErrorDiagnosticCount > 0
        ? `[TY] ${tyErrorDiagnosticCount} error(s), ${tyWarningDiagnosticCount} warning(s) in ${editedFileBaseName}`
        : `[TY] ${tyWarningDiagnosticCount} warning(s) in ${editedFileBaseName}`;

    return buildPostToolUseAdditionalContextDecision(
      `${diagnosticSummaryLine}:\n\n${renderedDiagnostics}`,
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

export const classifyTyTypeCheckForPostToolUseOrchestrator =
  classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator;

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

  const decision = await classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator(input);

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
