/**
 * Configuration constants for skill validation
 *
 * CRITICAL: Implements strict link validation policy.
 * Only /docs/adr/ and /docs/design/ paths are allowed as external references.
 * All other external paths must be copied into the skill directory.
 */

// ============================================================================
// Link Validation Policy
// ============================================================================

/**
 * ALLOWED repo-relative paths in skill markdown files.
 * These are source-repo references that are NOT bundled with installed skills.
 *
 * ALL other /... paths are ERRORS - files must be moved into skill directory.
 */
export const ALLOWED_REPO_PATHS = ["/docs/adr/", "/docs/design/"] as const;

// ============================================================================
// Skill Structure Standards
// ============================================================================

/** Maximum description length (S3 standard) */
export const MAX_DESCRIPTION_LENGTH = 200;

/** Maximum SKILL.md line count before requiring references/ (S1 standard) */
export const MAX_SKILL_LINES = 200;

/** Required YAML frontmatter fields */
export const REQUIRED_FRONTMATTER_FIELDS = ["name", "description"] as const;

/** Recommended YAML frontmatter fields (warning if missing) */
export const RECOMMENDED_FRONTMATTER_FIELDS = ["allowed-tools"] as const;

// ============================================================================
// File System Configuration
// ============================================================================

/** Directories to skip during file scanning */
export const SKIP_DIRECTORIES = new Set([
  "node_modules",
  ".git",
  "__pycache__",
  ".venv",
  "tmp",
  "dist",
  "build",
  "coverage",
  ".cache",
  ".mypy_cache",
  ".pytest_cache",
  ".ruff_cache",
]);

/** File encoding for reading/writing */
export const FILE_ENCODING = "utf-8" as const;

// ============================================================================
// Heredoc EOF Marker Generation
// ============================================================================

/**
 * Content-aware EOF marker patterns.
 * Keys are regex-testable keywords, values are corresponding EOF markers.
 */
export const EOF_MARKER_PATTERNS: Record<string, string> = {
  preflight: "PREFLIGHT_EOF",
  check: "PREFLIGHT_EOF",
  setup: "SETUP_EOF",
  install: "SETUP_EOF",
  validate: "VALIDATE_EOF",
  verify: "VALIDATE_EOF",
  config: "CONFIG_EOF",
  detect: "DETECT_EOF",
  git: "GIT_EOF",
  doppler: "DOPPLER_EOF",
  mise: "MISE_EOF",
  test: "TEST_EOF",
  build: "BUILD_EOF",
  deploy: "DEPLOY_EOF",
  release: "RELEASE_EOF",
};

/** Default EOF marker suffix for fallback */
export const DEFAULT_EOF_SUFFIX = "_SCRIPT_EOF";

// ============================================================================
// Clarification Presets
// ============================================================================

/** Preset clarification options for description length violation */
export const DESCRIPTION_LENGTH_OPTIONS = [
  "Trim description to 200 characters (recommended)",
  "Keep current description (accept warning)",
  "Manual edit required",
];

/** Preset clarification options for missing allowed-tools */
export const ALLOWED_TOOLS_OPTIONS = [
  "Add basic allowed-tools (Read, Grep, Glob)",
  "Add full access allowed-tools (all tools)",
  "Add custom allowed-tools",
  "Skip (accept warning)",
];

/** Preset clarification options for S2 compliance */
export const S2_COMPLIANCE_OPTIONS = [
  "Create references/ directory",
  "Reduce SKILL.md line count",
  "Accept current structure (warning)",
];

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Check if a path is in the allowed repo paths list
 */
export function isAllowedRepoPath(url: string): boolean {
  return ALLOWED_REPO_PATHS.some((allowed) => url.startsWith(allowed));
}

/**
 * Check if a directory should be skipped during scanning
 */
export function shouldSkipDirectory(name: string): boolean {
  return SKIP_DIRECTORIES.has(name);
}

/**
 * Get EOF marker for bash block content
 */
export function getEofMarker(content: string, filename: string): string {
  const contentLower = content.toLowerCase();

  // Try content-based matching
  for (const [keyword, marker] of Object.entries(EOF_MARKER_PATTERNS)) {
    if (contentLower.includes(keyword)) {
      return marker;
    }
  }

  // Fallback to filename-based
  const stem = filename.replace(/\.md$/i, "").toUpperCase().replace(/-/g, "_");
  return `${stem}${DEFAULT_EOF_SUFFIX}`;
}
