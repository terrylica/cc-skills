#!/usr/bin/env bun
/**
 * PostToolUse hook: Detect absolute GitHub URLs in root-level README.md
 * Non-blocking (visibility only) - Claude sees the reminder and can fix.
 *
 * Pattern: Follows lifecycle-reference.md TypeScript template.
 * Trigger: After Write/Edit/MultiEdit on root-level README.md.
 * Output: { decision: "block", reason: "..." } for Claude visibility.
 *
 * Context: Root-level README.md should use relative links for maintainability.
 * The transform_readme.py script converts them to absolute at publish time.
 * This hook prevents Claude from accidentally introducing absolute URLs.
 */

import { basename, dirname, resolve } from "node:path";
import { trackHookError } from "./lib/hook-error-tracker.ts";

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    content?: string; // Write tool
    new_string?: string; // Edit tool
    [key: string]: unknown;
  };
  cwd?: string;
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

// ============================================================================
// HELPERS
// ============================================================================

async function parseStdin(): Promise<PostToolUseInput | null> {
  try {
    const stdin = await Bun.stdin.text();
    if (!stdin.trim()) return null;
    return JSON.parse(stdin) as PostToolUseInput;
  } catch (err) {
    trackHookError("posttooluse-readme-pypi-links", err instanceof Error ? err.message : String(err));
    return null;
  }
}

function createVisibilityOutput(reason: string): string {
  return JSON.stringify({
    decision: "block",
    reason: reason,
  });
}

/**
 * Check if a file path is a root-level README.md.
 * Root-level means the README is in the repository root (cwd), not a subdirectory.
 */
function isRootReadme(filePath: string, cwd: string): boolean {
  if (basename(filePath) !== "README.md") return false;
  const fileDir = resolve(dirname(filePath));
  const repoRoot = resolve(cwd);
  return fileDir === repoRoot;
}

/**
 * Find absolute GitHub URLs in content that point to the same repo.
 * Returns matching URLs found.
 */
function findAbsoluteGitHubLinks(content: string): string[] {
  // Match markdown links with absolute GitHub URLs
  // Captures: ](https://github.com/owner/repo/blob/... or /tree/...)
  const pattern = /\]\(https:\/\/github\.com\/[^)]+\/(blob|tree)\/[^)]+\)/g;
  const matches = content.match(pattern);
  return matches || [];
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function runHook(): Promise<HookResult> {
  const input = await parseStdin();
  if (!input) {
    return { exitCode: 0 };
  }

  const toolName = input.tool_name || "";
  const filePath = input.tool_input?.file_path || "";
  const cwd = input.cwd || process.cwd();

  // Only check Write, Edit, and MultiEdit tools
  if (toolName !== "Write" && toolName !== "Edit" && toolName !== "MultiEdit") {
    return { exitCode: 0 };
  }

  // Only check root-level README.md
  if (!isRootReadme(filePath, cwd)) {
    return { exitCode: 0 };
  }

  // Get the content that was written/edited
  const content = input.tool_input?.content || input.tool_input?.new_string || "";
  if (!content) {
    return { exitCode: 0 };
  }

  // Check for absolute GitHub URLs
  const absoluteLinks = findAbsoluteGitHubLinks(content);
  if (absoluteLinks.length === 0) {
    return { exitCode: 0 };
  }

  const reason = `[README-PYPI] Found ${absoluteLinks.length} absolute GitHub URL(s) in root README.md.

Keep README.md links **relative** (e.g., \`[CLAUDE.md](CLAUDE.md)\` not \`[CLAUDE.md](https://github.com/.../CLAUDE.md)\`).

The \`transform_readme.py\` script in \`~/eon/fork-tools/\` converts relative links to version-pinned absolute URLs at PyPI publish time. Relative links:
- Work on GitHub natively
- Are easy for Claude Code to follow
- Get version-pinned automatically at publish

Please revert the absolute URLs to relative links.`;

  return {
    exitCode: 0,
    stdout: createVisibilityOutput(reason),
  };
}

// ============================================================================
// ENTRY POINT
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;

  try {
    result = await runHook();
  } catch (err: unknown) {
    trackHookError("posttooluse-readme-pypi-links", err instanceof Error ? err.message : String(err));
    return process.exit(0);
  }

  if (result.stderr) trackHookError("posttooluse-readme-pypi-links", result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
