#!/usr/bin/env bun
/**
 * Stop hook: Time-Weighted Sharpe Audit
 *
 * When Claude stops, audits the session for any Sharpe calculations
 * that should have been time-weighted. This is the final safety net.
 *
 * Output format: `systemMessage` for informational (non-blocking)
 *
 * Reference: /docs/reference/range-bar-sharpe-calculation.md
 */

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  detectSharpeIssues,
  isExcludedPath,
  hasRangeBarContext,
  DEFAULT_CONFIG,
} from "./time-weighted-sharpe-patterns.mjs";

/**
 * Parse stdin JSON for Stop hook.
 */
async function parseStdin() {
  try {
    const stdin = await Bun.stdin.text();
    return JSON.parse(stdin);
  } catch {
    return null;
  }
}

/**
 * Recursively find Python files in directory.
 */
function findPythonFiles(dir, maxDepth = 3, currentDepth = 0) {
  if (currentDepth >= maxDepth) return [];

  const files = [];
  try {
    const entries = readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = join(dir, entry.name);

      // Skip common non-source directories
      if (entry.isDirectory()) {
        if (["node_modules", ".git", "__pycache__", ".venv", "venv", ".tox"].includes(entry.name)) {
          continue;
        }
        files.push(...findPythonFiles(fullPath, maxDepth, currentDepth + 1));
      } else if (entry.isFile() && entry.name.endsWith(".py")) {
        files.push(fullPath);
      }
    }
  } catch {
    // Ignore permission errors
  }
  return files;
}

/**
 * Output informational message (non-blocking).
 * Uses additionalContext so Claude sees it in context.
 * Also includes systemMessage for user visibility.
 */
function inform(message) {
  console.log(JSON.stringify({
    additionalContext: message,
    systemMessage: message,
  }));
}

/**
 * Allow stop normally.
 */
function allowStop() {
  console.log(JSON.stringify({}));
}

/**
 * Main entry point.
 */
async function main() {
  const input = await parseStdin();
  if (!input) {
    allowStop();
    return;
  }

  // Check if this is already a continuation from stop hook
  if (input.stop_hook_active) {
    allowStop();
    return;
  }

  // Get project directory
  const projectDir = process.env.CLAUDE_PROJECT_DIR || "";
  if (!projectDir) {
    allowStop();
    return;
  }

  // Find Python files in research directories (where Sharpe calculations likely live)
  const researchDirs = [
    join(projectDir, "examples", "research"),
    join(projectDir, "src"),
    join(projectDir, "scripts"),
  ];

  const allFindings = [];

  for (const dir of researchDirs) {
    try {
      const pyFiles = findPythonFiles(dir, 2);

      for (const filePath of pyFiles) {
        if (isExcludedPath(filePath, DEFAULT_CONFIG.exclude_paths)) {
          continue;
        }

        try {
          const content = readFileSync(filePath, "utf8");

          // Only audit files with range bar context
          if (!hasRangeBarContext(content, DEFAULT_CONFIG.range_bar_indicators)) {
            continue;
          }

          const findings = detectSharpeIssues(
            content,
            DEFAULT_CONFIG.patterns,
            DEFAULT_CONFIG.whitelist_comments
          );

          if (findings.length > 0) {
            allFindings.push({
              file: filePath.replace(projectDir, ""),
              count: findings.length,
              critical: findings.filter(f => f.severity === "CRITICAL").length,
            });
          }
        } catch {
          // Skip unreadable files
        }
      }
    } catch {
      // Skip non-existent directories
    }
  }

  if (allFindings.length === 0) {
    allowStop();
    return;
  }

  // Format audit summary
  const totalIssues = allFindings.reduce((sum, f) => sum + f.count, 0);
  const criticalIssues = allFindings.reduce((sum, f) => sum + f.critical, 0);

  const fileList = allFindings
    .slice(0, 5)  // Limit to 5 files
    .map(f => `  ${f.file}: ${f.count} issues${f.critical > 0 ? ` (${f.critical} CRITICAL)` : ""}`)
    .join("\n");

  const moreFiles = allFindings.length > 5 ? `\n  ... and ${allFindings.length - 5} more files` : "";

  const message = `[TIME-WEIGHTED SHARPE AUDIT] Found ${totalIssues} simple Sharpe patterns in range bar files.
${criticalIssues > 0 ? `⚠️ ${criticalIssues} CRITICAL issues require immediate attention.\n` : ""}
Files with issues:
${fileList}${moreFiles}

Range bars have variable durations - simple bar Sharpe produces misleading results.
Consider using compute_time_weighted_sharpe(pnl, duration_us) for accuracy.`;

  inform(message);
}

main().catch((e) => {
  console.error(`[sharpe-audit] Error: ${e.message}`);
  console.log(JSON.stringify({}));  // Allow stop on error
});
