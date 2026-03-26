#!/usr/bin/env bun
/**
 * Stop hook: ty project-wide type check
 *
 * Runs `ty check .` on session exit to catch cross-file type errors
 * that per-file PostToolUse checks miss.
 *
 * Only runs when:
 * 1. Python files were edited this session (gate files in /tmp/.claude-ty-edits/)
 * 2. ty is installed
 * 3. CWD is a Python project (pyproject.toml or *.py files present)
 *
 * CRITICAL: Always runs with --python-version 3.13 (project policy: Python 3.13 ONLY).
 * Uses --exit-zero to prevent non-zero exit codes from failing the hook.
 *
 * Output: { additionalContext: "..." } for informational, non-blocking output.
 * Fail-open everywhere -- outputs {} on any error.
 */

import { existsSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";

// --- Constants ---

const EDIT_GATE_DIR = "/tmp/.claude-ty-edits";
const MAX_DIAGNOSTIC_LINES = 20;

// --- Main ---

function main(): void {
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

  // Run ty check on the entire project
  const result = Bun.spawnSync(
    ["ty", "check", ".", "--output-format", "concise", "--python-version", "3.13", "--exit-zero"],
    {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 15000, // 15s budget for project-wide check
    }
  );

  // Always cleanup gate files after running
  cleanup();

  // Collect output
  const stdout = result.stdout?.toString().trim() || "";
  const stderr = result.stderr?.toString().trim() || "";
  const output = stdout || stderr;

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
  main();
} catch {
  // Fail-open -- Stop hook must never block session end
  console.log(JSON.stringify({}));
}
