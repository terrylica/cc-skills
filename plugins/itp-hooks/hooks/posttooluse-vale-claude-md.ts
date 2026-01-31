#!/usr/bin/env bun
/**
 * PostToolUse hook: Vale terminology check on CLAUDE.md files
 * Non-blocking (visibility only) - Claude sees violations and can act.
 *
 * Pattern: Follows lifecycle-reference.md TypeScript template.
 * Trigger: After Edit or Write on any CLAUDE.md file.
 * Output: { decision: "block", reason: "..." } for Claude visibility.
 *
 * ADR: hooks-development/references/lifecycle-reference.md (lines 503-526)
 */

import { existsSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { $ } from "bun";

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
  tool_response?: unknown;
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

// ============================================================================
// HELPERS
// ============================================================================

/**
 * Parse stdin JSON for PostToolUse.
 */
async function parseStdin(): Promise<PostToolUseInput | null> {
  try {
    const stdin = await Bun.stdin.text();
    if (!stdin.trim()) return null;
    return JSON.parse(stdin) as PostToolUseInput;
  } catch {
    return null;
  }
}

/**
 * Output for Claude visibility.
 * PostToolUse requires `decision: "block"` for Claude to see the reason.
 */
function createVisibilityOutput(reason: string): string {
  return JSON.stringify({
    decision: "block",
    reason: reason,
  });
}

/**
 * Find Vale config file by walking up from file's directory, then fallback to global.
 * This makes the hook work regardless of cwd.
 */
function findValeConfig(filePath: string): string | null {
  const globalConfig = join(process.env.HOME || "", ".claude", ".vale.ini");

  // Walk up from file's directory looking for .vale.ini
  let dir = dirname(filePath);
  const root = "/";
  while (dir !== root) {
    const candidate = join(dir, ".vale.ini");
    if (existsSync(candidate)) {
      return candidate;
    }
    const parent = dirname(dir);
    if (parent === dir) break; // Reached filesystem root
    dir = parent;
  }

  // Fallback to global config
  if (existsSync(globalConfig)) return globalConfig;
  return null;
}

/**
 * Check if Vale is installed.
 */
async function isValeInstalled(): Promise<boolean> {
  try {
    await $`which vale`.quiet();
    return true;
  } catch {
    return false;
  }
}

/**
 * Run Vale and return output with parsed counts.
 * Must run Vale from the file's directory for glob patterns to match.
 */
async function runVale(
  filePath: string,
  configPath: string,
): Promise<{ output: string; exitCode: number; errors: number; warnings: number; suggestions: number }> {
  try {
    // Vale glob patterns in .vale.ini are relative to cwd
    // We must cd to the file's directory for patterns like [CLAUDE.md] to match
    const fileDir = dirname(filePath);
    const fileName = basename(filePath);

    const result = await $`cd ${fileDir} && vale --config ${configPath} ${fileName}`
      .quiet()
      .nothrow();
    const output = result.stdout.toString() + result.stderr.toString();

    // Parse counts from Vale's summary line: "✖ 0 errors, 6 warnings and 0 suggestions in 1 file."
    // Note: Vale output contains ANSI escape codes for colors, e.g., "\x1b[31m0 errors\x1b[0m"
    // Strip ANSI codes before parsing to ensure reliable matching
    const cleanOutput = output.replace(/\x1b\[[0-9;]*m/g, "");
    const summaryMatch = cleanOutput.match(/(\d+)\s+errors?,\s+(\d+)\s+warnings?\s+and\s+(\d+)\s+suggestions?/i);

    return {
      output,
      exitCode: result.exitCode,
      errors: summaryMatch ? parseInt(summaryMatch[1], 10) : 0,
      warnings: summaryMatch ? parseInt(summaryMatch[2], 10) : 0,
      suggestions: summaryMatch ? parseInt(summaryMatch[3], 10) : 0,
    };
  } catch {
    return { output: "", exitCode: 0, errors: 0, warnings: 0, suggestions: 0 };
  }
}

// ============================================================================
// MAIN LOGIC - Pure function returning result
// ============================================================================

async function runHook(): Promise<HookResult> {
  const input = await parseStdin();
  if (!input) {
    return { exitCode: 0 }; // No input, allow through
  }

  const toolName = input.tool_name || "";
  const filePath = input.tool_input?.file_path || "";

  // Only check Write and Edit tools
  if (toolName !== "Write" && toolName !== "Edit") {
    return { exitCode: 0 };
  }

  // Only check CLAUDE.md files
  if (!filePath.endsWith("CLAUDE.md")) {
    return { exitCode: 0 };
  }

  // Check if file exists
  if (!existsSync(filePath)) {
    return { exitCode: 0 };
  }

  // Check if Vale is installed
  if (!(await isValeInstalled())) {
    return { exitCode: 0 };
  }

  // Find Vale config (walks up from file's directory)
  const configPath = findValeConfig(filePath);
  if (!configPath) {
    return { exitCode: 0 };
  }

  // Run Vale
  const { output, errors, warnings, suggestions } = await runVale(filePath, configPath);

  // If Vale found any issues
  if (errors > 0 || warnings > 0 || suggestions > 0) {
    // Strip ANSI codes from output for cleaner display
    const cleanOutput = output.replace(/\x1b\[[0-9;]*m/g, "");
    const reason = `[VALE] Found ${errors} errors, ${warnings} warnings, ${suggestions} suggestions in ${basename(filePath)}:

${cleanOutput.trim()}

**Options:**
1. Fix terminology automatically (use acronyms: ITH, TMAEG, MCOT, NAV, CV, dbps)
2. Keep expanded form if this is a definition (Terminology table)
3. Ask user which terms to expand/contract`;

    return {
      exitCode: 0,
      stdout: createVisibilityOutput(reason),
    };
  }

  return { exitCode: 0 };
}

// ============================================================================
// ENTRY POINT - Single location for process.exit
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;

  try {
    result = await runHook();
  } catch (err: unknown) {
    // Unexpected error - log and allow through to avoid blocking on bugs
    console.error("[vale-claude-md] Unexpected error:");
    if (err instanceof Error) {
      console.error(`  Message: ${err.message}`);
      console.error(`  Stack: ${err.stack}`);
    }
    console.error("[vale-claude-md] Tip: Ensure Vale is installed (brew install vale) and ~/.claude/.vale.ini exists.");
    return process.exit(0);
  }

  if (result.stderr) console.error(result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
