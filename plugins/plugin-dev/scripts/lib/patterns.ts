/**
 * Centralized regex patterns for skill validation
 *
 * Ports Python regex patterns from validate_skill.py, validate_links.py,
 * and fix_bash_blocks.py to JavaScript/TypeScript.
 *
 * Note: Python regex differs slightly from JavaScript:
 * - Python re.MULTILINE -> JavaScript /m flag
 * - Python re.DOTALL -> JavaScript /s flag (or use [\s\S])
 * - Python r'raw string' -> JavaScript template literal or escape
 */

// ============================================================================
// Markdown Patterns
// ============================================================================

/** Markdown link pattern: [text](url) - captures text and url */
export const MARKDOWN_LINK = /\[([^\]]+)\]\(([^)]+)\)/g;

/** Fenced code block pattern (for stripping) */
export const FENCED_CODE_BLOCK = /```[\s\S]*?```/g;

/** Inline code pattern (for stripping) */
export const INLINE_CODE = /`[^`]+`/g;

// ============================================================================
// Bash Patterns
// ============================================================================

/** Bash code block with content capture */
export const BASH_CODE_BLOCK = /```bash\n([\s\S]*?)```/g;

/** Heredoc wrapper detection (at start of block content) */
export const HEREDOC_WRAPPER = /^\/usr\/bin\/env\s+bash\s*<<\s*['"]?\w+['"]?/m;

/**
 * Bash-specific patterns that require heredoc wrapper for zsh compatibility.
 * Each pattern indicates bash-specific syntax that won't work in zsh.
 */
export const BASH_SPECIFIC_PATTERNS = {
  /** Command substitution $(...) */
  commandSubstitution: /\$\([^)]+\)/,
  /** Bash conditional [[ ]] */
  bashConditional: /\[\[/,
  /** Declare statement at line start */
  declare: /^\s*declare\s/m,
  /** Local statement at line start */
  local: /^\s*local\s/m,
  /** Function keyword at line start */
  functionKeyword: /^\s*function\s/m,
  /** Variable expansion ${...} */
  variableExpansion: /\$\{[^}]+\}/,
  /** If with [[ conditional */
  ifConditional: /if\s+\[\[/,
  /** For loop */
  forLoop: /for\s+\w+\s+in/,
  /** While with [[ conditional */
  whileConditional: /while\s+\[\[/,
} as const;

/** Prohibited patterns in bash blocks (warning-level) */
export const BASH_PROHIBITED_PATTERNS = {
  /** Associative arrays - require heredoc */
  associativeArray: /declare\s+-A/,
  /** Perl regex in grep - not portable, use grep -E instead */
  perlRegex: /grep\s+[^|]*-[a-zA-Z]*P/,
} as const;

// ============================================================================
// Skill Name Validation
// ============================================================================

/** Valid skill name format: lowercase letters, numbers, hyphens */
export const SKILL_NAME = /^[a-z][a-z0-9-]*$/;

// ============================================================================
// Link Validation Patterns
// ============================================================================

/** GitHub URL to this repo (should use relative path instead) */
export const GITHUB_REPO_URL = /https:\/\/github\.com\/terrylica\/cc-skills\/blob\//;

/** Absolute repo path pattern (starts with / but not //, https, or #) */
export const ABSOLUTE_REPO_PATH = /^\/(?!\/)(?!https?:)(?!#)/;

// ============================================================================
// Documentation Example Marker
// ============================================================================

/** Marker for documentation examples that should be skipped */
export const DOC_EXAMPLE_MARKER = /#\s*❌\s*WRONG/;

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Check if a bash block contains bash-specific syntax
 */
export function hasBashSpecificSyntax(block: string): boolean {
  return Object.values(BASH_SPECIFIC_PATTERNS).some((pattern) => pattern.test(block));
}

/**
 * Check if a bash block is already wrapped with heredoc
 */
export function hasHeredocWrapper(block: string): boolean {
  return HEREDOC_WRAPPER.test(block);
}

/**
 * Check if a block is a documentation example (marked with ❌ WRONG)
 */
export function isDocExample(block: string): boolean {
  return DOC_EXAMPLE_MARKER.test(block);
}

/**
 * Strip code blocks from markdown content (for link scanning)
 */
export function stripCodeFromContent(content: string): string {
  return content.replace(FENCED_CODE_BLOCK, "").replace(INLINE_CODE, "");
}

/**
 * Create a new regex from pattern with global flag for iteration
 */
export function createGlobalRegex(pattern: RegExp): RegExp {
  const flags = pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g";
  return new RegExp(pattern.source, flags);
}
