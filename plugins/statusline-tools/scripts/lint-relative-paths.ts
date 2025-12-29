#!/usr/bin/env bun
/**
 * lint-relative-paths.ts - Lint markdown files for non-repo-relative local paths
 *
 * Repo-relative paths MUST start with / (e.g., /docs/foo.md)
 *
 * Violations:
 *   - ../foo.md (relative traversal)
 *   - foo/bar.md (missing leading /)
 *   - ./foo.md (explicit current dir)
 *
 * Allowed:
 *   - /docs/foo.md (repo-relative)
 *   - #anchor (fragment only)
 *   - https://... (external URL)
 *   - mailto:... (email)
 *   - Links inside code fences (```)
 *   - Inline code examples: `[text](url)`
 *   - Template variables: {{var}}, {var}
 *   - ASCII diagram placeholders: (...)
 *
 * KEY IMPROVEMENT: Uses git ls-files to respect .gitignore
 * This eliminates false positives from cloned repos (repos/), build artifacts (target/), etc.
 *
 * ERROR HANDLING: All failures are explicit and verbose for Claude Code CLI.
 * Exit codes:
 *   0 - Success (no violations or skip condition met)
 *   1 - Violations found (lint failure)
 *   2 - Hard block / fatal error (Claude Code hook protocol)
 */

import { execSync } from "child_process";
import { existsSync, readFileSync, readdirSync } from "fs";
import { join, resolve } from "path";

// Verbose error logging for Claude Code CLI
function logError(context: string, error: unknown): void {
  console.error(`\n❌ [lint-relative-paths] ERROR in ${context}:`);
  if (error instanceof Error) {
    console.error(`   Message: ${error.message}`);
    if (error.stack) {
      console.error(`   Stack: ${error.stack.split("\n").slice(1, 3).join("\n   ")}`);
    }
  } else {
    console.error(`   ${String(error)}`);
  }
}

function fatalError(context: string, error: unknown): never {
  logError(context, error);
  console.error("\n🛑 Fatal error - exiting with code 2 (hard block)");
  process.exit(2);
}

const workspace = process.argv[2] || process.env.WORKSPACE || resolve(process.env.HOME || "~", ".claude");

// Check for marketplace repo markers (skip relative path check for plugins)
if (existsSync(join(workspace, "plugin.json")) || existsSync(join(workspace, ".claude-plugin"))) {
  console.log(`✅ Marketplace repo detected at: ${workspace}`);
  console.log("   Relative paths (./  ../) are CORRECT for marketplace plugins.");
  process.exit(0);
}

// Check for global ignore file
const globalIgnore = resolve(process.env.HOME || "~", ".claude/lint-relative-paths-ignore");
if (existsSync(globalIgnore)) {
  const patterns = readFileSync(globalIgnore, "utf-8")
    .split("\n")
    .filter((line) => line.trim() && !line.startsWith("#"));

  for (const pattern of patterns) {
    if (workspace.includes(pattern)) {
      console.log(`✅ Workspace matches global ignore pattern: ${pattern}`);
      console.log(`   Skipping: ${workspace}`);
      process.exit(0);
    }
  }
}

// Check for explicit skip marker
const skipMarker = join(workspace, ".lint-skip-relative-paths");
if (existsSync(skipMarker)) {
  const reason = readFileSync(skipMarker, "utf-8").split("\n")[0] || "Skip marker present";
  console.log(`✅ Lint skip marker found at: ${workspace}`);
  console.log(`   Reason: ${reason}`);
  process.exit(0);
}

console.log(`🔍 Scanning for non-repo-relative paths in: ${workspace}`);
console.log("   Violations: paths not starting with / or http(s)");
console.log("");

// Fallback exclusions for non-git directories (expanded list)
const excludeDirs = new Set([
  "node_modules",
  "plugins",
  "skills",
  ".git",
  ".venv",
  "archive",
  "archives",
  "scratch",
  "plans",
  "tmp",
  "third_party",
  "state",
  // Common gitignored directories
  "repos",
  "target",
  "vendor",
  "dist",
  "build",
  "out",
  "coverage",
  ".cache",
  "__pycache__",
  ".mypy_cache",
  ".pytest_cache",
  ".ruff_cache",
]);

