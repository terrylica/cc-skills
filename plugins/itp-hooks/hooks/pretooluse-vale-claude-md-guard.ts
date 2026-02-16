#!/usr/bin/env bun
/**
 * PreToolUse hook: Vale CLAUDE.md Guard
 *
 * ACTUALLY REJECTS Edit/Write on CLAUDE.md files if Vale finds issues.
 * Unlike PostToolUse hooks (visibility only), this PreToolUse hook
 * can truly block the tool execution before it happens.
 *
 * Flow:
 * 1. Intercept Edit/Write on CLAUDE.md files
 * 2. Get proposed content (content or apply edit to existing)
 * 3. Write to temp file
 * 4. Run Vale on temp file
 * 5. Return permissionDecision: "deny" if issues found
 *
 * Pattern: PreToolUse with deny semantics (lifecycle-reference.md)
 * ADR: To be created if hook proves useful
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { $ } from "bun";
import { allow, deny, ask, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

// ============================================================================
// CONFIGURATION
// ============================================================================

const HOME = process.env.HOME || "";
const VALE_INI = join(HOME, ".claude/.vale.ini");

// Mode: "deny" = hard block, "ask" = permission dialog
const MODE: "deny" | "ask" = "deny"; // Hard block — Claude autonomously fixes terminology

// Severity threshold: "error" = only errors, "warning" = warnings+errors
const SEVERITY_THRESHOLD = "warning";

// ============================================================================
// HELPERS
// ============================================================================

/**
 * Apply an edit to existing content.
 */
function applyEdit(existing: string, oldString: string, newString: string): string {
  const index = existing.indexOf(oldString);
  if (index === -1) {
    // Edit target not found - return original (let Claude handle the error)
    return existing;
  }
  return existing.slice(0, index) + newString + existing.slice(index + oldString.length);
}

/**
 * Run Vale on content and return issues.
 */
async function runVale(content: string): Promise<{ severity: string; message: string; line: number }[]> {
  // Create temp directory and file
  const tempDir = mkdtempSync(join(tmpdir(), "vale-claude-md-"));
  const tempFile = join(tempDir, "CLAUDE.md");

  try {
    writeFileSync(tempFile, content);

    // Run Vale with JSON output
    const result = await $`vale --config=${VALE_INI} --output=JSON ${tempFile}`.quiet().nothrow();

    if (result.exitCode !== 0 && result.exitCode !== 1) {
      // Vale error (not lint issues)
      trackHookError("pretooluse-vale-claude-md-guard", `Vale failed: ${result.stderr.toString()}`);
      return [];
    }

    const stdout = result.stdout.toString().trim();
    if (!stdout) {
      return [];
    }

    // Parse Vale JSON output
    const valeOutput = JSON.parse(stdout);

    // Vale output is { "filepath": [issues] }
    const issues: { severity: string; message: string; line: number }[] = [];
    for (const [_file, fileIssues] of Object.entries(valeOutput)) {
      if (Array.isArray(fileIssues)) {
        for (const issue of fileIssues) {
          issues.push({
            severity: (issue as { Severity?: string }).Severity?.toLowerCase() || "warning",
            message: (issue as { Message?: string }).Message || "Unknown issue",
            line: (issue as { Line?: number }).Line || 0,
          });
        }
      }
    }

    return issues;
  } finally {
    // Cleanup
    try {
      unlinkSync(tempFile);
    } catch {
      // Ignore cleanup errors
    }
  }
}

/**
 * Filter issues by severity threshold.
 */
function filterBySeverity(issues: { severity: string; message: string; line: number }[], threshold: string): typeof issues {
  if (threshold === "error") {
    return issues.filter((i) => i.severity === "error");
  }
  // "warning" threshold includes warnings and errors
  return issues.filter((i) => i.severity === "warning" || i.severity === "error");
}

/**
 * Format issues for display.
 */
function formatIssues(issues: { severity: string; message: string; line: number }[]): string {
  return issues
    .map((i) => `  Line ${i.line}: [${i.severity.toUpperCase()}] ${i.message}`)
    .join("\n");
}

// ============================================================================
// MAIN
// ============================================================================

async function main(): Promise<void> {
  // Read JSON input from stdin
  const input = await parseStdinOrAllow("vale-claude-md-guard");
  if (!input) return;

  const toolName = input.tool_name || "";
  const toolInput = input.tool_input || {};
  const filePath = toolInput.file_path || "";

  // Only process Edit/Write
  if (toolName !== "Edit" && toolName !== "Write") {
    allow();
    return;
  }

  // Only process CLAUDE.md files
  if (!filePath.endsWith("CLAUDE.md")) {
    allow();
    return;
  }

  // Skip if Vale config doesn't exist
  if (!existsSync(VALE_INI)) {
    allow();
    return;
  }

  // Get the proposed content
  let proposedContent: string;

  if (toolName === "Write") {
    // Write: content is the full new content
    proposedContent = (toolInput.content as string) || "";
  } else {
    // Edit: apply old_string -> new_string to existing content
    const oldString = (toolInput.old_string as string) || "";
    const newString = (toolInput.new_string as string) || "";

    if (!existsSync(filePath)) {
      // File doesn't exist, can't validate edit
      allow();
      return;
    }

    const existing = readFileSync(filePath, "utf8");
    proposedContent = applyEdit(existing, oldString, newString);
  }

  // Run Vale
  const allIssues = await runVale(proposedContent);
  const issues = filterBySeverity(allIssues, SEVERITY_THRESHOLD);

  if (issues.length === 0) {
    allow();
    return;
  }

  // Format rejection message
  const fileName = filePath.split("/").pop() || "CLAUDE.md";
  const reason = `[VALE-CLAUDE-MD-GUARD] Found ${issues.length} terminology issue(s) in ${fileName}:

${formatIssues(issues)}

Fix the issues before saving. Check ~/.claude/docs/GLOSSARY.md for correct terminology.`;

  // Output based on mode
  if (MODE === "deny") {
    deny(reason);
  } else {
    ask(reason);
  }
}

// Entry point
main().catch((e) => {
  trackHookError("pretooluse-vale-claude-md-guard", e instanceof Error ? e.message : String(e));
  allow();
});
