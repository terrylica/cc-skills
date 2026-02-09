#!/usr/bin/env bun
/**
 * CWD Deletion Pattern Definitions
 *
 * Patterns for detecting commands that would delete or overwrite the
 * current working directory. When CWD is deleted, the shell becomes
 * unrecoverable — every subsequent command fails with exit code 1
 * because the OS cannot resolve the process's working directory.
 *
 * Two lessons encoded:
 * 1. NEVER delete CWD without cd-ing elsewhere first
 * 2. For git re-clone operations, prefer git remote set-url + fetch + reset
 *
 * ADR: /docs/adr/2026-02-09-cwd-deletion-guard.md
 */

import { resolve } from "node:path";

/**
 * Escape hatch comment pattern.
 * Adding this comment allows the command to pass.
 */
export const ESCAPE_HATCH = /#\s*CWD-DELETE-OK/i;

/**
 * Normalize a path for comparison.
 * - Expands ~ to $HOME
 * - Resolves to absolute path
 * - Removes trailing slashes
 */
function normalizePath(p) {
  const home = process.env.HOME || "/Users/unknown";
  let normalized = p.trim();

  // Strip surrounding quotes
  normalized = normalized.replace(/^["']|["']$/g, "");

  // Expand ~
  if (normalized.startsWith("~/")) {
    normalized = home + normalized.slice(1);
  } else if (normalized === "~") {
    normalized = home;
  }

  // Expand $HOME
  normalized = normalized.replace(/\$HOME\b/g, home);
  normalized = normalized.replace(/\$\{HOME\}/g, home);

  // Resolve to absolute (handles . and ..)
  normalized = resolve(normalized);

  // Remove trailing slash
  normalized = normalized.replace(/\/+$/, "");

  return normalized;
}

/**
 * Check if a target path would delete the CWD.
 *
 * Returns true if:
 * - target === cwd (exact match)
 * - target is a parent of cwd (deleting parent kills child)
 * - target is "." or "./" (relative CWD reference)
 */
function wouldDeleteCwd(targetPath, cwd) {
  const normalizedTarget = normalizePath(targetPath);
  const normalizedCwd = normalizePath(cwd);

  // Exact match
  if (normalizedTarget === normalizedCwd) return true;

  // Parent directory deletion (target is ancestor of CWD)
  if (normalizedCwd.startsWith(normalizedTarget + "/")) return true;

  return false;
}

/**
 * Extract rm target paths from a command string.
 * Handles: rm -rf /path, rm -rf ~/path, rm -rf $HOME/path
 */
function extractRmTargets(command) {
  const targets = [];

  // Match rm with various flag combinations followed by paths
  // Handles: rm -rf, rm -r -f, rm --recursive --force, rm -fr
  const rmPattern =
    /\brm\s+(?:(?:-[rRfidv]+\s+)*|(?:--(?:recursive|force|interactive|dir|verbose)\s+)*)(.+?)(?:\s*(?:&&|\|\||;|$|\||\n|2>&1|>[^&]))/g;

  let match;
  while ((match = rmPattern.exec(command)) !== null) {
    const pathsPart = match[1].trim();
    // Split on unquoted spaces to get individual paths
    const paths = pathsPart.split(/\s+/).filter((p) => p && !p.startsWith("-"));
    targets.push(...paths);
  }

  return targets;
}

/**
 * Detect if a bash command would delete the CWD.
 *
 * @param {string} command - The bash command to check
 * @param {string} cwd - The current working directory
 * @returns {{ detected: boolean, target?: string, isGitOperation: boolean }}
 */
export function detectCwdDeletion(command, cwd) {
  if (!command || !cwd) {
    return { detected: false, isGitOperation: false };
  }

  // Check escape hatch
  if (ESCAPE_HATCH.test(command)) {
    return { detected: false, isGitOperation: false };
  }

  // Check for $(pwd) or $PWD in rm commands
  if (/\brm\s+.*(-[rRf]+|--recursive)/.test(command)) {
    if (/\$\(pwd\)|\$PWD|\$\{PWD\}/.test(command)) {
      const isGit = /\bgit\s+(clone|init)\b/.test(command);
      return { detected: true, target: "$(pwd)", isGitOperation: isGit };
    }
  }

  // Check for "." or "./" as rm target
  if (/\brm\s+.*(-[rRf]+|--recursive).*\s+\.(?:\/?\s|\/?\s*$|\/?\s*&&|\/?\s*;|\/?\s*\|)/.test(command)) {
    return { detected: true, target: ".", isGitOperation: false };
  }

  // Extract and check explicit path targets
  const targets = extractRmTargets(command);

  for (const target of targets) {
    if (wouldDeleteCwd(target, cwd)) {
      // Determine if this is a git-related operation (rm before clone)
      const isGit =
        /\bgit\s+(clone|init)\b/.test(command) ||
        /\bgh\s+repo\s+clone\b/.test(command);

      return { detected: true, target, isGitOperation: isGit };
    }
  }

  return { detected: false, isGitOperation: false };
}

/**
 * Format denial message with actionable guidance.
 *
 * @param {string} target - The path that would be deleted
 * @param {string} cwd - The current working directory
 * @param {boolean} isGitOperation - Whether this is a git clone/re-clone operation
 * @returns {string}
 */
export function formatDenial(target, cwd, isGitOperation) {
  const lines = [
    "[CWD DELETION GUARD] Blocked: This command would delete the current working directory.\n",
    `  CWD:    ${cwd}`,
    `  Target: ${target}\n`,
    "Deleting the CWD makes the shell unrecoverable — every subsequent",
    "command fails with exit code 1 (including cd). The entire session breaks.\n",
  ];

  if (isGitOperation) {
    lines.push("RECOMMENDED (git re-clone): Use git remote set-url instead of rm + clone:\n");
    lines.push("  git remote set-url origin <new-url>");
    lines.push("  git fetch origin");
    lines.push("  git reset --hard origin/main\n");
    lines.push("This preserves CWD, avoids re-downloading, and keeps local branches.");
  } else {
    lines.push("RECOMMENDED: cd to another directory BEFORE deleting:\n");
    lines.push("  cd /tmp && rm -rf <target>");
    lines.push("  # or");
    lines.push(`  cd ~ && rm -rf ${target}`);
  }

  lines.push("\nEscape hatch: Add '# CWD-DELETE-OK' comment if intentional.");

  return lines.join("\n");
}
