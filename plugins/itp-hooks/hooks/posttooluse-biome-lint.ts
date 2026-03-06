#!/usr/bin/env bun
/**
 * PostToolUse hook: biome lint (complementary to oxlint)
 *
 * Runs `biome lint <file>` after every Write/Edit of a JS/TS file.
 * biome is ~40-80ms so it's hook-viable.
 *
 * Catches rules oxlint misses with default config:
 *   - useNodejsImportProtocol (prefer `node:fs` over `fs`)
 *   - useConst (`let` that should be `const`)
 *   - noDoubleEquals (`==` vs `===`)
 *   - noImplicitAnyLet (`let x;` without type)
 *   - noAssignInExpressions (assignment in conditions)
 *
 * Runs ALONGSIDE oxlint — not a replacement.
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

const GATE_DIR = "/tmp/.claude-biome-install-reminder";
const JS_TS_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"];

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

  // Only check JS/TS files
  if (!JS_TS_EXTENSIONS.some((ext) => filePath.endsWith(ext))) {
    process.exit(0);
  }

  // Check if biome is installed
  const biomeCheck = Bun.spawnSync(["which", "biome"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (biomeCheck.exitCode !== 0) {
    // biome not installed — show once-per-session install reminder
    const sessionId = input.session_id || "unknown";
    const gateFile = join(GATE_DIR, `${sessionId}-biome-install.reminded`);

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
      `[BIOME] Biome linter not installed. Install for complementary JS/TS lint checks (catches rules oxlint misses):

  bun add -g @biomejs/biome

Unique catches: useConst, noDoubleEquals, useNodejsImportProtocol, noImplicitAnyLet, noAssignInExpressions.`
    );
    process.exit(0);
  }

  // Run biome lint on the edited file
  // --error-on-warnings: exit 1 for warnings (useConst, noDoubleEquals, etc.)
  // --diagnostic-level=info: show info-level diagnostics too (useNodejsImportProtocol)
  // Suppress noisy rules that cause 67% trigger rate on real codebases:
  //   noExplicitAny (45 hits), useNodejsImportProtocol (24), noUnusedVariables (14),
  //   noNonNullAssertion (10), useTemplate (8), noUnusedImports (1)
  const result = Bun.spawnSync(
    [
      "biome", "lint",
      "--no-errors-on-unmatched",
      "--max-diagnostics=none",
      "--error-on-warnings",
      "--diagnostic-level=info",
      "--skip=lint/suspicious/noExplicitAny",
      "--skip=lint/style/useNodejsImportProtocol",
      "--skip=lint/correctness/noUnusedVariables",
      "--skip=lint/style/noNonNullAssertion",
      "--skip=lint/style/useTemplate",
      "--skip=lint/correctness/noUnusedImports",
      filePath,
    ],
    {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 4000, // 4s budget within 5s hook timeout
    }
  );

  // biome writes diagnostics to stderr, summary to stdout
  const stdout = result.stdout?.toString().trim() || "";
  const stderr = result.stderr?.toString().trim() || "";

  // Exit 1 = warnings/errors found (via --error-on-warnings).
  // Also check stderr for info-level diagnostics that don't trigger exit 1
  // (e.g., useNodejsImportProtocol is info-level).
  const hasFindings = result.exitCode !== 0 || /\blint\//.test(stderr);

  if (!hasFindings) {
    process.exit(0);
  }

  // Prefer stderr (has actual diagnostics), fall back to stdout (summary)
  const output = stderr || stdout;
  if (!output) {
    process.exit(0);
  }

  blockWithReminder(
    `[BIOME] Lint issues in ${filePath.split("/").pop()}:

${output}`
  );
}

main().catch(() => {
  process.exit(0);
});
