#!/usr/bin/env bun
/**
 * validate-skill.ts - Comprehensive skill validator
 *
 * Validates skills against skill-architecture standards:
 * - YAML frontmatter (name, description, allowed-tools)
 * - Description format (TRIGGERS keyword, length)
 * - S1/S2/S3 conformance standards
 * - Link portability (STRICT: only /docs/adr/ and /docs/design/ allowed)
 * - Bash compatibility (heredoc wrapper for bash-specific syntax)
 *
 * Usage:
 *   bun run scripts/validate-skill.ts <path> [--fix] [--interactive] [-v]
 *
 * Exit codes:
 *   0 = All validations passed
 *   1 = Violations found (errors)
 *   2 = Fatal error (invalid path, no SKILL.md)
 *
 * ADR: /docs/adr/2025-12-28-skill-validator-typescript-migration.md
 */

import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import { join, resolve, basename, relative } from "path";
import { parseArgs } from "util";
import { Glob } from "bun";

import { parseMarkdown, extractLinks, extractBashBlocks, countLines } from "./lib/markdown.js";
import {
  SKILL_NAME,
  hasBashSpecificSyntax,
  hasHeredocWrapper,
  isDocExample,
} from "./lib/patterns.js";
import {
  ALLOWED_REPO_PATHS,
  MAX_DESCRIPTION_LENGTH,
  MAX_SKILL_LINES,
  REQUIRED_FRONTMATTER_FIELDS,
  SKIP_DIRECTORIES,
  isAllowedRepoPath,
  FILE_ENCODING,
  DESCRIPTION_LENGTH_OPTIONS,
  ALLOWED_TOOLS_OPTIONS,
  S2_COMPLIANCE_OPTIONS,
} from "./lib/constants.js";
import {
  printResults,
  printAskUserQuestions,
  printSummary,
  printLinkViolations,
  printBashViolations,
  logError,
  fatalError,
  logDebug,
} from "./lib/output.js";
import type {
  ValidationResult,
  SkillValidation,
  SkillFrontmatter,
  LinkViolation,
  BashViolation,
  ExitCode,
} from "./lib/types.js";

// ============================================================================
// CLI Argument Parsing
// ============================================================================

const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    fix: { type: "boolean", default: false },
    interactive: { type: "boolean", default: false },
    verbose: { type: "boolean", short: "v", default: false },
    strict: { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
  allowPositionals: true,
});

if (values.help) {
  console.log(`
Usage: bun run validate-skill.ts <path> [options]

Arguments:
  path              Path to skill directory, SKILL.md, or plugin directory

Options:
  --fix             Show fix suggestions for violations
  --interactive     Generate AskUserQuestion JSON for clarifications
  -v, --verbose     Show all checks including passed ones
  --strict          Treat warnings as errors
  -h, --help        Show this help message

Exit codes:
  0  All validations passed
  1  Violations found (errors)
  2  Fatal error (invalid path, parse error)
`);
  process.exit(0);
}

// ============================================================================
// Frontmatter Validation
// ============================================================================

