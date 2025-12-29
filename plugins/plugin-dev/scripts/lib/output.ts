/**
 * CLI output formatting and AskUserQuestion JSON generation
 *
 * Follows patterns from lint-relative-paths.ts for error handling
 * and output formatting.
 */

import { red, green, yellow, cyan, bold, dim } from "ansis";
import type {
  ValidationResult,
  SkillValidation,
  AskUserQuestion,
  AskUserQuestionPayload,
  Severity,
  LinkViolation,
  BashViolation,
} from "./types.js";

// ============================================================================
// Error Handling (following lint-relative-paths.ts pattern)
// ============================================================================

/**
 * Log error with context to stderr
 */
export function logError(context: string, error: unknown): void {
  console.error(`\n${red("ERROR")} [skill-validator] in ${context}:`);
  if (error instanceof Error) {
    console.error(`   Message: ${error.message}`);
    if (error.stack) {
      const stackLines = error.stack.split("\n").slice(1, 3);
      console.error(`   Stack: ${stackLines.join("\n   ")}`);
    }
  } else {
    console.error(`   ${String(error)}`);
  }
}

/**
 * Log fatal error and exit with code 2
 */
export function fatalError(context: string, error: unknown): never {
  logError(context, error);
  console.error(`\n${red("FATAL")} - exiting with code 2 (hard block)`);
  process.exit(2);
}

/**
 * Log debug message (only when DEBUG env is set)
 */
export function logDebug(message: string): void {
  if (process.env.DEBUG) {
    console.error(`${dim("[DEBUG]")} ${message}`);
  }
}

// ============================================================================
// Severity Formatting
// ============================================================================

/**
 * Format severity with appropriate color
 */
function formatSeverity(severity: Severity): string {
  switch (severity) {
    case "error":
      return red("ERROR");
    case "warning":
      return yellow("WARN");
    case "info":
      return cyan("INFO");
  }
}

/**
 * Get severity icon
 */
function severityIcon(severity: Severity): string {
  switch (severity) {
    case "error":
      return red("x");
    case "warning":
      return yellow("!");
    case "info":
      return cyan("i");
  }
}

// ============================================================================
// Validation Results Output
// ============================================================================

export interface PrintResultsOptions {
  showFix?: boolean;
  verbose?: boolean;
}

/**
 * Print validation results to console
 */
export function printResults(
  validation: SkillValidation,
  options: PrintResultsOptions = {}
): void {
  const { showFix = false, verbose = false } = options;

  console.log(`\n${"=".repeat(60)}`);
  console.log(bold(`Skill: ${validation.skillName || validation.skillPath}`));
  console.log(`${"=".repeat(60)}\n`);

  // Group results by status
  const passed = validation.results.filter((r) => r.passed);
  const errors = validation.results.filter(
    (r) => !r.passed && r.severity === "error"
  );
  const warnings = validation.results.filter(
    (r) => !r.passed && r.severity === "warning"
  );

  // Show passed checks (only in verbose mode)
  if (passed.length > 0 && verbose) {
    console.log(green("PASSED:"));
    for (const r of passed) {
      console.log(`   ${green("v")} ${dim(r.check)}: ${r.message}`);
    }
    console.log();
  }

  // Show warnings
  if (warnings.length > 0) {
    console.log(yellow("WARNINGS:"));
    for (const r of warnings) {
      console.log(`   ${yellow("!")} ${r.check}: ${r.message}`);
      if (showFix && r.fixSuggestion) {
        console.log(`      ${dim("Fix:")} ${r.fixSuggestion}`);
      }
    }
    console.log();
  }

  // Show errors
  if (errors.length > 0) {
    console.log(red("ERRORS:"));
    for (const r of errors) {
      console.log(`   ${red("x")} ${r.check}: ${r.message}`);
      if (showFix && r.fixSuggestion) {
        console.log(`      ${dim("Fix:")} ${r.fixSuggestion}`);
      }
    }
    console.log();
  }

  // Summary
  const total = validation.results.length;
  const passedCount = passed.length;
  const allPassed = errors.length === 0;

  console.log(`Summary: ${passedCount}/${total} checks passed`);
  if (allPassed) {
    console.log(green("Skill validation PASSED"));
  } else {
    console.log(red("Skill validation FAILED"));
  }
}

// ============================================================================
// Link Violation Output
// ============================================================================

/**
 * Print link violations in detail
 */
export function printLinkViolations(
  violations: LinkViolation[],
  skillPath: string
): void {
  if (violations.length === 0) {
    console.log(green("No link violations found."));
    return;
  }

  console.log(red(`Found ${violations.length} link violation(s):\n`));

  // Group by file
  const byFile = new Map<string, LinkViolation[]>();
  for (const v of violations) {
    const existing = byFile.get(v.filePath) || [];
    existing.push(v);
    byFile.set(v.filePath, existing);
  }

  for (const [filePath, fileViolations] of byFile) {
    // Show relative path from skill
    const relPath = filePath.replace(skillPath + "/", "");
    console.log(cyan(relPath));

    for (const v of fileViolations) {
      console.log(`   Line ${v.lineNumber}: [${v.linkText}](${v.linkUrl})`);
      if (v.suggestedFix) {
        console.log(`   ${dim("->")} ${v.suggestedFix}`);
      }
    }
    console.log();
  }

  // Policy explanation
  console.log(bold("Link Policy:"));
  console.log("  ALLOWED: ./relative/path.md, /docs/adr/*, /docs/design/*");
  console.log("  FORBIDDEN: /docs/guides/*, /plugins/*, any other /... paths");
  console.log("  FIX: Copy external files into skill's references/ directory");
}

