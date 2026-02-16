#!/usr/bin/env node
/**
 * PreToolUse hook: Enforce pyproject.toml policies
 *
 * POLICIES ENFORCED:
 * 1. Root-only pyproject.toml: Block creation/editing of pyproject.toml outside git root
 * 2. Path boundary validation: Block [tool.uv.sources] path references escaping git root
 * 3. Hoisted dev dependencies: Block [dependency-groups] in sub-package pyproject.toml
 *
 * ADR: 2026-01-22-pyproject-toml-root-only-policy
 * Reference: https://docs.astral.sh/uv/concepts/projects/dependencies/
 */

import { dirname, basename, resolve, relative } from "path";
import { execSync } from "child_process";
import { trackHookError } from "./lib/hook-error-tracker.ts";

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
 * Output JSON result to stdout (legacy format)
 * @param {HookOutput} result
 * @deprecated Use denyWithReason for new code
 */
function output(result) {
  console.log(JSON.stringify(result));
}

/**
 * Output deny decision with proper PreToolUse format
 * @param {string} reason
 */
function denyWithReason(reason) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    })
  );
}

/**
 * Get git root directory for a given path
 * Falls back to cwd-based detection if path directory doesn't exist
 * @param {string} filePath
 * @returns {string|null}
 */
function getGitRoot(filePath) {
  try {
    // Try from the file's directory first (if it exists)
    const dir = dirname(filePath);
    try {
      const gitRoot = execSync("git rev-parse --show-toplevel", {
        cwd: dir,
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();
      return gitRoot;
    } catch {
      // Directory doesn't exist, try from cwd (Claude Code's context)
      const gitRoot = execSync("git rev-parse --show-toplevel", {
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();
      return gitRoot;
    }
  } catch {
    return null;
  }
}

/**
 * Check if pyproject.toml is at git root (root-only policy)
 * @param {string} filePath - Absolute path to pyproject.toml
 * @param {string} gitRoot - Git root directory
 * @returns {boolean}
 */
function isAtGitRoot(filePath, gitRoot) {
  const fileDir = dirname(filePath);
  return fileDir === gitRoot;
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

/**
 * Extract path references from [tool.uv.sources] section
 * Returns array of { package, path } objects for paths that escape git root
 * @param {string} content - pyproject.toml content
 * @param {string} filePath - Path to the pyproject.toml file
 * @param {string} gitRoot - Git root directory
 * @returns {Array<{package: string, path: string, resolved: string}>}
 */
function findEscapingPaths(content, filePath, gitRoot) {
  const escapingPaths = [];
  const fileDir = dirname(filePath);

  // Match patterns like: package-name = { path = "../../../something" }
  // Also matches: package-name = { path = "../sibling" }
  const pathPattern =
    /^([a-zA-Z0-9_-]+)\s*=\s*\{[^}]*path\s*=\s*["']([^"']+)["']/gm;

  let match;
  while ((match = pathPattern.exec(content)) !== null) {
    const packageName = match[1];
    const pathValue = match[2];

    // Resolve the path relative to the pyproject.toml location
    const resolvedPath = resolve(fileDir, pathValue);

    // Check if resolved path is outside git root
    const relativePath = relative(gitRoot, resolvedPath);
    if (relativePath.startsWith("..") || relativePath.startsWith("/")) {
      escapingPaths.push({
        package: packageName,
        path: pathValue,
        resolved: resolvedPath,
      });
    }
  }

  return escapingPaths;
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

  // Get git root for boundary validation
  const gitRoot = getGitRoot(filePath);

  // --- POLICY 1: Root-only pyproject.toml ---
  // Block pyproject.toml creation/editing outside git root
  if (gitRoot && !isAtGitRoot(filePath, gitRoot)) {
    const relPath = relative(gitRoot, filePath);
    denyWithReason(`[PYPROJECT-ROOT-ONLY] Blocked: pyproject.toml outside monorepo root

DETECTED: Writing to ${relPath}

POLICY: pyproject.toml should ONLY exist at monorepo root.

WHY:
- Sub-directory pyproject.toml creates implicit monorepo fragmentation
- 'uv sync' from root won't pick up sub-package dependencies
- Breaks workspace member discovery and lockfile coherence

FIX:
1. Use workspace members in ROOT pyproject.toml:
   [tool.uv.workspace]
   members = ["packages/*"]

2. Sub-packages should be workspace members, not standalone projects

3. If this IS the root, run from the correct directory

REFERENCE: https://docs.astral.sh/uv/concepts/projects/workspaces/`);
    process.exit(0);
  }

  // Get the content being written/edited
  let newContent = "";

  if (toolName === "Write") {
    newContent = input.tool_input?.content || "";
  } else if (toolName === "Edit") {
    // For Edit, check the new_string being added
    newContent = input.tool_input?.new_string || "";
  }

  // --- POLICY 2: Path boundary validation ---
  // Block [tool.uv.sources] path references escaping git root
  if (gitRoot && newContent) {
    const escapingPaths = findEscapingPaths(newContent, filePath, gitRoot);
    if (escapingPaths.length > 0) {
      const pathList = escapingPaths
        .map((p) => `  - ${p.package} = { path = "${p.path}" }`)
        .join("\n");

      denyWithReason(`[PATH-ESCAPE] Blocked: [tool.uv.sources] path escapes monorepo boundary

DETECTED:
${pathList}

POLICY: Path references in [tool.uv.sources] must resolve within git root.

WHY:
- Paths escaping monorepo (../../../) create implicit external dependencies
- Breaks portability when code is cloned elsewhere
- Violates monorepo encapsulation principle

FIX:
1. Use Git source for external packages:
   package = { git = "https://github.com/owner/repo", branch = "main" }

2. Or add package as workspace member:
   [tool.uv.workspace]
   members = ["packages/*"]

3. For sibling monorepo packages, use workspace reference:
   package = { workspace = true }

GIT ROOT: ${gitRoot}
REFERENCE: https://docs.astral.sh/uv/concepts/projects/dependencies/`);
      process.exit(0);
    }
  }

  // --- POLICY 3: Hoisted dev dependencies ---
  // Only enforce on sub-packages (legacy support for existing monorepos)
  if (isSubPackage(filePath) && hasDependencyGroups(newContent)) {
    const packageDir = dirname(filePath);
    const packageName = basename(packageDir);

    denyWithReason(`[HOISTED-DEPS] Blocked: [dependency-groups] in sub-package pyproject.toml

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

REFERENCE: https://docs.astral.sh/uv/concepts/projects/dependencies/`);
    process.exit(0);
  }

  // No issues - allow
  process.exit(0);
}

main().catch((err) => {
  trackHookError("pretooluse-hoisted-deps-guard", `Error: ${err?.message ?? err}`);
  process.exit(0);
});