function validateFrontmatter(
  frontmatter: SkillFrontmatter | null,
  frontmatterError: string
): ValidationResult[] {
  const results: ValidationResult[] = [];

  // Check frontmatter exists
  if (frontmatterError) {
    results.push({
      check: "yaml_frontmatter",
      passed: false,
      message: frontmatterError,
      severity: "error",
      fixSuggestion: "Add YAML frontmatter:\n---\nname: skill-name\ndescription: Description. TRIGGERS - keyword1, keyword2.\n---",
    });
    return results;
  }

  if (!frontmatter) {
    results.push({
      check: "yaml_frontmatter",
      passed: false,
      message: "No frontmatter found",
      severity: "error",
    });
    return results;
  }

  results.push({
    check: "yaml_frontmatter",
    passed: true,
    message: "Valid YAML frontmatter found",
    severity: "info",
  });

  // Check required fields
  if (!frontmatter.name) {
    results.push({
      check: "yaml_name",
      passed: false,
      message: "Missing required 'name' field in frontmatter",
      severity: "error",
      fixSuggestion: "Add 'name: your-skill-name' to frontmatter",
    });
  } else {
    // Validate name format
    if (!SKILL_NAME.test(frontmatter.name)) {
      results.push({
        check: "yaml_name_format",
        passed: false,
        message: `Invalid skill name format: '${frontmatter.name}'. Must be lowercase letters, numbers, and hyphens only.`,
        severity: "error",
        fixSuggestion: `Use format: ${frontmatter.name.toLowerCase().replace(/[^a-z0-9-]/g, "-")}`,
      });
    } else {
      results.push({
        check: "yaml_name",
        passed: true,
        message: `Skill name: ${frontmatter.name}`,
        severity: "info",
      });
    }
  }

  // Check description
  if (!frontmatter.description) {
    results.push({
      check: "yaml_description",
      passed: false,
      message: "Missing required 'description' field in frontmatter",
      severity: "error",
      fixSuggestion: "Add 'description: Brief description. TRIGGERS - keyword1, keyword2.'",
    });
  } else {
    results.push({
      check: "yaml_description",
      passed: true,
      message: "Description field present",
      severity: "info",
    });

    // Check description length
    if (frontmatter.description.length > MAX_DESCRIPTION_LENGTH) {
      results.push({
        check: "description_length",
        passed: false,
        message: `Description exceeds ${MAX_DESCRIPTION_LENGTH} characters (${frontmatter.description.length} chars)`,
        severity: "warning",
        fixSuggestion: `Trim to ${MAX_DESCRIPTION_LENGTH} characters`,
        needsClarification: true,
        clarificationQuestion: `Description exceeds ${MAX_DESCRIPTION_LENGTH} chars. How should we handle this?`,
        clarificationOptions: DESCRIPTION_LENGTH_OPTIONS,
      });
    }

    // Check for TRIGGERS keyword
    if (!/triggers/i.test(frontmatter.description)) {
      results.push({
        check: "description_triggers",
        passed: false,
        message: "Description missing 'TRIGGERS' keyword for discoverability",
        severity: "warning",
        fixSuggestion: "Add 'TRIGGERS - keyword1, keyword2.' to description",
      });
    }
  }

  // Check allowed-tools (recommended)
  if (!frontmatter["allowed-tools"]) {
    results.push({
      check: "allowed_tools",
      passed: false,
      message: "Missing 'allowed-tools' field (security recommendation)",
      severity: "warning",
      fixSuggestion: "Add 'allowed-tools: [Read, Grep, Glob]' to limit tool access",
      needsClarification: true,
      clarificationQuestion: "No allowed-tools specified. What tools should this skill access?",
      clarificationOptions: ALLOWED_TOOLS_OPTIONS,
    });
  } else {
    results.push({
      check: "allowed_tools",
      passed: true,
      message: "allowed-tools specified",
      severity: "info",
    });
  }

  return results;
}

// ============================================================================
// Structure Validation
// ============================================================================

function validateStructure(skillPath: string, content: string): ValidationResult[] {
  const results: ValidationResult[] = [];

  // Check SKILL.md exists (already verified before calling this)
  results.push({
    check: "skill_md_exists",
    passed: true,
    message: "SKILL.md found",
    severity: "info",
  });

  // Count lines
  const lineCount = countLines(content);
  const hasReferences = existsSync(join(skillPath, "references"));

  if (lineCount > MAX_SKILL_LINES) {
    if (hasReferences) {
      // S2 compliant - progressive disclosure
      results.push({
        check: "s2_progressive_disclosure",
        passed: true,
        message: `SKILL.md is ${lineCount} lines with references/ directory (S2 compliant)`,
        severity: "info",
      });
    } else {
      // S1 violation
      results.push({
        check: "s1_line_count",
        passed: false,
        message: `SKILL.md exceeds ${MAX_SKILL_LINES} lines (${lineCount} lines) without references/ directory`,
        severity: "warning",
        fixSuggestion: "Create references/ directory and move detailed content there",
        needsClarification: true,
        clarificationQuestion: `SKILL.md is ${lineCount} lines without references/. How to proceed?`,
        clarificationOptions: S2_COMPLIANCE_OPTIONS,
      });
    }
  } else {
    results.push({
      check: "s1_line_count",
      passed: true,
      message: `SKILL.md is ${lineCount} lines (within S1 limit)`,
      severity: "info",
    });
  }

  return results;
}

// ============================================================================
// Link Validation
// ============================================================================

