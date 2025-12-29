/**
 * Core type definitions for skill validation
 *
 * Ports Python dataclasses from validate_skill.py and validate_links.py
 * to TypeScript interfaces for Bun/TypeScript validators.
 *
 * ADR: /docs/adr/2025-12-28-skill-validator-typescript-migration.md
 */

// ============================================================================
// Severity and Exit Codes
// ============================================================================

/** Severity levels for validation results */
export type Severity = "error" | "warning" | "info";

/** Exit codes following Claude Code CLI convention */
export enum ExitCode {
  /** All validations passed */
  Success = 0,
  /** Violations found (errors) */
  ValidationFailed = 1,
  /** Fatal error (invalid path, parse error) */
  FatalError = 2,
}

// ============================================================================
// Validation Result Types
// ============================================================================

/** Result of a single validation check */
export interface ValidationResult {
  /** Unique check identifier (e.g., 'yaml_name', 'link_portability') */
  check: string;
  /** Whether the check passed */
  passed: boolean;
  /** Human-readable message */
  message: string;
  /** Severity level (default: 'error') */
  severity: Severity;
  /** Optional fix suggestion */
  fixSuggestion?: string;
  /** Whether this needs user clarification */
  needsClarification?: boolean;
  /** Question to ask user if clarification needed */
  clarificationQuestion?: string;
  /** Options for clarification (labels) */
  clarificationOptions?: string[];
}

/** Link violation details */
export interface LinkViolation {
  /** Absolute path to file containing violation */
  filePath: string;
  /** Line number (1-indexed) */
  lineNumber: number;
  /** Column number (1-indexed) */
  column: number;
  /** Link display text */
  linkText: string;
  /** Link URL/path */
  linkUrl: string;
  /** Type of violation */
  violationType: "forbidden_path" | "absolute_non_docs" | "github_url" | "bare_path";
  /** Suggested fix */
  suggestedFix?: string;
}

/** Bash compatibility violation */
export interface BashViolation {
  /** Absolute path to file */
  filePath: string;
  /** Line number (1-indexed) */
  lineNumber: number;
  /** Issue description */
  issue: string;
  /** Severity (error for unwrapped blocks, warning for patterns like grep -P) */
  severity: Severity;
  /** Pattern that triggered the violation */
  pattern?: string;
}

// ============================================================================
// Skill Validation Types
// ============================================================================

/** Parsed YAML frontmatter from SKILL.md */
export interface SkillFrontmatter {
  name?: string;
  description?: string;
  "allowed-tools"?: string | string[];
  [key: string]: unknown;
}

/** Complete skill validation results */
export interface SkillValidation {
  /** Absolute path to skill directory */
  skillPath: string;
  /** Skill name from frontmatter or directory name */
  skillName: string;
  /** All validation results */
  results: ValidationResult[];
  /** Detailed link violations */
  linkViolations: LinkViolation[];
  /** Detailed bash violations */
  bashViolations: BashViolation[];
}

// ============================================================================
// AskUserQuestion Types (Claude Code CLI integration)
// ============================================================================

/** Single option for AskUserQuestion */
export interface AskUserOption {
  label: string;
  description: string;
}

/** AskUserQuestion format for Claude Code CLI */
export interface AskUserQuestion {
  question: string;
  header: string;
  options: AskUserOption[];
  multiSelect: boolean;
}

/** Container for multiple questions */
export interface AskUserQuestionPayload {
  questions: AskUserQuestion[];
}

// ============================================================================
// Utility Types
// ============================================================================

/** Result of link validation scan */
export interface LinkValidationResult {
  results: ValidationResult[];
  violations: LinkViolation[];
}

/** Result of bash validation scan */
export interface BashValidationResult {
  results: ValidationResult[];
  violations: BashViolation[];
}

/** Parsed markdown document */
export interface ParsedMarkdown {
  /** Parsed frontmatter data */
  frontmatter: SkillFrontmatter | null;
  /** Frontmatter parsing error (empty string if none) */
  frontmatterError: string;
  /** Markdown content (without frontmatter) */
  content: string;
}

/** Code block extracted from markdown */
export interface CodeBlock {
  /** Language identifier (e.g., 'bash', 'typescript') */
  lang: string | undefined;
  /** Block content */
  text: string;
  /** Starting line number (1-indexed) */
  lineNumber: number;
}

/** Link extracted from markdown */
export interface ExtractedLink {
  /** Link display text */
  text: string;
  /** Link URL/path */
  href: string;
  /** Line number (1-indexed) */
  lineNumber: number;
  /** Column number (1-indexed) */
  column: number;
}
