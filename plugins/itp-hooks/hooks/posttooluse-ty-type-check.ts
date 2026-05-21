#!/usr/bin/env bun
/**
 * PostToolUse hook: ty type checker (iter-93 dual-mode: standalone CLI +
 * orchestrator-imported classifier).
 *
 * Runs `ty check <file>` after every Write/Edit of a .py/.pyi file.
 * ty is ~60x faster than mypy (4.7ms incremental) so it's hook-viable.
 *
 * CRITICAL: Always runs with --python-version 3.13 (project policy: Python
 * 3.13 ONLY). Uses --output-format concise for one-line diagnostics.
 *
 * If ty is not installed, surfaces a once-per-session install reminder.
 * Tracks .py edits via gate file for the Stop hook (stop-ty-project-check.ts).
 *
 * Fail-open everywhere — every catch returns a `noop` (orchestrator path)
 * or exits 0 (standalone path).
 *
 * ─── Iter-93 architectural change ─────────────────────────────────────────
 *
 * This file now exports `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator`
 * (the precise algorithm-encoding name) and a symmetric-naming alias
 * `classifyTyTypeCheckForPostToolUseOrchestrator`. The orchestrator
 * (`posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts`)
 * imports the classifier so all PostToolUse subhooks share one bun
 * cold-start instead of N. Standalone-CLI invocation is preserved via the
 * `import.meta.main` guard at the bottom — direct `bun posttooluse-ty-type-check.ts`
 * still works for testing or operators running the hook by hand.
 *
 * Iter-93 motivation: iter-92 audit ruled out `async: true` for
 * context-injecting hooks (15 of 17 marketplace PostToolUse hooks) because
 * async hooks cannot reliably inject `additionalContext` next-to-tool-result.
 * The orchestrator inlining strategy (Path B) is the only viable
 * consolidation for this cohort.
 */

import { mkdirSync, openSync, closeSync, constants, existsSync, writeFileSync } from "node:fs";
import { join, basename } from "node:path";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// --- Constants ---

const TY_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY = "/tmp/.claude-ty-install-reminder";
const PYTHON_EDIT_GATE_DIRECTORY_FOR_STOP_HOOK_HANDOFF = "/tmp/.claude-ty-edits";
const MAX_TYPE_CHECK_DIAGNOSTIC_LINES_BEFORE_TRUNCATION = 30;

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Pure classifier function (no stdin/stdout/process.exit). Returns a
 * PostToolUseSubhookDecision the orchestrator aggregates into one
 * consolidated reason.
 *
 * Precise algorithm-encoding name. Aliased as
 * `classifyTyTypeCheckForPostToolUseOrchestrator` for symmetric naming
 * with sibling subhooks (consistent with iter-89/90/91 dual-export pattern).
 */
export async function classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Only check .py and .pyi files (cheap O(1) extension filter — lightest-first)
    if (!filePath.endsWith(".py") && !filePath.endsWith(".pyi")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Skip virtual environments and node_modules
    if (filePath.includes("/.venv/") || filePath.includes("/node_modules/")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Check file exists (may have been deleted between Write/Edit and hook)
    if (!existsSync(filePath)) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Check if ty is installed
    const tyResolvedPathCheck = Bun.spawnSync(["which", "ty"], {
      stdout: "pipe",
      stderr: "pipe",
    });

    if (tyResolvedPathCheck.exitCode !== 0) {
      // ty not installed — surface a once-per-session install reminder
      const sessionId = input.session_id || "unknown";
      const gateFile = join(
        TY_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY,
        `${sessionId}-ty-install.reminded`,
      );

      try {
        mkdirSync(TY_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY, { recursive: true });
      } catch {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }

      try {
        const fd = openSync(gateFile, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL);
        closeSync(fd);
      } catch {
        // Already reminded this session
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }

      return buildPostToolUseAdditionalContextDecision(
        `[TY] Python type checker not installed. Install for instant type checking after every .py edit:

  uv tool install ty

ty is 60x faster than mypy (4.7ms incremental) — fast enough to run on every edit.`,
      );
    }

    // Run ty check on the edited file with --python-version 3.13 and concise output
    const tyCheckSubprocessResult = Bun.spawnSync(
      ["ty", "check", filePath, "--python-version", "3.13", "--output-format", "concise"],
      {
        stdout: "pipe",
        stderr: "pipe",
        timeout: 4000, // 4s budget within 5s hook timeout
      },
    );

    // Touch gate file to signal Stop hook that Python files were edited
    try {
      mkdirSync(PYTHON_EDIT_GATE_DIRECTORY_FOR_STOP_HOOK_HANDOFF, { recursive: true });
      const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || "unknown";
      writeFileSync(
        join(PYTHON_EDIT_GATE_DIRECTORY_FOR_STOP_HOOK_HANDOFF, `${sessionId}.edited`),
        "",
        { flag: "w" },
      );
    } catch {
      // Gate file failure is non-critical — continue
    }

    // Exit codes 2 (config error) and 101 (internal bug): treat as ty issue, not type error
    if (tyCheckSubprocessResult.exitCode === 2 || tyCheckSubprocessResult.exitCode === 101) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Clean exit = no type errors
    if (tyCheckSubprocessResult.exitCode === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Collect output (ty writes to stdout in concise mode)
    const tyStdoutText = tyCheckSubprocessResult.stdout?.toString().trim() || "";
    const tyStderrText = tyCheckSubprocessResult.stderr?.toString().trim() || "";
    const tyOutputTextForOperator = tyStdoutText || tyStderrText;

    if (!tyOutputTextForOperator) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Parse concise output: count errors vs warnings
    const diagnosticLines = tyOutputTextForOperator.split("\n").filter((l) => l.trim() !== "");
    const tyErrorDiagnosticCount = diagnosticLines.filter((l) => l.includes(": error:")).length;
    const tyWarningDiagnosticCount = diagnosticLines.filter((l) => l.includes(": warning:")).length;
    const editedFileBaseName = basename(filePath);

    // Truncate output if too long
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
    // Fail-open: any unexpected error → noop (do not break the orchestrator)
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

/**
 * Symmetric-naming alias for sibling-subhook consistency. The orchestrator
 * registry imports under this name; the underlying algorithm is encoded in
 * the precise function name above.
 */
export const classifyTyTypeCheckForPostToolUseOrchestrator =
  classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator;

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point (preserved for backward-compat + direct invocation)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Standalone entry — reads stdin, calls the classifier, emits the legacy
 * `{decision: "block", reason}` JSON when appropriate. Preserved so direct
 * `bun posttooluse-ty-type-check.ts` invocation still works (for testing or
 * operators running the hook by hand).
 */
async function runStandaloneCliMain(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

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

// `import.meta.main` is true ONLY when this file is run directly via bun.
// When the orchestrator imports this module, `import.meta.main` is false,
// so the standalone CLI never executes during orchestrator inlining.
if (import.meta.main) {
  runStandaloneCliMain().catch(() => {
    process.exit(0);
  });
}
