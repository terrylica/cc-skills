#!/usr/bin/env bun
/**
 * PostToolUse hook: oxlint lint checker
 *
 * Runs `oxlint -D correctness -D suspicious` after every Write/Edit of a
 * .ts/.tsx/.js/.jsx file. oxlint runs in ~40-65ms on single files so it's
 * hook-viable.
 *
 * If oxlint is not installed, shows a once-per-session install reminder.
 *
 * Fail-open everywhere — every catch exits 0.
 */

import { mkdirSync, openSync, closeSync, constants } from "node:fs";
import { join } from "node:path";

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

const GATE_DIR = "/tmp/.claude-oxlint-install-reminder";

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

  // Only check JS/TS files (including ES module and CommonJS variants)
  if (
    !filePath.endsWith(".ts") &&
    !filePath.endsWith(".tsx") &&
    !filePath.endsWith(".js") &&
    !filePath.endsWith(".jsx") &&
    !filePath.endsWith(".mjs") &&
    !filePath.endsWith(".cjs") &&
    !filePath.endsWith(".mts") &&
    !filePath.endsWith(".cts")
  ) {
    process.exit(0);
  }

  // Check if oxlint is installed
  const oxlintCheck = Bun.spawnSync(["which", "oxlint"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (oxlintCheck.exitCode !== 0) {
    // oxlint not installed — show once-per-session install reminder
    const sessionId = input.session_id || "unknown";
    const gateFile = join(GATE_DIR, `${sessionId}-oxlint-install.reminded`);

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
      `[OXLINT] JavaScript/TypeScript linter not installed. Install for instant correctness checking after every edit:

  bun add -g oxlint

oxlint runs in ~40-65ms — fast enough to run on every edit. Catches real bugs: const reassignment, duplicate keys, debugger statements, and more.`
    );
    process.exit(0);
  }

  // Run oxlint on the edited file
  const result = Bun.spawnSync(
    [
      "oxlint",
      "-D", "correctness",
      "-D", "suspicious",
      "-A", "no-unused-vars",
      "-A", "no-empty-file",
      "-f", "unix",
      filePath,
    ],
    {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 4000, // 4s budget within 5s hook timeout
    }
  );

  // Clean exit = no lint issues
  if (result.exitCode === 0) {
    process.exit(0);
  }

  // Collect output (oxlint writes to stdout in unix format)
  const stdout = result.stdout?.toString().trim() || "";
  const stderr = result.stderr?.toString().trim() || "";
  const output = stdout || stderr;

  if (!output) {
    process.exit(0);
  }

  // Strip the summary line (e.g., "3 problems" or "Found 2 diagnostics")
  const lines = output.split("\n").filter(
    (line) =>
      !line.match(/^Found \d+ diagnostic/) &&
      !line.match(/^\d+ problem/)
  );
  const filteredOutput = lines.join("\n").trim();

  if (!filteredOutput) {
    process.exit(0);
  }

  blockWithReminder(
    `[OXLINT] Lint issues in ${filePath.split("/").pop()}:

${filteredOutput}`
  );
}

main().catch(() => {
  process.exit(0);
});
