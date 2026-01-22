#!/usr/bin/env bun
/**
 * PreToolUse hook: Time-Weighted Sharpe Guard
 *
 * Detects non-time-weighted Sharpe calculations in Python files that work
 * with range bar data. Range bars have variable durations, so simple
 * mean(pnl)/std(pnl) Sharpe calculations produce misleading results.
 *
 * PROBLEM: Range bars have irregular timestamps. A 1-minute bar and a
 * 1-hour bar contribute equally to simple Sharpe, distorting results.
 *
 * SOLUTION: Use time-weighted Sharpe that weights by bar duration:
 *   sharpe = weighted_mean / weighted_std * sqrt(annualization)
 *
 * Usage:
 *   Installed via /itp:hooks install
 *   Configured via .claude/time-weighted-sharpe-guard.json (project) or
 *   ~/.claude/time-weighted-sharpe-guard.json (global)
 *
 * Reference: /docs/reference/range-bar-sharpe-calculation.md
 * ADR: /docs/adr/2026-01-21-time-weighted-sharpe-guard.md
 */

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import {
  DEFAULT_CONFIG,
  detectSharpeIssues,
  isExcludedPath,
  formatFindings,
  hasRangeBarContext,
} from "./time-weighted-sharpe-patterns.mjs";
import { allow, ask, deny, parseStdinOrAllow } from "./pretooluse-helpers.ts";

/**
 * Load configuration from project or global config file.
 * Precedence: project > global > defaults
 *
 * @param {string|undefined} projectDir - Project directory from CLAUDE_PROJECT_DIR
 * @returns {Object} Merged configuration
 */
function loadConfig(projectDir) {
  const config = { ...DEFAULT_CONFIG };

  // Try project-level config
  if (projectDir) {
    const projectConfig = join(projectDir, ".claude", "time-weighted-sharpe-guard.json");
    if (existsSync(projectConfig)) {
      try {
        const loaded = JSON.parse(readFileSync(projectConfig, "utf8"));
        return mergeConfig(config, loaded);
      } catch (e) {
        console.error(`[sharpe-guard] Warning: Failed to parse ${projectConfig}: ${e.message}`);
      }
    }
  }

  // Try global config
  const homeDir = process.env.HOME || process.env.USERPROFILE;
  if (homeDir) {
    const globalConfig = join(homeDir, ".claude", "time-weighted-sharpe-guard.json");
    if (existsSync(globalConfig)) {
      try {
        const loaded = JSON.parse(readFileSync(globalConfig, "utf8"));
        return mergeConfig(config, loaded);
      } catch (e) {
        console.error(`[sharpe-guard] Warning: Failed to parse ${globalConfig}: ${e.message}`);
      }
    }
  }

  return config;
}

/**
 * Merge loaded config with defaults.
 */
function mergeConfig(defaults, loaded) {
  return {
    ...defaults,
    ...loaded,
    patterns: { ...defaults.patterns, ...(loaded.patterns || {}) },
    whitelist_comments: loaded.whitelist_comments || defaults.whitelist_comments,
    exclude_paths: loaded.exclude_paths || defaults.exclude_paths,
    range_bar_indicators: loaded.range_bar_indicators || defaults.range_bar_indicators,
  };
}

/**
 * Main entry point.
 */
async function main() {
  // Read JSON input from stdin (allow-on-error semantics)
  const input = await parseStdinOrAllow("time-weighted-sharpe-guard");
  if (!input) return;

  // Only process Write and Edit tools
  const toolName = input.tool_name || "";
  if (toolName !== "Write" && toolName !== "Edit") {
    allow();
    return;
  }

  // Get file path and content
  const toolInput = input.tool_input || {};
  const filePath = toolInput.file_path || "";
  const content = toolInput.content || toolInput.new_string || "";

  // Only check Python files
  if (!filePath.endsWith(".py")) {
    allow();
    return;
  }

  // Load config
  const projectDir = process.env.CLAUDE_PROJECT_DIR || "";
  const config = loadConfig(projectDir);

  // Check if hook is disabled
  if (!config.enabled) {
    allow();
    return;
  }

  // Check if path is excluded
  if (isExcludedPath(filePath, config.exclude_paths)) {
    allow();
    return;
  }

  // Detect Sharpe issues
  const findings = detectSharpeIssues(content, config.patterns, config.whitelist_comments);

  // No findings - allow
  if (findings.length === 0) {
    allow();
    return;
  }

  // Format message
  const fileName = filePath.split("/").pop();
  const formattedFindings = formatFindings(findings);
  const isRangeBarFile = hasRangeBarContext(content, config.range_bar_indicators);

  const contextNote = isRangeBarFile
    ? "\n\nRANGE BAR CONTEXT DETECTED: This file appears to work with range bar data.\nRange bars have variable durations - simple bar Sharpe will distort results."
    : "";

  const reason = `[TIME-WEIGHTED SHARPE GUARD] Detected non-time-weighted Sharpe in ${fileName}
${contextNote}

${formattedFindings}

REQUIRED FIXES:
1. Use compute_time_weighted_sharpe(pnl, duration_us) from metrics module
2. OR add "# time-weighted-sharpe-ok" comment if this is NOT range bar data
3. OR add "# allow-simple-sharpe" if simple Sharpe is intentional

REFERENCE:
- ADR: /docs/adr/2026-01-21-time-weighted-sharpe-guard.md
- Guide: /docs/reference/range-bar-sharpe-calculation.md
- Canonical: exp066_bar_index_wfo.py:compute_time_weighted_sharpe()`;

  // Output based on mode
  if (config.mode === "deny") {
    deny(reason);
  } else {
    ask(reason);
  }
}

// Run
main().catch((e) => {
  console.error(`[time-weighted-sharpe-guard] Error: ${e.message}`);
  allow();
});
