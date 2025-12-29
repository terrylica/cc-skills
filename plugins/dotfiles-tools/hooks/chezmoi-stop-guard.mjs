#!/usr/bin/env bun
/**
 * Stop hook: Chezmoi Sync Guard
 *
 * FORCES Claude to sync chezmoi-tracked dotfiles before session ends.
 * Unlike PostToolUse (visibility only), Stop hooks with decision:block
 * ACTUALLY PREVENT Claude from stopping until the issue is resolved.
 *
 * This catches ALL file modifications including Bash(cp ...) which
 * bypasses the PostToolUse Edit|Write matcher.
 *
 * Usage:
 *   Installed via /dotfiles-tools:hooks install
 *
 * Lifecycle Reference:
 *   - Stop hook with {} = allow stop
 *   - Stop hook with {decision: "block", reason: "..."} = FORCE continuation
 *
 * ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
 */

import { execSync, spawnSync } from "child_process";

/**
 * Check if chezmoi is available
 * @returns {boolean}
 */
function hasChezoi() {
  try {
    execSync("command -v chezmoi", { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/**
 * Get chezmoi diff summary
 * @returns {string} Diff output or empty string
 */
function getChezmoiDiff() {
  try {
    const result = spawnSync("chezmoi", ["diff", "--no-pager"], {
      encoding: "utf8",
      timeout: 10000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    return result.stdout?.trim() || "";
  } catch {
    return "";
  }
}

/**
 * Get list of modified files from chezmoi diff
 * @param {string} diffOutput
 * @returns {string[]} Array of file paths
 */
function extractModifiedFiles(diffOutput) {
  const files = new Set();
  const lines = diffOutput.split("\n");

  for (const line of lines) {
    // Match diff header: diff --git a/.config/foo b/.config/foo
    const match = line.match(/^diff --git a\/(.+) b\/(.+)$/);
    if (match) {
      // Use the 'b' path (destination)
      files.add(`~/${match[2]}`);
    }
  }

  return Array.from(files);
}

/**
 * Main hook logic
 */
function main() {
  // Read stdin (hook input JSON)
  const chunks = [];
  const stdin = Bun.stdin.stream();
  const reader = stdin.getReader();

  // Non-blocking stdin read with timeout
  const readStdin = async () => {
    try {
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(decoder.decode(value, { stream: true }));
      }
    } catch {
      // Ignore stdin errors
    }
  };

  // Run synchronously for hook context
  Bun.sleepSync(0); // Yield to allow stdin

  // Skip if chezmoi not available
  if (!hasChezoi()) {
    console.log("{}");
    process.exit(0);
  }

  // Check for uncommitted chezmoi changes
  const diffOutput = getChezmoiDiff();

  if (diffOutput.length === 0) {
    // No changes - allow stop
    console.log("{}");
    process.exit(0);
  }

  // Extract modified files for helpful message
  const modifiedFiles = extractModifiedFiles(diffOutput);
  const fileList =
    modifiedFiles.length > 0
      ? modifiedFiles.slice(0, 5).join("\n  - ")
      : "(run chezmoi diff to see details)";

  const truncated = modifiedFiles.length > 5 ? `\n  ... and ${modifiedFiles.length - 5} more` : "";

  // BLOCK stopping - force Claude to sync chezmoi
  const result = {
    decision: "block",
    reason: `[CHEZMOI-GUARD] Uncommitted dotfile changes detected. Sync before stopping:

Modified files:
  - ${fileList}${truncated}

Run these commands:
  chezmoi re-add --verbose
  chezmoi git -- add -A && chezmoi git -- commit -m "sync: dotfiles" && chezmoi git -- push

This Stop hook will allow session end once chezmoi diff returns clean.`,
  };

  console.log(JSON.stringify(result));
}

main();
