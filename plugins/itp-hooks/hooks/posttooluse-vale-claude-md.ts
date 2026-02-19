#!/usr/bin/env bun
/**
 * PostToolUse hook: Vale terminology check on CLAUDE.md files
 * Non-blocking (visibility only) - Claude sees violations and can act.
 *
 * Pattern: Follows lifecycle-reference.md TypeScript template.
 * Trigger: After Edit or Write on any CLAUDE.md file.
 * Output: { decision: "block", reason: "..." } for Claude visibility.
 *
 * Scoping: For Edit tool, only reports issues on lines that were actually
 * changed (± 3 line buffer). This prevents flagging pre-existing issues
 * elsewhere in the file. Write tool checks the entire file.
 *
 * ADR: hooks-development/references/lifecycle-reference.md (lines 503-526)
 */

import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { $ } from "bun";
import { trackHookError } from "./lib/hook-error-tracker.ts";

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    old_string?: string;
    new_string?: string;
    replace_all?: boolean;
    [key: string]: unknown;
  };
  tool_response?: unknown;
}

interface LineRange {
  start: number;
  end: number;
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
  } catch (err) {
    trackHookError("posttooluse-vale-claude-md", err instanceof Error ? err.message : String(err));
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
 * Compute the line range affected by an Edit operation.
 * Returns null for Write (entire file is new) or if range can't be determined.
 * Uses ±3 line buffer to catch context-dependent issues.
 */
function computeEditLineRange(filePath: string, newString: string): LineRange | null {
  const BUFFER = 3;

  if (!newString || !existsSync(filePath)) return null;

  try {
    const content = readFileSync(filePath, "utf8");
    const lines = content.split("\n");

    // Find the first non-empty line of new_string in the file
    const firstLine = newString.split("\n").find((l) => l.trim().length > 0);
    if (!firstLine) return null;

    // Find the line number (1-based)
    let matchCount = 0;
    let matchLineNum = -1;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes(firstLine.trim())) {
        matchCount++;
        matchLineNum = i + 1; // 1-based
      }
    }

    // Only scope if we can uniquely identify the location
    if (matchCount !== 1 || matchLineNum < 1) return null;

    const newLineCount = newString.split("\n").length;
    const start = Math.max(1, matchLineNum - BUFFER);
    const end = matchLineNum + newLineCount - 1 + BUFFER;

    return { start, end };
  } catch {
    return null;
  }
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

interface ValeIssue {
  line: number;
  severity: "error" | "warning" | "suggestion";
  message: string;
  rule: string;
}

/**
 * Run Vale and return structured issues with line numbers.
 * Must run Vale from the file's directory for glob patterns to match.
 */
async function runVale(
  filePath: string,
  configPath: string,
): Promise<ValeIssue[]> {
  try {
    const fileDir = dirname(filePath);
    const fileName = basename(filePath);

    const result = await $`cd ${fileDir} && vale --config ${configPath} --output=JSON ${fileName}`
      .quiet()
      .nothrow();

    const stdout = result.stdout.toString().trim();
    const issues: ValeIssue[] = [];

    if (stdout) {
      try {
        const valeOutput = JSON.parse(stdout);
        for (const [_file, fileIssues] of Object.entries(valeOutput)) {
          if (Array.isArray(fileIssues)) {
            for (const issue of fileIssues) {
              const i = issue as { Line?: number; Severity?: string; Message?: string; Check?: string };
              issues.push({
                line: i.Line || 0,
                severity: (i.Severity?.toLowerCase() || "warning") as ValeIssue["severity"],
                message: i.Message || "Unknown issue",
                rule: i.Check || "",
              });
            }
          }
        }
      } catch {
        // JSON parse failed
      }
    }

    return issues;
  } catch (err) {
    trackHookError("posttooluse-vale-claude-md", err instanceof Error ? err.message : String(err));
    return [];
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

  // For Edit tool: compute changed line range to scope output
  // Write tool checks the entire file (all content is new)
  let lineRange: LineRange | null = null;
  if (toolName === "Edit" && !input.tool_input?.replace_all) {
    const newString = input.tool_input?.new_string || "";
    lineRange = computeEditLineRange(filePath, newString);
  }

  // Run Vale
  const issues = await runVale(filePath, configPath);

  // Filter issues to changed lines only (for Edit tool)
  const scopedIssues = lineRange
    ? issues.filter((i) => i.line >= lineRange!.start && i.line <= lineRange!.end)
    : issues;

  // Count by severity
  const errors = scopedIssues.filter((i) => i.severity === "error").length;
  const warnings = scopedIssues.filter((i) => i.severity === "warning").length;
  const suggestions = scopedIssues.filter((i) => i.severity === "suggestion").length;

  // If Vale found issues on changed lines
  if (errors > 0 || warnings > 0 || suggestions > 0) {
    const issueLines = scopedIssues
      .map((i) => `  Line ${i.line}: [${i.severity.toUpperCase()}] ${i.message} (${i.rule})`)
      .join("\n");

    const scopeNote = lineRange
      ? ` (scoped to changed lines ${lineRange.start}-${lineRange.end})`
      : "";

    const reason = `[VALE] Found ${errors} errors, ${warnings} warnings, ${suggestions} suggestions in ${basename(filePath)}${scopeNote}:

${issueLines}

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
    trackHookError("posttooluse-vale-claude-md", err instanceof Error ? err.message : String(err));
    return process.exit(0);
  }

  if (result.stderr) trackHookError("posttooluse-vale-claude-md", result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
