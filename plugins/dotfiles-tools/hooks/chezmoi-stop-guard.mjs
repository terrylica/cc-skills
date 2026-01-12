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
 * Parse stdin JSON to get hook input
 * @returns {object} Parsed input or empty object
 */
async function parseStdinInput() {
  try {
    const text = await Bun.stdin.text();
    return text ? JSON.parse(text) : {};
  } catch {
    return {};
  }
}

/**
 * Main hook logic
 */
async function main() {
  // Parse hook input from stdin
  const input = await parseStdinInput();

  // ============================================================================
  // LOOP PREVENTION (Critical - per lifecycle-reference.md lines 198-201)
  // ============================================================================
  // If stop_hook_active is true, a previous Stop hook already triggered continuation.
  // We MUST allow stopping to prevent infinite loops, even if chezmoi has changes.
  // Reference: plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md
  if (input.stop_hook_active === true) {
    // Already tried to fix once - allow stopping to break the loop
    console.log(
      JSON.stringify({
        systemMessage:
          "[CHEZMOI-GUARD] Allowing stop despite uncommitted changes (stop_hook_active=true, breaking loop). " +
          "Run chezmoi sync manually after session ends.",
      }),
    );
    process.exit(0);
  }

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

ACTION REQUIRED - Run these Bash commands (chezmoi is NOT blocked by gh-isolation):
  chezmoi re-add --verbose
  chezmoi git -- add -A && chezmoi git -- commit -m "sync: dotfiles" && chezmoi git -- push

NOTE: The gh-isolation hook only blocks \`gh\` CLI commands. Other Bash commands (chezmoi, git, npm, etc.) work normally.

This Stop hook will allow session end once chezmoi diff returns clean.`,
  };

  console.log(JSON.stringify(result));
}

main().catch((err) => {
  console.error("chezmoi-stop-guard error:", err);
  console.log("{}"); // Allow stop on error
  process.exit(0);
});
