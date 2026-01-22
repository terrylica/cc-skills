#!/usr/bin/env bun
/**
 * PostToolUse hook: Time-Weighted Sharpe Reminder
 *
 * After Write/Edit operations on Python files, scans for simple bar Sharpe
 * patterns and reminds Claude about time-weighted alternatives.
 *
 * This is a REMINDER hook (non-blocking). The PreToolUse guard is the
 * blocking defense; this catches anything that slips through or exists
 * in existing code being edited.
 *
 * Reference: /docs/reference/range-bar-sharpe-calculation.md
 */

import { readFileSync, existsSync } from "node:fs";
import {
  DEFAULT_CONFIG,
  detectSharpeIssues,
  isExcludedPath,
  formatFindings,
  hasRangeBarContext,
} from "./time-weighted-sharpe-patterns.mjs";

/**
 * Parse stdin JSON for PostToolUse.
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
 * Output for Claude visibility.
 * PostToolUse requires `decision: "block"` for Claude to see the reason.
 */
function remind(reason) {
  console.log(JSON.stringify({
    decision: "block",
    reason: reason,
  }));
}

/**
 * Allow silently (no output needed for PostToolUse allow).
 */
function allow() {
  // Empty output = tool result passes through unchanged
  process.exit(0);
}

/**
 * Main entry point.
 */
async function main() {
  const input = await parseStdin();
  if (!input) {
    allow();
    return;
  }

  const toolName = input.tool_name || "";
  const toolInput = input.tool_input || {};
  // toolResponse available but not used for this reminder

  // Only check Write and Edit tools
  if (toolName !== "Write" && toolName !== "Edit") {
    allow();
    return;
  }

  // Get file path
  const filePath = toolInput.file_path || "";
  if (!filePath.endsWith(".py")) {
    allow();
    return;
  }

  // Check if path is excluded
  if (isExcludedPath(filePath, DEFAULT_CONFIG.exclude_paths)) {
    allow();
    return;
  }

  // Read the file content (after write/edit completed)
  let content = "";
  try {
    if (existsSync(filePath)) {
      content = readFileSync(filePath, "utf8");
    } else {
      // File might have been written but path is relative
      allow();
      return;
    }
  } catch {
    allow();
    return;
  }

  // Detect Sharpe issues in the written/edited file
  const findings = detectSharpeIssues(content, DEFAULT_CONFIG.patterns, DEFAULT_CONFIG.whitelist_comments);

  if (findings.length === 0) {
    allow();
    return;
  }

  // Format reminder message
  const fileName = filePath.split("/").pop();
  const formattedFindings = formatFindings(findings);
  const isRangeBarFile = hasRangeBarContext(content, DEFAULT_CONFIG.range_bar_indicators);

  const contextNote = isRangeBarFile
    ? "\n⚠️ RANGE BAR CONTEXT DETECTED - Time-weighted Sharpe is CRITICAL for accuracy."
    : "";

  const reason = `[TIME-WEIGHTED SHARPE REMINDER] ${fileName} contains simple bar Sharpe patterns.
${contextNote}

${formattedFindings}

RECOMMENDATION:
- For range bars: Use compute_time_weighted_sharpe(pnl, duration_us)
- For fixed intervals: Simple Sharpe is acceptable
- To suppress: Add "# time-weighted-sharpe-ok" comment

Reference: exp066_bar_index_wfo.py:compute_time_weighted_sharpe()`;

  remind(reason);
}

main().catch((e) => {
  console.error(`[sharpe-reminder] Error: ${e.message}`);
  process.exit(0);
});
