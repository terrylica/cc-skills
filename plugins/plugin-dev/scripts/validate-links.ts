#!/usr/bin/env bun
/**
 * validate-links.ts - Link portability validator with STRICT policy
 *
 * CRITICAL POLICY:
 *   Only /docs/adr/ and /docs/design/ paths are allowed as external references.
 *   ALL other external paths are ERRORS - files must be moved into skill directory.
 *
 * Usage:
 *   bun run scripts/validate-links.ts <skill-path>
 *
 * Exit codes:
 *   0 = All links valid
 *   1 = Link violations found
 *   2 = Fatal error
 *
 * ADR: /docs/adr/2025-12-28-skill-validator-typescript-migration.md
 */

import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import { join, resolve, relative, basename } from "path";
import { Glob } from "bun";
import { red, green, yellow, cyan, bold, dim } from "ansis";

import { extractLinks } from "./lib/markdown.js";
import { SKIP_DIRECTORIES, isAllowedRepoPath, FILE_ENCODING, ALLOWED_REPO_PATHS } from "./lib/constants.js";
import { logError, fatalError, logDebug } from "./lib/output.js";
import type { LinkViolation, ValidationResult } from "./lib/types.js";

// ============================================================================
// Link Validation
// ============================================================================

/**
 * Suggest fix for a link violation
 */
function suggestLinkFix(url: string, violationType: string): string {
  if (violationType === "github_url") {
    return "Use relative path (./) or allowed repo path (/docs/adr/, /docs/design/)";
  }

  if (url.startsWith("/docs/") && !isAllowedRepoPath(url)) {
    const filename = url.split("/").pop();
    return `Copy to references/${filename} and use ./references/${filename}`;
  }

  if (url.startsWith("/")) {
    const filename = url.split("/").pop();
    return `Copy file to skill directory: ./references/${filename}`;
  }

  return `Use explicit relative path: ./${url}`;
}

/**
 * Scan a single file for link violations
 */
function scanFile(filePath: string, skillPath: string): LinkViolation[] {
  const violations: LinkViolation[] = [];

  try {
    const content = readFileSync(filePath, FILE_ENCODING);
    const links = extractLinks(content);

    for (const link of links) {
      const url = link.href;

      // Skip allowed patterns
      if (
        url.startsWith("./") ||
        url.startsWith("../") ||
        url.startsWith("#") ||
        url.startsWith("http://") ||
        url.startsWith("https://") ||
        url.startsWith("mailto:") ||
        url.startsWith("{") ||
        url.startsWith("{{")
      ) {
        // Check for GitHub URLs to this repo
        if (/github\.com\/terrylica\/cc-skills\/blob\//.test(url)) {
          violations.push({
            filePath,
            lineNumber: link.lineNumber,
            column: link.column,
            linkText: link.text,
            linkUrl: url,
            violationType: "github_url",
            suggestedFix: suggestLinkFix(url, "github_url"),
          });
        }
        continue;
      }

      // Check repo-relative paths (starting with /)
      if (url.startsWith("/")) {
        if (!isAllowedRepoPath(url)) {
          violations.push({
            filePath,
            lineNumber: link.lineNumber,
            column: link.column,
            linkText: link.text,
            linkUrl: url,
            violationType: "forbidden_path",
            suggestedFix: suggestLinkFix(url, "forbidden_path"),
          });
        }
        continue;
      }

      // Bare paths (no leading ./ or /) - violation
      violations.push({
        filePath,
        lineNumber: link.lineNumber,
        column: link.column,
        linkText: link.text,
        linkUrl: url,
        violationType: "bare_path",
        suggestedFix: suggestLinkFix(url, "bare_path"),
      });
    }
  } catch (err) {
    logDebug(`Could not read ${filePath}: ${err}`);
  }

  return violations;
}

/**
 * Scan all markdown files in skill directory
 */