// ============================================================================
// Bash Violation Output
// ============================================================================

/**
 * Print bash violations in detail
 */
export function printBashViolations(
  violations: BashViolation[],
  skillPath: string
): void {
  if (violations.length === 0) {
    console.log(green("No bash compatibility issues found."));
    return;
  }

  const errors = violations.filter((v) => v.severity === "error");
  const warnings = violations.filter((v) => v.severity === "warning");

  if (errors.length > 0) {
    console.log(red(`Found ${errors.length} bash error(s):\n`));
    for (const v of errors) {
      const relPath = v.filePath.replace(skillPath + "/", "");
      console.log(`   ${red("x")} ${relPath}:${v.lineNumber}: ${v.issue}`);
    }
    console.log();
  }

  if (warnings.length > 0) {
    console.log(yellow(`Found ${warnings.length} bash warning(s):\n`));
    for (const v of warnings) {
      const relPath = v.filePath.replace(skillPath + "/", "");
      console.log(`   ${yellow("!")} ${relPath}:${v.lineNumber}: ${v.issue}`);
    }
    console.log();
  }

  console.log(bold("Bash Compatibility:"));
  console.log("  Blocks with $(), [[, declare, local, function need heredoc wrapper:");
  console.log(`  ${dim("/usr/bin/env bash << 'EOF'")}`);
  console.log(`  ${dim("...bash code...")}`);
  console.log(`  ${dim("EOF")}`);
}

// ============================================================================
// AskUserQuestion JSON Generation
// ============================================================================

/**
 * Generate AskUserQuestion payload for interactive mode
 */
export function generateAskUserQuestions(
  validation: SkillValidation
): AskUserQuestionPayload {
  const questions: AskUserQuestion[] = [];

  const needsClarification = validation.results.filter(
    (r) =>
      r.needsClarification &&
      r.clarificationQuestion &&
      r.clarificationOptions &&
      r.clarificationOptions.length > 0
  );

  for (const r of needsClarification) {
    questions.push({
      question: r.clarificationQuestion!,
      header: formatHeader(r.check),
      options: r.clarificationOptions!.map((opt) => ({
        label: opt.split(" (")[0], // Extract label before any parenthetical
        description: opt,
      })),
      multiSelect: false,
    });
  }

  return { questions };
}

/**
 * Format check name as header (max 12 chars)
 */
function formatHeader(check: string): string {
  // Convert snake_case to Title Case and truncate
  const words = check.split("_");
  const titleCase = words
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
  return titleCase.slice(0, 12);
}

/**
 * Print AskUserQuestion JSON output
 */
export function printAskUserQuestions(validation: SkillValidation): void {
  const payload = generateAskUserQuestions(validation);

  if (payload.questions.length === 0) {
    return;
  }

  console.log(`\n${"=".repeat(60)}`);
  console.log("INTERACTIVE CLARIFICATION (AskUserQuestion format)");
  console.log(`${"=".repeat(60)}`);
  console.log("\nAskUserQuestion tool call:");
  console.log(JSON.stringify(payload, null, 2));
}

// ============================================================================
// Summary Output
// ============================================================================

/**
 * Print final validation summary
 */
export function printSummary(
  validations: SkillValidation[],
  options: { strict?: boolean } = {}
): void {
  const { strict = false } = options;

  let totalErrors = 0;
  let totalWarnings = 0;
  let totalPassed = 0;

  for (const v of validations) {
    totalErrors += v.results.filter(
      (r) => !r.passed && r.severity === "error"
    ).length;
    totalWarnings += v.results.filter(
      (r) => !r.passed && r.severity === "warning"
    ).length;
    totalPassed += v.results.filter((r) => r.passed).length;
  }

  console.log(`\n${"=".repeat(60)}`);
  console.log("VALIDATION SUMMARY");
  console.log(`${"=".repeat(60)}`);
  console.log(`Skills validated: ${validations.length}`);
  console.log(`Passed: ${totalPassed}`);
  console.log(`Errors: ${totalErrors}`);
  console.log(`Warnings: ${totalWarnings}`);
  console.log(`${"=".repeat(60)}`);

  if (totalErrors > 0) {
    console.log(`\n${red("VALIDATION FAILED")} - ${totalErrors} error(s) must be fixed`);
  } else if (totalWarnings > 0 && strict) {
    console.log(
      `\n${red("VALIDATION FAILED (strict mode)")} - ${totalWarnings} warning(s) must be fixed`
    );
  } else if (totalWarnings > 0) {
    console.log(`\n${yellow("VALIDATION PASSED WITH WARNINGS")} - ${totalWarnings} warning(s)`);
  } else {
    console.log(`\n${green("VALIDATION PASSED")} - All checks passed`);
  }
}