async function validateLinks(
  skillPath: string
): Promise<{ results: ValidationResult[]; violations: LinkViolation[] }> {
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

  // Scan each file
  for (const filePath of mdFiles) {
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
              suggestedFix: "Use relative path (./) or allowed repo path (/docs/adr/, /docs/design/)",
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
              suggestedFix: suggestLinkFix(url),
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
          suggestedFix: `Use explicit relative path: ./${url}`,
        });
      }
    } catch (err) {
      logDebug(`Could not read ${filePath}: ${err}`);
    }
  }

  // Create summary result
  if (violations.length === 0) {
    results.push({
      check: "link_portability",
      passed: true,
      message: "All links use appropriate path formats",
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
      message: `Found ${violations.length} link violation(s): ${parts.join(", ")}`,
      severity: "error",
      fixSuggestion: "Only /docs/adr/ and /docs/design/ allowed. Copy other files to references/",
    });
  }

  return { results, violations };
}

/**
 * Suggest fix for a link violation
 */
function suggestLinkFix(url: string): string {
  if (url.startsWith("/docs/") && !isAllowedRepoPath(url)) {
    const filename = url.split("/").pop();
    return `Copy to references/${filename} and use ./references/${filename}`;
  }

  const filename = url.split("/").pop();
  return `Copy file to skill directory: ./references/${filename}`;
}

// ============================================================================
// Bash Validation
// ============================================================================

function validateBashBlocks(
  skillPath: string
): { results: ValidationResult[]; violations: BashViolation[] } {
  const violations: BashViolation[] = [];
  const results: ValidationResult[] = [];

  // Find all markdown files
  const mdFiles: string[] = [];

  function walkDir(dir: string): void {
    try {
      const entries = readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory() && !SKIP_DIRECTORIES.has(entry.name)) {
          walkDir(join(dir, entry.name));
        } else if (entry.isFile() && entry.name.endsWith(".md")) {
          mdFiles.push(join(dir, entry.name));
        }
      }
    } catch {
      // Continue silently
    }
  }

  walkDir(skillPath);

  // Scan each file for bash blocks
  for (const filePath of mdFiles) {
    try {
      const content = readFileSync(filePath, FILE_ENCODING);
      const bashBlocks = extractBashBlocks(content);

      for (const block of bashBlocks) {
        // Skip documentation examples
        if (isDocExample(block.text)) {
          continue;
        }

        // Check if needs wrapper
        if (hasBashSpecificSyntax(block.text) && !hasHeredocWrapper(block.text)) {
          violations.push({
            filePath,
            lineNumber: block.lineNumber,
            issue: "Bash block contains bash-specific syntax without heredoc wrapper",
            severity: "error",
            pattern: detectBashPattern(block.text),
          });
        }

        // Check for grep -P (warning only)
        if (/grep\s+[^|]*-[a-zA-Z]*P/.test(block.text)) {
          violations.push({
            filePath,
            lineNumber: block.lineNumber,
            issue: "grep -P (Perl regex) is not portable - use grep -E with awk instead",
            severity: "warning",
            pattern: "grep -P",
          });
        }
      }
    } catch (err) {
      logDebug(`Could not read ${filePath}: ${err}`);
    }
  }

  // Create summary result
  const errors = violations.filter((v) => v.severity === "error");
  const warnings = violations.filter((v) => v.severity === "warning");

  if (errors.length === 0) {
    results.push({
      check: "bash_compatibility",
      passed: true,
      message: "All bash blocks properly wrapped for zsh compatibility",
      severity: "info",
    });
  } else {
    results.push({
      check: "bash_compatibility",
      passed: false,
      message: `Found ${errors.length} bash block(s) without heredoc wrapper`,
      severity: "error",
      fixSuggestion: "Wrap with: /usr/bin/env bash << 'EOF'\\n...\\nEOF",
    });
  }

  if (warnings.length > 0) {
    results.push({
      check: "bash_portability",
      passed: false,
      message: `Found ${warnings.length} bash portability warning(s)`,
      severity: "warning",
    });
  }

  return { results, violations };
}

/**
 * Detect which bash pattern triggered the violation
 */
function detectBashPattern(block: string): string {
  if (/\$\([^)]+\)/.test(block)) return "$(...)";
  if (/\[\[/.test(block)) return "[[...]]";
  if (/^\s*declare\s/m.test(block)) return "declare";
  if (/^\s*local\s/m.test(block)) return "local";
  if (/^\s*function\s/m.test(block)) return "function";
  if (/\$\{[^}]+\}/.test(block)) return "${...}";
  return "bash-specific syntax";
}