async function validateLinks(skillPath: string): Promise<{
  results: ValidationResult[];
  violations: LinkViolation[];
}> {
  const violations: LinkViolation[] = [];
  const results: ValidationResult[] = [];

  // Find all markdown files
  const glob = new Glob("**/*.md");
  const mdFiles: string[] = [];

  for await (const file of glob.scan({ cwd: skillPath, absolute: true })) {
    const relativePath = relative(skillPath, file);
    const firstDir = relativePath.split("/")[0];
    if (!SKIP_DIRECTORIES.has(firstDir)) {
      mdFiles.push(file);
    }
  }

  if (mdFiles.length === 0) {
    results.push({
      check: "link_scan",
      passed: true,
      message: "No markdown files found to scan",
      severity: "info",
    });
    return { results, violations };
  }

  // Scan each file
  for (const file of mdFiles) {
    const fileViolations = scanFile(file, skillPath);
    violations.push(...fileViolations);
  }

  // Create summary result
  if (violations.length === 0) {
    results.push({
      check: "link_portability",
      passed: true,
      message: `Scanned ${mdFiles.length} files - all links valid`,
      severity: "info",
    });
  } else {
    const forbiddenCount = violations.filter((v) => v.violationType === "forbidden_path").length;
    const githubCount = violations.filter((v) => v.violationType === "github_url").length;
    const bareCount = violations.filter((v) => v.violationType === "bare_path").length;

    const parts = [];
    if (forbiddenCount > 0) parts.push(`${forbiddenCount} forbidden paths`);
    if (githubCount > 0) parts.push(`${githubCount} GitHub URLs`);
    if (bareCount > 0) parts.push(`${bareCount} bare paths`);

    results.push({
      check: "link_portability",
      passed: false,
      message: `Found ${violations.length} violation(s): ${parts.join(", ")}`,
      severity: "error",
    });
  }

  return { results, violations };
}

// ============================================================================
// Output Formatting
// ============================================================================

function printViolations(violations: LinkViolation[], skillPath: string): void {
  // Group by file
  const byFile = new Map<string, LinkViolation[]>();
  for (const v of violations) {
    const existing = byFile.get(v.filePath) || [];
    existing.push(v);
    byFile.set(v.filePath, existing);
  }

  for (const [filePath, fileViolations] of byFile) {
    const relPath = relative(skillPath, filePath);
    console.log(cyan(relPath));

    for (const v of fileViolations) {
      console.log(`   Line ${v.lineNumber}: [${v.linkText}](${v.linkUrl})`);
      console.log(`   ${dim("->")} ${v.suggestedFix}`);
    }
    console.log();
  }
}

// ============================================================================
// Entry Point
// ============================================================================

async function main(): Promise<void> {
  const path = Bun.argv[2];

  if (!path || path === "--help" || path === "-h") {
    console.log(`
Usage: bun run validate-links.ts <skill-path>

Arguments:
  skill-path    Path to skill directory or plugin directory

Examples:
  bun run validate-links.ts ~/.claude/skills/my-skill/
  bun run validate-links.ts plugins/my-plugin/skills/my-skill/
  bun run validate-links.ts .

Exit codes:
  0  All links valid
  1  Link violations found
  2  Fatal error

Link Policy:
  ALLOWED:    ./relative/path.md, /docs/adr/*, /docs/design/*
  FORBIDDEN:  /docs/guides/*, /plugins/*, any other /... paths
  FIX:        Copy external files into skill's references/ directory
`);
    process.exit(path === "--help" || path === "-h" ? 0 : 2);
  }

  const skillPath = resolve(path);

  if (!existsSync(skillPath)) {
    fatalError("path resolution", new Error(`Path not found: ${skillPath}`));
  }

  // Check if it's a skill directory
  let skillPaths: string[] = [];

  const stat = statSync(skillPath);

  if (stat.isDirectory()) {
    if (existsSync(join(skillPath, "SKILL.md"))) {
      // Single skill
      skillPaths = [skillPath];
    } else if (existsSync(join(skillPath, "skills"))) {
      // Plugin directory
      const skillsDir = join(skillPath, "skills");
      for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
        if (entry.isDirectory() && existsSync(join(skillsDir, entry.name, "SKILL.md"))) {
          skillPaths.push(join(skillsDir, entry.name));
        }
      }
    } else {
      // Just scan the directory as-is
      skillPaths = [skillPath];
    }
  } else {
    fatalError("path resolution", new Error(`Path is not a directory: ${skillPath}`));
  }

  if (skillPaths.length === 0) {
    console.log(yellow("No skill directories found to scan."));
    process.exit(0);
  }

  let totalViolations = 0;

  for (const sp of skillPaths) {
    console.log(`\n${bold("Scanning:")} ${sp}\n`);

    const { results, violations } = await validateLinks(sp);
    totalViolations += violations.length;

    if (violations.length === 0) {
      console.log(green("All links valid."));
    } else {
      console.log(red(`Found ${violations.length} violation(s):\n`));
      printViolations(violations, sp);
    }
  }

  // Policy reminder
  console.log(bold("\nLink Policy:"));
  console.log(`  ALLOWED:   ${green("./relative/path.md")}, ${green("/docs/adr/*")}, ${green("/docs/design/*")}`);
  console.log(`  FORBIDDEN: ${red("/docs/guides/*")}, ${red("/plugins/*")}, ${red("any other /... paths")}`);
  console.log(`  FIX:       Copy external files into skill's ${cyan("references/")} directory`);

  process.exit(totalViolations > 0 ? 1 : 0);
}

main().catch((err) => {
  fatalError("main execution", err);
});
