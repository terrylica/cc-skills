#!/usr/bin/env bun
/**
 * PostToolUse hook: ty type checker
 *
 * Runs `ty check <file>` after every Write/Edit of a .py/.pyi file.
 * ty is ~60x faster than mypy (4.7ms incremental) so it's hook-viable.
 *
 * CRITICAL: Always runs with --python-version 3.13 (project policy: Python 3.13 ONLY).
 * Uses --output-format concise for one-line diagnostics.
 *
 * If ty is not installed, shows a once-per-session install reminder.
 * Tracks .py edits via gate file for the Stop hook (stop-ty-project-check.ts).
 *
 * Fail-open everywhere -- every catch exits 0.
 */

import { mkdirSync, openSync, closeSync, constants, existsSync, writeFileSync } from "node:fs";
import { join, basename } from "node:path";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    content?: string;
    old_string?: string;
    new_string?: string;
  };
  session_id?: string;
}

// --- Constants ---

const GATE_DIR = "/tmp/.claude-ty-install-reminder";
const EDIT_GATE_DIR = "/tmp/.claude-ty-edits";
const MAX_DIAGNOSTIC_LINES = 30;

// --- Utility ---

function blockWithReminder(reason: string): void {
  console.log(JSON.stringify({ decision: "block", reason }));
}

// --- Main ---

async function main(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch {
    process.exit(0);
  }

  const filePath = input.tool_input?.file_path;
  if (!filePath) {
    process.exit(0);
  }

  // Only check .py and .pyi files
  if (!filePath.endsWith(".py") && !filePath.endsWith(".pyi")) {
    process.exit(0);
  }

  // Skip virtual environments and node_modules
  if (filePath.includes("/.venv/") || filePath.includes("/node_modules/")) {
    process.exit(0);
  }

  // Check file exists (may have been deleted between Write/Edit and hook)
  if (!existsSync(filePath)) {
    process.exit(0);
  }

  // Check if ty is installed
  const tyCheck = Bun.spawnSync(["which", "ty"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (tyCheck.exitCode !== 0) {
    // ty not installed -- show once-per-session install reminder
    const sessionId = input.session_id || "unknown";
    const gateFile = join(GATE_DIR, `${sessionId}-ty-install.reminded`);

    try {
      mkdirSync(GATE_DIR, { recursive: true });
    } catch {
      process.exit(0);
    }

    try {
      const fd = openSync(
        gateFile,
        constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL
      );
      closeSync(fd);
    } catch {
      // Already reminded this session
      process.exit(0);
    }

    blockWithReminder(
      `[TY] Python type checker not installed. Install for instant type checking after every .py edit:

  uv tool install ty

ty is 60x faster than mypy (4.7ms incremental) -- fast enough to run on every edit.`
    );
    process.exit(0);
  }

  // Run ty check on the edited file with --python-version 3.13 and concise output
  const result = Bun.spawnSync(
    ["ty", "check", filePath, "--python-version", "3.13", "--output-format", "concise"],
    {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 4000, // 4s budget within 5s hook timeout
    }
  );

  // Touch gate file to signal Stop hook that Python files were edited
  try {
    mkdirSync(EDIT_GATE_DIR, { recursive: true });
    const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || "unknown";
    writeFileSync(join(EDIT_GATE_DIR, `${sessionId}.edited`), "", { flag: "w" });
  } catch {
    // Gate file failure is non-critical -- continue
  }

  // Exit codes 2 (config error) and 101 (internal bug): treat as ty issue, not type error
  if (result.exitCode === 2 || result.exitCode === 101) {
    process.exit(0);
  }

  // Clean exit = no type errors
  if (result.exitCode === 0) {
    process.exit(0);
  }

  // Collect output (ty writes to stdout in concise mode)
  const stdout = result.stdout?.toString().trim() || "";
  const stderr = result.stderr?.toString().trim() || "";
  const output = stdout || stderr;

  if (!output) {
    process.exit(0);
  }

  // Parse concise output: count errors vs warnings
  const lines = output.split("\n").filter((l) => l.trim() !== "");
  const errorCount = lines.filter((l) => l.includes(": error:")).length;
  const warningCount = lines.filter((l) => l.includes(": warning:")).length;
  const fileName = basename(filePath);

  // Truncate output if too long
  let diagnostics: string;
  if (lines.length > MAX_DIAGNOSTIC_LINES) {
    diagnostics =
      lines.slice(0, MAX_DIAGNOSTIC_LINES).join("\n") +
      `\n... (${lines.length} total diagnostics, showing first ${MAX_DIAGNOSTIC_LINES})`;
  } else {
    diagnostics = lines.join("\n");
  }

  const summary = errorCount > 0
    ? `[TY] ${errorCount} error(s), ${warningCount} warning(s) in ${fileName}`
    : `[TY] ${warningCount} warning(s) in ${fileName}`;

  blockWithReminder(`${summary}:\n\n${diagnostics}`);
}

main().catch(() => {
  process.exit(0);
});
