#!/usr/bin/env bun
/**
 * PostToolUse hook: ty type checker
 *
 * Runs `ty check <file>` after every Write/Edit of a .py file.
 * ty is ~60x faster than mypy (4.7ms incremental) so it's hook-viable.
 *
 * If ty is not installed, shows a once-per-session install reminder.
 *
 * Fail-open everywhere — every catch exits 0.
 */

import { mkdirSync, openSync, closeSync, constants } from "fs";
import { join } from "path";

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

  // Only check .py files
  if (!filePath.endsWith(".py")) {
    process.exit(0);
  }

  // Check if ty is installed
  const tyCheck = Bun.spawnSync(["which", "ty"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (tyCheck.exitCode !== 0) {
    // ty not installed — show once-per-session install reminder
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

ty is 60x faster than mypy (4.7ms incremental) — fast enough to run on every edit.`
    );
    process.exit(0);
  }

  // Run ty check on the edited file
  const result = Bun.spawnSync(["ty", "check", filePath], {
    stdout: "pipe",
    stderr: "pipe",
    timeout: 4000, // 4s budget within 5s hook timeout
  });

  // Clean exit = no type errors
  if (result.exitCode === 0) {
    process.exit(0);
  }

  // Collect output (ty writes to stdout)
  const stdout = result.stdout?.toString().trim() || "";
  const stderr = result.stderr?.toString().trim() || "";
  const output = stdout || stderr;

  if (!output) {
    process.exit(0);
  }

  blockWithReminder(
    `[TY] Type errors in ${filePath.split("/").pop()}:

${output}`
  );
}

main().catch(() => {
  process.exit(0);
});
