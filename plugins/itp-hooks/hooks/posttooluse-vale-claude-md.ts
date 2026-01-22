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
import { basename, join } from "node:path";
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
 * Find Vale config file (project > global).
 */
function findValeConfig(): string | null {
  const projectConfig = join(process.cwd(), ".vale.ini");
  const globalConfig = join(process.env.HOME || "", ".claude", ".vale.ini");

  if (existsSync(projectConfig)) return projectConfig;
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
 * Run Vale and return output.
 */
async function runVale(
  filePath: string,
  configPath: string,
): Promise<{ output: string; exitCode: number }> {
  try {
    const result = await $`vale --config ${configPath} ${filePath}`
      .quiet()
      .nothrow();
    return {
      output: result.stdout.toString() + result.stderr.toString(),
      exitCode: result.exitCode,
    };
  } catch {
    return { output: "", exitCode: 0 };
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

  // Find Vale config
  const configPath = findValeConfig();
  if (!configPath) {
    return { exitCode: 0 };
  }

  // Run Vale
  const { output } = await runVale(filePath, configPath);

  // If Vale found issues (check output, not exit code - Vale returns 0 for warnings)
  if (output.trim() && (output.includes("warning") || output.includes("error") || output.includes("suggestion"))) {
    // Count violations
    const warnings = (output.match(/warning/gi) || []).length;
    const suggestions = (output.match(/suggestion/gi) || []).length;
    const errors = (output.match(/error/gi) || []).length;

    const reason = `[VALE] Found ${errors} errors, ${warnings} warnings, ${suggestions} suggestions in ${basename(filePath)}:

${output.trim()}

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
    return process.exit(0);
  }

  if (result.stderr) console.error(result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
