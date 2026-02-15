#!/usr/bin/env bun
/**
 * PreToolUse hook: Fake Data Guard
 *
 * Detects fake/synthetic data patterns in new Python files and denies
 * with actionable guidance for Claude Code to self-correct. Universal across all projects.
 *
 * Usage:
 *   Installed via /itp:hooks install
 *   Configured via .claude/fake-data-guard.json (project) or
 *   ~/.claude/fake-data-guard.json (global)
 *
 * ADR: /docs/adr/2025-12-27-fake-data-guard-universal.md
 */

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import {
  DEFAULT_CONFIG,
  detectFakeData,
  isExcludedPath,
  formatFindings,
} from "./fake-data-patterns.mjs";
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
    const projectConfig = join(projectDir, ".claude", "fake-data-guard.json");
    if (existsSync(projectConfig)) {
      try {
        const loaded = JSON.parse(readFileSync(projectConfig, "utf8"));
        return mergeConfig(config, loaded);
      } catch (e) {
        console.error(`[fake-data-guard] Warning: Failed to parse ${projectConfig}: ${e.message}`);
      }
    }
  }

  // Try global config
  const homeDir = process.env.HOME || process.env.USERPROFILE;
  if (homeDir) {
    const globalConfig = join(homeDir, ".claude", "fake-data-guard.json");
    if (existsSync(globalConfig)) {
      try {
        const loaded = JSON.parse(readFileSync(globalConfig, "utf8"));
        return mergeConfig(config, loaded);
      } catch (e) {
        console.error(`[fake-data-guard] Warning: Failed to parse ${globalConfig}: ${e.message}`);
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
  };
}

/**
 * Main entry point.
 */
async function main() {
  // Read JSON input from stdin (allow-on-error semantics)
  const input = await parseStdinOrAllow("fake-data-guard");
  if (!input) return;

  // Only process Write tool (not Edit - respect existing files)
  const toolName = input.tool_name || "";
  if (toolName !== "Write") {
    allow();
    return;
  }

  // Get file path and content
  const toolInput = input.tool_input || {};
  const filePath = toolInput.file_path || "";
  const content = toolInput.content || "";

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

  // Detect fake data patterns
  const findings = detectFakeData(content, config.patterns, config.whitelist_comments);

  // No findings - allow
  if (findings.length === 0) {
    allow();
    return;
  }

  // Format message
  const fileName = filePath.split("/").pop();
  const formattedFindings = formatFindings(findings);
  const reason = `[FAKE DATA GUARD] Detected fake/synthetic data patterns in ${fileName}:

${formattedFindings}

Consider using real data, pre-computed fixtures, or API data instead.
To whitelist: add "# noqa: fake-data" comment to the line.`;

  // Output based on mode
  if (config.mode === "deny") {
    deny(reason);
  } else {
    ask(reason);
  }
}

// Run
main().catch((e) => {
  console.error(`[fake-data-guard] Error: ${e.message}`);
  allow();
});
