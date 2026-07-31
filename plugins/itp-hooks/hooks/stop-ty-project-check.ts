#!/usr/bin/env bun
/**
 * Stop hook: ty project-wide type check with subprocess resource guards
 *
 * Runs `ty check .` on session exit to catch cross-file type errors
 * that per-file PostToolUse checks miss.
 *
 * Only runs when:
 * 1. Python files were edited this session (gate files in /tmp/.claude-ty-edits/)
 * 2. ty is installed
 * 3. CWD is a Python project (pyproject.toml or *.py files present)
 *
 * ─── Incident 2026-07-31 ─────────────────────────────────────────────────────
 *
 * The previous sync implementation had NO resource guard. This Stop hook runs on
 * session exit, so multiple concurrent sessions exiting could trigger several
 * whole-tree `ty check .` runs simultaneously — exactly the pattern that caused
 * 2026-07-30 to freeze the machine (four concurrent runs, 73 GB combined, kernel
 * jetsam named ty as largestProcess). Incident this machine: one unguarded Stop-hook
 * run reached 14.4 GB and was killed by the kernel at 17 minutes. The fix: use the
 * async spawn path with full resource guards — machine-wide concurrency slots,
 * RSS watchdog, and kernel-enforced CPU ceiling — reusing the infrastructure from
 * the iter-95 shared helper and iter-124 watchdog.
 *
 * This now mirrors the per-file PostToolUse check (which IS guarded) rather than
 * being a separate unguarded path. Duration is wrong axis; memory and concurrency
 * are the layers that matter.
 *
 * CRITICAL: Always runs with --python-version 3.14 (project policy: Python 3.14 ONLY).
 * Uses --exit-zero to prevent non-zero exit codes from failing the hook.
 *
 * Output: { additionalContext: "..." } for informational, non-blocking output.
 * Fail-open everywhere -- outputs {} on any error, never blocks session end.
 */

import { existsSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95";

// --- Constants ---

const EDIT_GATE_DIR = "/tmp/.claude-ty-edits";
const MAX_DIAGNOSTIC_LINES = 20;
const TY_SUBPROCESS_TIMEOUT_MILLISECONDS = 15000; // 15s budget for project-wide check

// --- Main ---

async function main(): Promise<void> {
  // Check gate: were any Python files edited this session?
  let hasEdits = false;
  try {
    if (existsSync(EDIT_GATE_DIR)) {
      const files = readdirSync(EDIT_GATE_DIR);
      hasEdits = files.some((f) => f.endsWith(".edited"));
    }
  } catch {
    // Gate dir read failed -- skip
    console.log(JSON.stringify({}));
    return;
  }

  if (!hasEdits) {
    console.log(JSON.stringify({}));
    return;
  }

  // Check if this is a Python project
  const cwd = process.cwd();
  let isPythonProject = false;
  try {
    if (existsSync(join(cwd, "pyproject.toml"))) {
      isPythonProject = true;
    } else {
      const entries = readdirSync(cwd);
      isPythonProject = entries.some((f) => f.endsWith(".py"));
    }
  } catch {
    // Can't read CWD -- skip
    console.log(JSON.stringify({}));
    return;
  }

  if (!isPythonProject) {
    cleanup();
    console.log(JSON.stringify({}));
    return;
  }

  // Check if ty is installed
  const tyCheck = Bun.spawnSync(["which", "ty"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (tyCheck.exitCode !== 0) {
    // ty not installed -- skip silently (no install reminder from Stop hooks)
    cleanup();
    console.log(JSON.stringify({}));
    return;
  }

  // Run ty check on the entire project via the guarded async spawn path
  const tyExecutionResult =
    await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
      ["ty", "check", ".", "--output-format", "concise", "--python-version", "3.14", "--exit-zero"],
      {
        cwd,
        timeoutMs: TY_SUBPROCESS_TIMEOUT_MILLISECONDS,
        // Incident 2026-07-31: one unguarded Stop-hook run reached 14.4 GB and was killed by
        // the kernel at 17 minutes old. Multiple concurrent sessions exiting would spawn
        // several whole-tree checks simultaneously — the exact pattern that caused 2026-07-30
        // to freeze the machine (73 GB across 4 concurrent runs). This guard bounds memory and
        // concurrency via the same mechanism the per-file PostToolUse check uses, reusing the
        // iter-95 shared helper and iter-124 watchdog.
        residentMemoryGuardedToolName: "ty",
      },
    );

  // Always cleanup gate files after running
  cleanup();

  // Handle resource-guard outcomes
  if (tyExecutionResult.skippedBecauseConcurrencySlotsBusy) {
    // Every slot busy; a concurrent session's check is already running. This is safe — we
    // skip rather than queue, and a type check is advisory.
    console.log(JSON.stringify({}));
    return;
  }

  if (tyExecutionResult.killedForExceedingMemoryCeiling) {
    // The watchdog SIGKILLed this for exceeding the 1500 MB ceiling. This is not a normal
    // failure to swallow; silence is how 2026-07-30 recurred after its own reboot.
    const peakMB = tyExecutionResult.observedPeakResidentMegabytes ?? 0;
    const summary = `[TY] Project type check MEMORY LIMIT exceeded (peak ${peakMB} MB). ` +
      `Upgrade ty or report to https://github.com/astral-sh/ty/issues/4147`;
    console.log(JSON.stringify({ additionalContext: summary }));
    return;
  }

  if (tyExecutionResult.timedOut) {
    // The subprocess was aborted after 15 s. This is less severe than a memory kill but
    // still worth reporting to the operator.
    console.log(JSON.stringify({ additionalContext: "[TY] Project type check timed out (15s)" }));
    return;
  }

  // Collect output
  const output = tyExecutionResult.stdoutText || tyExecutionResult.stderrText;

  if (!output) {
    // Clean project -- no diagnostics
    console.log(JSON.stringify({}));
    return;
  }

  // Parse concise output
  const lines = output.split("\n").filter((l) => l.trim() !== "");

  if (lines.length === 0) {
    console.log(JSON.stringify({}));
    return;
  }

  const errorCount = lines.filter((l) => l.includes(": error:")).length;
  const warningCount = lines.filter((l) => l.includes(": warning:")).length;

  if (errorCount === 0 && warningCount === 0) {
    // Output exists but no recognizable diagnostics -- skip
    console.log(JSON.stringify({}));
    return;
  }

  // Count unique files from concise format (file:line:col: ...)
  const uniqueFiles = new Set<string>();
  for (const line of lines) {
    const match = line.match(/^([^:]+):\d+:\d+:/);
    if (match) {
      uniqueFiles.add(match[1]);
    }
  }
  const fileCount = uniqueFiles.size;

  // Truncate if needed
  let diagnostics: string;
  if (lines.length > MAX_DIAGNOSTIC_LINES) {
    diagnostics =
      lines.slice(0, MAX_DIAGNOSTIC_LINES).join("\n") +
      `\n... (${lines.length} total, showing first ${MAX_DIAGNOSTIC_LINES})`;
  } else {
    diagnostics = lines.join("\n");
  }

  const summary = `[TY] Project type check: ${errorCount} error(s), ${warningCount} warning(s) across ${fileCount} file(s)\n\n${diagnostics}`;

  console.log(JSON.stringify({ additionalContext: summary }));
}

function cleanup(): void {
  try {
    rmSync(EDIT_GATE_DIR, { recursive: true, force: true });
  } catch {
    // Cleanup failure is non-critical
  }
}

try {
  // Async main
  await main();
} catch {
  // Fail-open -- Stop hook must never block session end
  console.log(JSON.stringify({}));
}
