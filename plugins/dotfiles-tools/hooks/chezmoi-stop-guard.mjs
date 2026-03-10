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
import { realpathSync } from "fs";

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
 * Get chezmoi diff summary, filtering out mode-only changes
 * (chezmoi cannot track directory permission modes)
 * @returns {string} Diff output or empty string
 */
function getChezmoiDiff() {
  try {
    const result = spawnSync("chezmoi", ["diff", "--no-pager"], {
      encoding: "utf8",
      timeout: 10000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    const output = result.stdout?.trim() || "";

    // Filter out mode-only changes (directory permission diffs that chezmoi can't fix)
    // Pattern: "diff --git ... \nold mode XXXXX\nnew mode XXXXX" with no other content
    const filtered = filterModeOnlyChanges(output);
    return filtered;
  } catch {
    return "";
  }
}

/**
 * Filter out diff entries that only have mode changes (no content)
 * @param {string} diffOutput
 * @returns {string} Filtered diff output
 */
function filterModeOnlyChanges(diffOutput) {
  if (!diffOutput) return "";

  // Split by diff headers
  const parts = diffOutput.split(/(?=^diff --git )/m);
  const meaningful = [];

  for (const part of parts) {
    if (!part.trim()) continue;

    // Check if this diff entry has any content changes (not just mode)
    const lines = part.split("\n");
    let hasContentChange = false;

    for (const line of lines) {
      // Skip diff header, mode lines, and empty lines
      if (
        line.startsWith("diff --git") ||
        line.startsWith("old mode") ||
        line.startsWith("new mode") ||
        line.trim() === ""
      ) {
        continue;
      }
      // Any other line means actual content change
      hasContentChange = true;
      break;
    }

    if (hasContentChange) {
      meaningful.push(part);
    }
  }

  return meaningful.join("");
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
 * Resolve a path to its canonical absolute form.
 *
 * Handles: ~ expansion, symlinks (via realpathSync), case normalization
 * on case-insensitive APFS, trailing/double slashes.
 *
 * Falls back to string normalization when the path doesn't exist on disk
 * (e.g., chezmoi target not yet applied, or file was deleted).
 *
 * @param {string} p - Path to resolve (may start with ~/)
 * @param {string} home - Value of $HOME
 * @returns {string} Canonical absolute path
 */
function resolveCanonical(p, home) {
  let abs = p;

  // Expand ~ → $HOME
  if (abs.startsWith("~/")) {
    abs = home + abs.slice(1);
  } else if (abs === "~") {
    abs = home;
  }

  // Normalize slashes: collapse // → /, strip trailing /
  abs = abs.replace(/\/+/g, "/").replace(/\/$/, "");

  // Resolve symlinks + case normalization (APFS is case-insensitive)
  // realpathSync returns the on-disk canonical path, handling:
  //   - symlinks (~/eon → /Volumes/data/eon)
  //   - case folding (/Users/Terryli → /Users/terryli)
  try {
    abs = realpathSync(abs);
  } catch {
    // Path doesn't exist on disk (deleted file, unapplied chezmoi target).
    // Keep the string-normalized version — still good enough for prefix matching.
  }

  return abs;
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
  // PLAN MODE BYPASS (Skip guard entirely during plan mode)
  // ============================================================================
  // In plan mode, Claude is exploring/planning — no files were intentionally modified.
  // Pre-existing chezmoi drift should not block stopping a planning session.
  // permission_mode is a universal field available to all hook events.
  if (input.permission_mode === "plan") {
    console.log("{}");
    process.exit(0);
  }

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

  // ============================================================================
  // SCOPE CHECK: Only block when working in the chezmoi source directory.
  //
  // Chezmoi tracks HOME directory files (~/.config/*, ~/.zshrc, etc.).
  // These are NEVER under a project CWD like ~/eon/some-project/.
  // The old approach (checking if drift files are under CWD) was backwards
  // and caused false positives across every project.
  //
  // Correct logic: only block when CWD is the chezmoi source repo itself
  // (~/own/dotfiles). All other projects → silently allow.
  // ============================================================================
  const cwd = input.cwd || "";
  const homePath = process.env.HOME || "";

  let chezmoiSourceDir = "";
  try {
    const result = spawnSync("chezmoi", ["source-path"], {
      encoding: "utf8",
      timeout: 5000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    chezmoiSourceDir = result.stdout?.trim() || "";
  } catch {
    // Can't determine source path — silently allow
    console.log("{}");
    process.exit(0);
  }

  if (!cwd || !chezmoiSourceDir) {
    // Can't determine scope — silently allow
    console.log("{}");
    process.exit(0);
  }

  const cwdResolved = resolveCanonical(cwd, homePath);
  const sourceResolved = resolveCanonical(chezmoiSourceDir, homePath);

  // Only block if CWD is the chezmoi source dir or a subdirectory of it
  const isInSourceRepo =
    cwdResolved === sourceResolved ||
    cwdResolved.startsWith(sourceResolved + "/");

  if (!isInSourceRepo) {
    // Working in a different project — chezmoi drift is pre-existing, not our concern
    console.log("{}");
    process.exit(0);
  }

  // Extract modified files for the block message
  const modifiedFiles = extractModifiedFiles(diffOutput);
  const fileList =
    modifiedFiles.length > 0
      ? modifiedFiles.slice(0, 5).join("\n  - ")
      : "(run chezmoi diff to see details)";

  const truncated = modifiedFiles.length > 5 ? `\n  ... and ${modifiedFiles.length - 5} more` : "";

  // BLOCK stopping — we're in the chezmoi source repo with uncommitted drift
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

main().catch(async (err) => {
  const { trackHookError } = await import("../../itp-hooks/hooks/lib/hook-error-tracker.ts");
  trackHookError("chezmoi-stop-guard", err instanceof Error ? err.message : String(err));
  console.log("{}"); // Allow stop on error
  process.exit(0);
});
