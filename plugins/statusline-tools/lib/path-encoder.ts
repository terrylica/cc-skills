/**
 * path-encoder.ts - CWD encoding and hashing for session registry
 *
 * Claude Code uses path encoding: /Users/terryli/foo -> -Users-terryli-foo
 * We also provide SHA256 hashing for PII prevention in logs/metadata.
 */

import { createHash } from "crypto";
import { basename } from "path";
import { execSync } from "child_process";

/**
 * Encode a project path in Claude Code's native format
 * Example: /Users/terryli/eon/cc-skills -> -Users-terryli-eon-cc-skills
 */
export function encodeProjectPath(cwd: string): string {
  // Replace all slashes with dashes, ensure leading dash
  return "-" + cwd.replace(/\//g, "-").replace(/^-/, "");
}

/**
 * Get the full project directory path for session registry
 * Example: /Users/terryli/eon/cc-skills -> ~/.claude/projects/-Users-terryli-eon-cc-skills
 */
export function getProjectDir(cwd: string): string {
  return `${process.env.HOME}/.claude/projects/${encodeProjectPath(cwd)}`;
}

/**
 * Sanitize path for logging (PII prevention)
 * Replaces home directory with ~
 */
export function sanitizePath(path: string): string {
  const home = process.env.HOME || "";
  return path.replace(home, "~");
}

/**
 * Hash a path for privacy in metadata
 * Returns first 12 chars of SHA256 hash
 */
export function hashPath(path: string): string {
  return createHash("sha256").update(path).digest("hex").slice(0, 12);
}

/**
 * Extract repository name from cwd
 * Tries git remote first, falls back to directory basename
 */
export function getRepoName(cwd: string): string {
  try {
    // Try to get repo name from git remote origin URL
    const remoteUrl = execSync("git remote get-url origin", {
      cwd,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();

    // Extract repo name from URL patterns:
    // git@github.com:user/repo.git -> repo
    // https://github.com/user/repo.git -> repo
    // https://github.com/user/repo -> repo
    const match = remoteUrl.match(/\/([^/]+?)(\.git)?$/);
    if (match) {
      return match[1];
    }
  } catch {
    // Not a git repo or no remote - fall back to basename
  }

  // Fallback: use directory basename
  return basename(cwd);
}
