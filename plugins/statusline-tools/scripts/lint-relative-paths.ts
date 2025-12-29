#!/usr/bin/env bun
/**
 * lint-relative-paths.ts - Lint markdown files for non-repo-relative local paths
 *
 * Uses well-maintained OSS packages:
 * - simple-git: Git operations (respects .gitignore via git ls-files)
 * - remark-parse + unified: Markdown parsing with mdast
 * - unist-util-visit: AST traversal for link extraction
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
 *   - Template variables: {{var}}, {var}
 *
 * Exit codes:
 *   0 - Success (no violations or skip condition met)
 *   1 - Violations found (lint failure)
 *   2 - Hard block / fatal error (Claude Code hook protocol)
 */

import { existsSync, readFileSync, readdirSync } from "fs";
import { join, resolve } from "path";
import { simpleGit, type SimpleGit } from "simple-git";
import { unified } from "unified";
import remarkParse from "remark-parse";
import { visit } from "unist-util-visit";
import type { Link, LinkReference } from "mdast";

// ============================================================================
// Error Handling - Explicit and verbose for Claude Code CLI
// ============================================================================

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

function logDebug(message: string): void {
  // Debug output goes to stderr so it doesn't interfere with stdout parsing
  console.error(`[DEBUG] ${message}`);
}

// ============================================================================
// Configuration
// ============================================================================

const workspace = process.argv[2] || process.env.WORKSPACE || resolve(process.env.HOME || "~", ".claude");

