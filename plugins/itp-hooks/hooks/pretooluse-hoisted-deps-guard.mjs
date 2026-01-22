#!/usr/bin/env node
/**
 * PreToolUse hook: Enforce hoisted dev dependencies pattern in monorepos
 *
 * Blocks edits that add [dependency-groups] to sub-package pyproject.toml files.
 * Dev dependencies should be hoisted to workspace root pyproject.toml.
 *
 * ADR: 2026-01-22-hoisted-dev-dependencies-monorepo (to be created)
 * Reference: https://docs.astral.sh/uv/concepts/projects/dependencies/
 */

import { dirname, basename } from "path";

// --- Types ---

/**
 * @typedef {Object} HookInput
 * @property {string} tool_name
 * @property {Object} tool_input
 * @property {string} [tool_input.file_path]
 * @property {string} [tool_input.new_string]
 * @property {string} [tool_input.content]
 */

/**
 * @typedef {Object} HookOutput
 * @property {"block" | "allow"} decision
 * @property {string} reason
 */

// --- Utility Functions ---

/**
 * Output JSON result to stdout
 * @param {HookOutput} result
 */
function output(result) {
  console.log(JSON.stringify(result));
}

/**
 * Check if path is a sub-package (not workspace root)
 * @param {string} filePath
 * @returns {boolean}
 */
function isSubPackage(filePath) {
  // Common monorepo sub-package patterns
  const subPackagePatterns = [
    /\/packages\/[^/]+\/pyproject\.toml$/,
    /\/libs\/[^/]+\/pyproject\.toml$/,
    /\/services\/[^/]+\/pyproject\.toml$/,
    /\/apps\/[^/]+\/pyproject\.toml$/,
  ];

  return subPackagePatterns.some((pattern) => pattern.test(filePath));
}

/**
 * Check if content contains [dependency-groups] section
 * @param {string} content
 * @returns {boolean}
 */
function hasDependencyGroups(content) {
  // Match [dependency-groups] section header
  return /^\s*\[dependency-groups\]/m.test(content);
}


// --- Main ---

async function main() {
  // Read JSON from stdin
  let inputText = "";
  const stdin = process.stdin;
  stdin.setEncoding("utf8");

  for await (const chunk of stdin) {
    inputText += chunk;
  }

  /** @type {HookInput} */
  let input;
  try {
    input = JSON.parse(inputText);
  } catch {
    // Invalid JSON - allow
    process.exit(0);
  }

  const toolName = input.tool_name || "";

  // Only check Write and Edit tools
  if (toolName !== "Write" && toolName !== "Edit") {
    process.exit(0);
  }

  const filePath = input.tool_input?.file_path || "";

  // Only check pyproject.toml files
  if (!filePath.endsWith("pyproject.toml")) {
    process.exit(0);
  }

  // Only enforce on sub-packages, not workspace root
  if (!isSubPackage(filePath)) {
    process.exit(0);
  }

  // Get the content being written/edited
  let newContent = "";

  if (toolName === "Write") {
    newContent = input.tool_input?.content || "";
  } else if (toolName === "Edit") {
    // For Edit, check the new_string being added
    const newString = input.tool_input?.new_string || "";
    if (hasDependencyGroups(newString)) {
      newContent = newString; // Will trigger block
    } else {
      // Also check if edit adds dependency-groups
      if (newString.includes("dependency-groups")) {
        newContent = newString;
      }
    }
  }

  // Check for [dependency-groups] in the new content
  if (hasDependencyGroups(newContent)) {
    const packageDir = dirname(filePath);
    const packageName = basename(packageDir);

    output({
      decision: "block",
      reason: `[HOISTED-DEPS] Blocked: [dependency-groups] in sub-package pyproject.toml

DETECTED: Adding [dependency-groups] to ${packageName}/pyproject.toml

POLICY: Dev dependencies must be hoisted to workspace root.

WHY:
- Sub-package [dependency-groups] are NOT installed by 'uv sync' from root
- Causes "unnecessary package" warnings and environment drift
- Single 'uv sync --group dev' should install all dev tools

FIX:
1. Add dev dependencies to ROOT pyproject.toml:
   [dependency-groups]
   dev = ["pytest", "ruff", ...]

2. In sub-package, add only a comment:
   # NOTE: Dev dependencies hoisted to workspace root pyproject.toml
   # Use 'uv sync --group dev' from workspace root

REFERENCE: https://docs.astral.sh/uv/concepts/projects/dependencies/`,
    });
    process.exit(0);
  }

  // No issues - allow
  process.exit(0);
}

main().catch((err) => {
  console.error("[pretooluse-hoisted-deps-guard] Error:", err);
  process.exit(0);
});
