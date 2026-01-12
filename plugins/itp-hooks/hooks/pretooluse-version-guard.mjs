#!/usr/bin/env bun
/**
 * PreToolUse hook: Version SSoT Guard
 *
 * Blocks ANY hardcoded version numbers in markdown documentation.
 * Forces use of "<version>" placeholder pattern.
 * Universal across all projects - Rust, Python, JavaScript, etc.
 *
 * Usage:
 *   Installed via /itp:hooks install
 *   Escape hatch: # SSoT-OK comment in file
 *
 * ADR: /docs/adr/2026-01-09-version-ssot-guard.md (to be created)
 */

// ============================================================================
// VERSION PATTERNS - Expanded based on codebase audit
// ============================================================================

const VERSION_PATTERNS = [
  // Rust/TOML: package = "1.2.3" or version = "1.2.3"
  /=\s*"(\d+\.\d+\.\d+)"/g,
  /=\s*"(\d+\.\d+)"/g,
  /=\s*"(\d+)"/g, // Major-only

  // Python: package==1.2.3, >=1.2.3, ~=1.2.3
  /==\s*(\d+\.\d+\.\d+)/g,
  />=\s*(\d+\.\d+\.\d+)/g,
  /~=\s*(\d+\.\d+\.\d+)/g,

  // JSON: "version": "1.2.3"
  /"version"\s*:\s*"(\d+\.\d+\.\d+)"/g,

  // Prose patterns: Version 1.2.3, v1.2.3, **Version**: 1.2.3
  /Version:\s*(\d+\.\d+\.\d+)/gi,
  /\*\*Version\*\*:\s*v?(\d+\.\d+\.\d+)/gi,
  /\bv(\d+\.\d+\.\d+)\b/g,

  // Forward-compatible: v1.2.3+
  /\bv?(\d+\.\d+\.\d+)\+/g,

  // Pre-release patterns: 1.2.3-alpha.1, 1.2.3-beta.2, 1.2.3-rc.1
  /(\d+\.\d+\.\d+)-(alpha|beta|rc)(\.\d+)?/gi,

  // Calendar versioning: 2024.9.5
  /\b(\d{4}\.\d{1,2}\.\d{1,2})\b/g,
];

// ============================================================================
// ALLOWED PATTERNS & EXCLUDED PATHS
// ============================================================================

const ESCAPE_HATCH = /#\s*SSoT-OK/;

// Paths where historical versions are OK
const EXCLUDED_PATHS = [
  /CHANGELOG/i, // All changelogs
  /MIGRATION/i, // Migration guides
  /\/archive\//i, // Archived docs
  /\/milestones\//i, // Milestone tracking
  /\/planning\//i, // Planning documents
  /\/reports\//i, // Generated reports
  /\/outputs?\//i, // Output directories (output/ or outputs/)
  /\/adr\//i, // Architecture Decision Records
  /ADR-\d+/i, // ADR files by number
  /HISTORY/i, // History files
  /node_modules/i, // Never check node_modules
  /\/crates\/[^/]+\/README\.md$/i, // Crate-level READMEs
  /\/development\//i, // Development docs
];

// ============================================================================
// HELPER FUNCTIONS (lifecycle-reference.md compliant)
// ============================================================================

/**
 * Output JSON response to stdout
 * @param {object} response - The response object
 */
function output(response) {
  console.log(JSON.stringify(response));
}

/**
 * Allow the tool operation to proceed
 * Lifecycle: permissionDecision: "allow"
 */
function allow() {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  });
}

/**
 * Deny the tool operation with a reason
 * Lifecycle: permissionDecision: "deny" + permissionDecisionReason
 * @param {string} reason - Explanation shown to Claude
 */
function deny(reason) {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  });
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function main() {
  // Parse stdin JSON input
  let input;
  try {
    const stdin = await Bun.stdin.text();
    input = JSON.parse(stdin);
  } catch (e) {
    console.error(`[VERSION-GUARD] Failed to parse stdin: ${e.message}`);
    allow();
    return;
  }

  const { tool_name, tool_input = {} } = input;

  // Early exit: Only check Write and Edit tools
  if (tool_name !== "Write" && tool_name !== "Edit") {
    allow();
    return;
  }

  const filePath = tool_input.file_path || "";
  const content = tool_input.content || tool_input.new_string || "";

  // Early exit: Only check markdown files
  if (!filePath.endsWith(".md")) {
    allow();
    return;
  }

  // Early exit: Excluded paths (changelogs, migrations, etc.)
  if (EXCLUDED_PATHS.some((p) => p.test(filePath))) {
    allow();
    return;
  }

  // Early exit: Escape hatch comment present
  if (ESCAPE_HATCH.test(content)) {
    allow();
    return;
  }

  // NOTE: Placeholder pattern does NOT exempt file from checking (STRICT mode)
  // Block if ANY hardcoded version, even if placeholder is also present

  // Find hardcoded versions
  const versions = new Set();
  for (const pattern of VERSION_PATTERNS) {
    // Reset lastIndex for global patterns
    pattern.lastIndex = 0;
    for (const match of content.matchAll(pattern)) {
      versions.add(match[1]);
    }
  }

  // No versions found = allow
  if (versions.size === 0) {
    allow();
    return;
  }

  // Block with helpful message
  const fileName = filePath.split("/").pop();
  const versionList = [...versions].map((v) => `"${v}"`).join(", ");
  deny(`[VERSION-GUARD] Hardcoded version in ${fileName}

Found: ${versionList}

Fix by using one of:
  my-package = "<version>"  (placeholder pattern)
  See [crates.io](link)     (registry link)
  # SSoT-OK                 (escape hatch comment)

SSoT: Version only in Cargo.toml/pyproject.toml/package.json`);
}

// Run with error handling (always allow on error)
main().catch((e) => {
  console.error(`[VERSION-GUARD] Unhandled error: ${e.message}`);
  allow();
});