// Fallback exclusions for non-git directories (expanded list)
const EXCLUDE_DIRS = new Set([
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

// Path patterns to exclude from scanning (applies to both git ls-files and fallback)
// Project-local skills use relative paths like marketplace plugins
const EXCLUDE_PATH_PATTERNS = [
  /\.claude\/skills\//,  // Project-local skills: relative paths are correct
  /\.claude\/commands\//, // Project-local commands: relative paths are correct
];

// ============================================================================
// Skip Conditions (checked before any scanning)
// ============================================================================

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

// ============================================================================
// Git Integration (using simple-git)
// ============================================================================

/**
 * Check if a file path matches any exclusion pattern
 */
function shouldExcludePath(filepath: string): boolean {
  return EXCLUDE_PATH_PATTERNS.some((pattern) => pattern.test(filepath));
}

/**
 * Get tracked .md files using simple-git (respects .gitignore)
 */
async function getTrackedMdFiles(workspace: string): Promise<string[]> {
  try {
    const git: SimpleGit = simpleGit(workspace);

    // Check if this is a git repository
    const isRepo = await git.checkIsRepo();
    if (!isRepo) {
      logDebug("Not a git repository, falling back to directory walk");
      return [];
    }

    // Use git ls-files to get tracked markdown files
    const result = await git.raw(["ls-files", "--cached", "*.md", "**/*.md"]);

    if (result.trim()) {
      const allFiles = result
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((f) => join(workspace, f));

      // Filter out excluded paths (e.g., .claude/skills/)
      const files = allFiles.filter((f) => !shouldExcludePath(f));

      const excluded = allFiles.length - files.length;
      if (excluded > 0) {
        logDebug(`Excluded ${excluded} files matching EXCLUDE_PATH_PATTERNS`);
      }

      logDebug(`simple-git found ${files.length} tracked .md files`);
      return files;
    }
  } catch (error) {
    logDebug(`simple-git failed: ${error instanceof Error ? error.message : String(error)}`);
  }
  return [];
}

/**
 * Fallback: walk directory with exclude_dirs filter
 */
function getMdFilesFallback(workspace: string): string[] {
  const files: string[] = [];

  function walk(dir: string): void {
    try {
      const entries = readdirSync(dir, { withFileTypes: true });

      for (const entry of entries) {
        if (entry.isDirectory()) {
          if (!EXCLUDE_DIRS.has(entry.name)) {
            walk(join(dir, entry.name));
          }
        } else if (entry.isFile() && entry.name.endsWith(".md")) {
          const filepath = join(dir, entry.name);
          // Apply same path exclusion as git ls-files
          if (!shouldExcludePath(filepath)) {
            files.push(filepath);
          }
        }
      }
    } catch {
      // Permission denied or other error - continue silently
    }
  }

  walk(workspace);
  logDebug(`Directory walk found ${files.length} .md files`);
  return files;
}

// ============================================================================
// Markdown Link Extraction (using remark + mdast)
// ============================================================================

interface LinkViolation {
  file: string;
  line: number;
  column: number;
  url: string;
  text: string;
}

/**
 * Extract non-compliant links from markdown content using remark
 */
function extractViolations(filepath: string, content: string): LinkViolation[] {
  const violations: LinkViolation[] = [];

  try {
    const tree = unified().use(remarkParse).parse(content);

    // Visit all link nodes in the AST
    visit(tree, "link", (node: Link) => {
      const url = node.url;

      // Skip allowed patterns
      if (
        url.startsWith("/") ||
        url.startsWith("#") ||
        url.startsWith("http://") ||
        url.startsWith("https://") ||
        url.startsWith("mailto:")
      ) {
        return;
      }

      // Skip template variables
      if (url.startsWith("{") || url.startsWith("{{") || url === "...") {
        return;
      }

      // This is a violation
      const position = node.position;
      violations.push({
        file: filepath,
        line: position?.start.line ?? 0,
        column: position?.start.column ?? 0,
        url: url,
        text: node.children.map((c) => ("value" in c ? c.value : "")).join(""),
      });
    });

    // Also check link references (though these are less common)
    visit(tree, "linkReference", (node: LinkReference) => {
      // Link references use definitions, which should also be repo-relative
      // For now, we skip these as they're handled differently
    });
  } catch (error) {
    logError(`parsing ${filepath}`, error);
  }

  return violations;
}

// ============================================================================
// Main Execution
// ============================================================================

async function main(): Promise<void> {
  console.log(`🔍 Scanning for non-repo-relative paths in: ${workspace}`);
  console.log("   Violations: paths not starting with / or http(s)");
  console.log("");

  // Get markdown files (prefer git ls-files, fallback to directory walk)
  let mdFiles = await getTrackedMdFiles(workspace);
  if (mdFiles.length === 0) {
    mdFiles = getMdFilesFallback(workspace);
  }

  if (mdFiles.length === 0) {
    console.log("⚠️ No markdown files found to scan");
    process.exit(0);
  }

  // Scan all files for violations
  const allViolations: LinkViolation[] = [];

  for (const filepath of mdFiles) {
    try {
      const content = readFileSync(filepath, "utf-8");
      const violations = extractViolations(filepath, content);
      allViolations.push(...violations);
    } catch (error) {
      // File read error - log but continue
      logDebug(`Could not read ${filepath}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  // Report results
  if (allViolations.length === 0) {
    console.log("✅ No violations found. All local paths use repo-relative format (start with /).");
    process.exit(0);
  }

  console.log(`❌ Found ${allViolations.length} violation(s):`);
  console.log("");

  // Show first 50 violations
  for (const v of allViolations.slice(0, 50)) {
    console.log(`${v.file}:${v.line}:${v.column}: [${v.text}](${v.url})`);
  }

  if (allViolations.length > 50) {
    console.log("");
    console.log(`... and ${allViolations.length - 50} more (showing first 50)`);
  }

  console.log("");
  console.log("📝 Fix: Convert relative paths to repo-relative paths starting with /");
  console.log("   WRONG: [Link](../docs/foo.md)");
  console.log("   WRONG: [Link](docs/foo.md)");
  console.log("   RIGHT: [Link](/docs/foo.md)");

  process.exit(1);
}

// Run main with error handling
main().catch((error) => {
  fatalError("main execution", error);
});