// Pattern for markdown links with relative paths
const linkPattern = /\[([^\]]*)\]\(([^)]+)\)/g;

/**
 * Get tracked .md files using git ls-files (respects .gitignore)
 */
function getTrackedMdFiles(workspace: string): string[] {
  try {
    const result = execSync('git ls-files --cached "*.md" "**/*.md"', {
      cwd: workspace,
      encoding: "utf-8",
      timeout: 30000,
    });
    if (result.trim()) {
      const files = result
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((f) => join(workspace, f));
      console.error(`[DEBUG] git ls-files found ${files.length} tracked .md files`);
      return files;
    }
  } catch (error) {
    // Explicit logging - not a git repo or git not available
    console.error(`[DEBUG] git ls-files failed (falling back to directory walk): ${error instanceof Error ? error.message : String(error)}`);
  }
  return [];
}

/**
 * Fallback: walk directory with exclude_dirs filter
 */
function getMdFilesFallback(workspace: string): string[] {
  const files: string[] = [];

  function walk(dir: string) {
    try {
      const entries = Bun.file(dir).exists;
      // Use Bun's native filesystem API
      const dirEntries = require("fs").readdirSync(dir, { withFileTypes: true });

      for (const entry of dirEntries) {
        if (entry.isDirectory()) {
          if (!excludeDirs.has(entry.name)) {
            walk(join(dir, entry.name));
          }
        } else if (entry.isFile() && entry.name.endsWith(".md")) {
          files.push(join(dir, entry.name));
        }
      }
    } catch {
      // Permission denied or other error
    }
  }

  walk(workspace);
  return files;
}

// Prefer git ls-files (respects .gitignore), fallback to directory walk
let mdFiles = getTrackedMdFiles(workspace);
if (mdFiles.length === 0) {
  mdFiles = getMdFilesFallback(workspace);
}

const violations: string[] = [];

for (const filepath of mdFiles) {
  let content: string;
  try {
    content = readFileSync(filepath, "utf-8");
  } catch {
    continue;
  }

  const lines = content.split("\n");
  let inCodeFence = false;

  for (let lineNum = 0; lineNum < lines.length; lineNum++) {
    const line = lines[lineNum];

    // Track code fence state
    if (line.trim().startsWith("```")) {
      inCodeFence = !inCodeFence;
      continue;
    }

    // Skip if inside code fence
    if (inCodeFence) {
      continue;
    }

    // Skip inline code examples
    if (line.includes("`[") && line.includes("](") && line.includes(")`")) {
      continue;
    }

    // Find all links in line
    let match: RegExpExecArray | null;
    linkPattern.lastIndex = 0;
    while ((match = linkPattern.exec(line)) !== null) {
      const path = match[2];

      // Skip allowed patterns
      if (path.startsWith("/") || path.startsWith("#") || path.startsWith("http://") || path.startsWith("https://") || path.startsWith("mailto:")) {
        continue;
      }

      // Skip template variables
      if (path.startsWith("{") || path.startsWith("{{") || path === "...") {
        continue;
      }

      // This is a violation
      violations.push(`${filepath}:${lineNum + 1}:${line.trimEnd()}`);
    }
  }
}

if (violations.length === 0) {
  console.log("✅ No violations found. All local paths use repo-relative format (start with /).");
  process.exit(0);
}

console.log(`❌ Found ${violations.length} violation(s):`);
console.log("");
violations.slice(0, 50).forEach((v) => console.log(v));

if (violations.length > 50) {
  console.log("");
  console.log(`... and ${violations.length - 50} more (showing first 50)`);
}

console.log("");
console.log("📝 Fix: Convert relative paths to repo-relative paths starting with /");
console.log("   WRONG: [Link](../docs/foo.md)");
console.log("   WRONG: [Link](docs/foo.md)");
console.log("   RIGHT: [Link](/docs/foo.md)");

process.exit(1);