// ============================================================================
// Main Validation
// ============================================================================

async function validateSkill(skillPath: string): Promise<SkillValidation> {
  const validation: SkillValidation = {
    skillPath,
    skillName: "",
    results: [],
    linkViolations: [],
    bashViolations: [],
  };

  const skillMdPath = join(skillPath, "SKILL.md");
  if (!existsSync(skillMdPath)) {
    validation.results.push({
      check: "skill_md_exists",
      passed: false,
      message: `SKILL.md not found at ${skillPath}`,
      severity: "error",
    });
    return validation;
  }

  const content = readFileSync(skillMdPath, FILE_ENCODING);
  const parsed = parseMarkdown(content);

  if (parsed.frontmatter?.name) {
    validation.skillName = parsed.frontmatter.name;
  } else {
    validation.skillName = basename(skillPath);
  }

  // Run all validators
  validation.results.push(
    ...validateFrontmatter(parsed.frontmatter, parsed.frontmatterError)
  );
  validation.results.push(...validateStructure(skillPath, content));

  const linkResults = await validateLinks(skillPath);
  validation.results.push(...linkResults.results);
  validation.linkViolations = linkResults.violations;

  const bashResults = validateBashBlocks(skillPath);
  validation.results.push(...bashResults.results);
  validation.bashViolations = bashResults.violations;

  return validation;
}

// ============================================================================
// Entry Point
// ============================================================================

async function main(): Promise<void> {
  if (positionals.length < 1) {
    console.log("Usage: bun run validate-skill.ts <path> [--fix] [--interactive] [-v]");
    console.log("Run with --help for more options.");
    process.exit(2);
  }

  const inputPath = resolve(positionals[0]);

  if (!existsSync(inputPath)) {
    fatalError("path resolution", new Error(`Path not found: ${inputPath}`));
  }

  // Determine skill path(s)
  let skillPaths: string[] = [];

  const stat = statSync(inputPath);

  if (stat.isFile() && basename(inputPath) === "SKILL.md") {
    // Direct SKILL.md file
    skillPaths = [resolve(inputPath, "..")];
  } else if (stat.isDirectory() && existsSync(join(inputPath, "SKILL.md"))) {
    // Skill directory
    skillPaths = [inputPath];
  } else if (stat.isDirectory() && existsSync(join(inputPath, "skills"))) {
    // Plugin directory - validate all skills
    const skillsDir = join(inputPath, "skills");
    for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        const skillDir = join(skillsDir, entry.name);
        if (existsSync(join(skillDir, "SKILL.md"))) {
          skillPaths.push(skillDir);
        }
      }
    }
  } else {
    fatalError("path resolution", new Error(`No SKILL.md found at ${inputPath}`));
  }

  if (skillPaths.length === 0) {
    fatalError("path resolution", new Error(`No skills found to validate at ${inputPath}`));
  }

  // Validate all skills
  const validations: SkillValidation[] = [];

  for (const skillPath of skillPaths) {
    const validation = await validateSkill(skillPath);
    validations.push(validation);

    printResults(validation, { showFix: values.fix, verbose: values.verbose });

    if (validation.linkViolations.length > 0 && values.verbose) {
      console.log();
      printLinkViolations(validation.linkViolations, validation.skillPath);
    }

    if (validation.bashViolations.length > 0 && values.verbose) {
      console.log();
      printBashViolations(validation.bashViolations, validation.skillPath);
    }

    if (values.interactive) {
      printAskUserQuestions(validation);
    }
  }

  // Print summary for multiple skills
  if (validations.length > 1) {
    printSummary(validations, { strict: values.strict });
  }

  // Determine exit code
  let hasErrors = false;
  let hasWarnings = false;

  for (const v of validations) {
    if (v.results.some((r) => !r.passed && r.severity === "error")) {
      hasErrors = true;
    }
    if (v.results.some((r) => !r.passed && r.severity === "warning")) {
      hasWarnings = true;
    }
  }

  if (hasErrors) {
    process.exit(1);
  } else if (hasWarnings && values.strict) {
    process.exit(1);
  } else {
    process.exit(0);
  }
}

main().catch((err) => {
  fatalError("main execution", err);
});
