#!/usr/bin/env bun
/**
 * PostToolUse hook: tsgo type checker
 *
 * Runs `tsgo --noEmit` after every Write/Edit of a .ts/.tsx file.
 * tsgo is the native Go TypeScript compiler (~170ms full project check),
 * making it viable as a PostToolUse hook where tsc would not be.
 *
 * Runs in project mode from the nearest tsconfig.json directory.
 * Filters output to only show errors in the edited file.
 *
 * If tsgo is not installed, shows a once-per-session install reminder.
 *
 * Fail-open everywhere — every catch exits 0.
 */

import { mkdirSync, openSync, closeSync, constants, existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";

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

const GATE_DIR = "/tmp/.claude-tsgo-install-reminder";

// --- Utility ---

function blockWithReminder(reason: string): void {
  console.log(JSON.stringify({ decision: "block", reason }));
}

/**
 * Walk up from startDir to find the nearest directory containing tsconfig.json.
 * Returns the directory path, or null if not found.
 */
function findTsconfigDir(startDir: string): string | null {
  let dir = startDir;
  const root = "/";
  while (true) {
    if (existsSync(join(dir, "tsconfig.json"))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir || parent === root) {
      // Check root too
      if (existsSync(join(root, "tsconfig.json"))) {
        return root;
      }
      return null;
    }
    dir = parent;
  }
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

  // Only check .ts and .tsx files
  if (!filePath.endsWith(".ts") && !filePath.endsWith(".tsx")) {
    process.exit(0);
  }

  // Check if tsgo is installed
  const tsgoCheck = Bun.spawnSync(["which", "tsgo"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (tsgoCheck.exitCode !== 0) {
    // tsgo not installed — show once-per-session install reminder
    const sessionId = input.session_id || "unknown";
    const gateFile = join(GATE_DIR, `${sessionId}-tsgo-install.reminded`);

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
      `[TSGO] TypeScript native compiler not installed. Install for instant type checking after every .ts/.tsx edit:

  npm install -g @typescript/native-preview

tsgo is ~30x faster than tsc (~170ms full project check) — fast enough to run on every edit.`
    );
    process.exit(0);
  }

  // Find nearest tsconfig.json directory
  const fileDir = dirname(filePath);
  const tsconfigDir = findTsconfigDir(fileDir);

  if (!tsconfigDir) {
    // No tsconfig.json found — skip silently
    process.exit(0);
  }

  // Run tsgo --noEmit from the tsconfig.json directory
  const result = Bun.spawnSync(["tsgo", "--noEmit"], {
    cwd: tsconfigDir,
    stdout: "pipe",
    stderr: "pipe",
    timeout: 4000, // 4s budget within 5s hook timeout
  });

  // Clean exit = no type errors
  if (result.exitCode === 0) {
    process.exit(0);
  }

  // Collect output (tsgo writes errors to stdout)
  const stdout = result.stdout?.toString().trim() || "";
  const stderr = result.stderr?.toString().trim() || "";
  const allOutput = stdout || stderr;

  if (!allOutput) {
    process.exit(0);
  }

  // Filter output to only show errors related to the edited file.
  // tsgo checks ALL files in tsconfig scope — don't blame user for
  // pre-existing errors in other files.
  // Use relative path from tsconfigDir to avoid basename collisions
  // (e.g., two files named index.ts in different directories).
  const relativePath = filePath.startsWith(`${tsconfigDir}/`)
    ? filePath.slice(tsconfigDir.length + 1)
    : basename(filePath);
  const filteredLines = allOutput
    .split("\n")
    .filter((line) => {
      // Match error lines that reference the edited file
      // Format: relative/path/file(line,col): error TSXXXX: message
      return line.startsWith(relativePath) || line.includes(filePath);
    });

  if (filteredLines.length === 0) {
    // Errors exist but not in the edited file — don't block
    process.exit(0);
  }

  blockWithReminder(
    `[TSGO] Type errors in ${basename(filePath)}:

${filteredLines.join("\n")}`
  );
}

main().catch(() => {
  process.exit(0);
});
