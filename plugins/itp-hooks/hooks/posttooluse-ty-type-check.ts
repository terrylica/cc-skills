#!/usr/bin/env bun
/**
 * PostToolUse hook: ty type checker (iter-93 dual-mode: standalone CLI +
 * orchestrator-imported classifier; iter-94 async-Bun.spawn refactor).
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
 * This file exports `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator`
 * (the precise algorithm-encoding name) and a symmetric-naming alias
 * `classifyTyTypeCheckForPostToolUseOrchestrator`. The orchestrator
 * imports the classifier so all PostToolUse subhooks share one bun
 * cold-start instead of N. Standalone-CLI invocation is preserved via the
 * `import.meta.main` guard at the bottom.
 *
 * ─── Iter-94 performance correction (Bun.spawnSync → Bun.spawn) ──────────
 *
 * Iter-93 inherited the legacy synchronous `Bun.spawnSync` from the
 * pre-orchestrator standalone hook. That was a self-inflicted parallelism
 * defeat: per Bun's official documentation + 2026 community guidance, ANY
 * `Bun.spawnSync` invocation halts the entire JS event loop until the
 * subprocess exits, so wrapping it in `Promise.all` yields ZERO actual
 * parallelism — N subhooks each calling `Bun.spawnSync(ty)` would
 * serialize at the OS level even though the orchestrator iterates them
 * "in parallel" at the JS level.
 *
 * Iter-94 swaps to `Bun.spawn` (async): N subhooks spawned concurrently
 * via `Promise.all` truly overlap at the OS level (posix_spawn(3) lets
 * the kernel schedule them across cores), and the orchestrator's
 * wall-clock approaches the SLOWEST subhook instead of the SUM. Empirical
 * confirmation lives in the iter-94 microbenchmark task. The
 * `AbortSignal.timeout()` cooperative-cancellation primitive used by the
 * orchestrator now actually fires the subprocess kill (Bun.spawn honors
 * the `signal` option natively; spawnSync ignored it because the call
 * never yields back to the event loop where the abort would observe).
 *
 * Static audit task (iter-94)
 * `audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh`
 * prevents regression — any classifier imported by the iter-93 orchestrator
 * that uses `Bun.spawnSync(` will fail the audit (informational gate;
 * release:preflight Check 4n candidate).
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
const TY_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

// ══════════════════════════════════════════════════════════════════════════
//  Helpers — async subprocess execution with AbortSignal cooperative timeout
// ══════════════════════════════════════════════════════════════════════════

/**
 * Async drain of a Bun ReadableStream into a UTF-8 string. The orchestrator-
 * imported path must NEVER block on subprocess I/O, so we use `Response(stream).text()`
 * which is the idiomatic 2026 Bun pattern for fully consuming a process stream.
 * Mirrors the Bun docs example for `Bun.spawn` stdout reading.
 */
async function drainBunSubprocessStreamToUtf8Text(
  stream: ReadableStream<Uint8Array> | undefined,
): Promise<string> {
  if (!stream) return "";
  try {
    return await new Response(stream).text();
  } catch {
    return "";
  }
}

interface AsyncSubprocessExecutionResult {
  exitCode: number | null;
  stdoutText: string;
  stderrText: string;
  spawnFailed: boolean;
  timedOut: boolean;
}

/**
 * Spawn a subprocess asynchronously with AbortSignal-driven cooperative
 * cancellation. Returns ONE structured result object capturing the four
 * possible outcomes (clean exit, non-zero exit, spawn-failed-to-start,
 * timed-out). Never throws — every error path collapses to a flagged result.
 *
 * Why this helper exists: every PostToolUse type-checker classifier shares
 * the same spawn pattern (run external binary, capture stdout/stderr,
 * respect orchestrator timeout, fail-open on every error). Centralizing
 * it prevents drift between sibling subhook classifiers.
 */
async function executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain(
  argv: readonly string[],
  options: {
    cwd?: string;
    timeoutMs: number;
  },
): Promise<AsyncSubprocessExecutionResult> {
  const abortSignal = AbortSignal.timeout(options.timeoutMs);
  try {
    const subprocess = Bun.spawn(argv, {
      cwd: options.cwd,
      stdout: "pipe",
      stderr: "pipe",
      signal: abortSignal,
    });

    // Drain stdout + stderr CONCURRENTLY with the .exited promise so we
    // don't deadlock waiting for the process to flush.
    const [stdoutText, stderrText] = await Promise.all([
      drainBunSubprocessStreamToUtf8Text(subprocess.stdout as ReadableStream<Uint8Array> | undefined),
      drainBunSubprocessStreamToUtf8Text(subprocess.stderr as ReadableStream<Uint8Array> | undefined),
    ]);
    await subprocess.exited;

    return {
      exitCode: subprocess.exitCode,
      stdoutText: stdoutText.trim(),
      stderrText: stderrText.trim(),
      spawnFailed: false,
      timedOut: false,
    };
  } catch (raw: unknown) {
    // Two failure modes collapse here:
    //   1. Binary not in PATH — Bun.spawn throws on posix_spawn ENOENT
    //   2. AbortSignal.timeout() fired — subprocess was killed mid-execution
    const isAbortError = raw instanceof DOMException && raw.name === "AbortError";
    return {
      exitCode: null,
      stdoutText: "",
      stderrText: raw instanceof Error ? raw.message : String(raw),
      spawnFailed: !isAbortError,
      timedOut: isAbortError,
    };
  }
}

/**
 * Atomically create the ty-install-reminder gate file. Returns true if THIS
 * call won the create race (we should surface the reminder), false if the
 * reminder was already surfaced this session (silent noop).
 *
 * Race-safe because `O_CREAT | O_EXCL` is atomic at the POSIX layer — if
 * multiple PostToolUse subhooks all detect missing-binary at once
 * (e.g., ty + tsgo + oxlint + biome all uninstalled), only ONE wins the
 * gate. The losers see EEXIST and treat as "already reminded".
 */
function tryAtomicallyClaimTyInstallReminderOncePerSessionGateFile(sessionId: string): boolean {
  try {
    mkdirSync(TY_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY, { recursive: true });
  } catch {
    return false;
  }
  const gateFile = join(
    TY_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY,
    `${sessionId}-ty-install.reminded`,
  );
  try {
    const fd = openSync(gateFile, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL);
    closeSync(fd);
    return true;
  } catch {
    return false; // Lost the race or filesystem error; either way, no reminder
  }
}

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

    // Touch the gate file BEFORE running ty so the Stop hook fires its
    // project-wide check even if ty errors and we early-return.
    const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || "unknown";
    touchPythonEditGateFileForStopHookHandoffSwallowingAllFilesystemErrors(sessionId);

    // Run ty check ASYNC via Bun.spawn — does NOT block the event loop, so
    // the orchestrator's Promise.all genuinely overlaps multiple subhooks.
    const tyExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain(
        ["ty", "check", filePath, "--python-version", "3.13", "--output-format", "concise"],
        { timeoutMs: TY_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    // Spawn-failed-to-start (ENOENT — ty not in PATH) → surface install reminder
    if (tyExecutionResult.spawnFailed) {
      const sessionIdForGate = input.session_id || "unknown";
      if (!tryAtomicallyClaimTyInstallReminderOncePerSessionGateFile(sessionIdForGate)) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[TY] Python type checker not installed. Install for instant type checking after every .py edit:

  uv tool install ty

ty is 60x faster than mypy (4.7ms incremental) — fast enough to run on every edit.`,
      );
    }

    // Timeout / abort → silent noop (orchestrator already logged the timeout to stderr)
    if (tyExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Exit codes 2 (config error) and 101 (internal bug): treat as ty issue, not type error
    if (tyExecutionResult.exitCode === 2 || tyExecutionResult.exitCode === 101) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Clean exit = no type errors
    if (tyExecutionResult.exitCode === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Collect output (ty writes to stdout in concise mode)
    const tyOutputTextForOperator = tyExecutionResult.stdoutText || tyExecutionResult.stderrText;
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
 * `{decision: "block", reason}` JSON when appropriate.
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

if (import.meta.main) {
  runStandaloneCliMain().catch(() => {
    process.exit(0);
  });
}
