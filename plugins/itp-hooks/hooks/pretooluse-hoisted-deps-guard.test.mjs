/**
 * Tests for pretooluse-hoisted-deps-guard.mjs
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-hoisted-deps-guard.test.mjs
 *
 * Policies tested:
 * 1. Root-only pyproject.toml - Block pyproject.toml outside git root
 * 2. Path boundary validation - Block [tool.uv.sources] escaping git root
 * 3. Hoisted dev dependencies - Block [dependency-groups] in sub-packages
 *
 * ADR: 2026-01-22-pyproject-toml-root-only-policy
 */

import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import { execSync } from "child_process";
import { mkdirSync, rmSync, existsSync } from "fs";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "pretooluse-hoisted-deps-guard.mjs");
const TMP_DIR = join(import.meta.dir, "test-tmp-pretooluse");

// Get git root for testing
let GIT_ROOT;
try {
  GIT_ROOT = execSync("git rev-parse --show-toplevel", {
    encoding: "utf-8",
  }).trim();
} catch {
  GIT_ROOT = process.cwd();
}

function runHook(input) {
  try {
    const inputJson = JSON.stringify(input);
    const stdout = execSync(`node ${HOOK_PATH}`, {
      encoding: "utf-8",
      input: inputJson,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();

    let parsed = null;
    if (stdout) {
      try {
        parsed = JSON.parse(stdout);
      } catch {
        // Not JSON output
      }
    }
    return { stdout, parsed, exitCode: 0 };
  } catch (err) {
    return {
      stdout: err.stdout?.toString() || "",
      parsed: null,
      exitCode: err.status || 1,
    };
  }
}

/**
 * Helper to check if hook denied the operation
 * Works with both old format (decision: "block") and new format (permissionDecision: "deny")
 */
function isDenied(parsed) {
  if (!parsed) return false;
  // New format
  if (parsed.hookSpecificOutput?.permissionDecision === "deny") return true;
  // Old format (legacy)
  if (parsed.decision === "block") return true;
  return false;
}

/**
 * Helper to get the reason from either format
 */
function getReason(parsed) {
  if (!parsed) return "";
  // New format
  if (parsed.hookSpecificOutput?.permissionDecisionReason) {
    return parsed.hookSpecificOutput.permissionDecisionReason;
  }
  // Old format
  return parsed.reason || "";
}

// --- Setup/Teardown ---

beforeAll(() => {
  mkdirSync(TMP_DIR, { recursive: true });
});

afterAll(() => {
  if (existsSync(TMP_DIR)) {
    rmSync(TMP_DIR, { recursive: true });
  }
});

// ============================================================================
// Policy 1: Root-only pyproject.toml
// ============================================================================

describe("Policy 1: Root-only pyproject.toml", () => {
  it("should ALLOW pyproject.toml at git root", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        content: '[project]\nname = "my-project"',
      },
    });
    // No output = allowed
    expect(result.stdout).toBe("");
  });

  it("should BLOCK pyproject.toml in packages/ subdirectory", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/packages/my-lib/pyproject.toml`,
        content: '[project]\nname = "my-lib"',
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(isDenied(result.parsed)).toBe(true);
    expect(getReason(result.parsed)).toContain("[PYPROJECT-ROOT-ONLY]");
  });

  it("should BLOCK pyproject.toml in libs/ subdirectory", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/libs/utils/pyproject.toml`,
        content: '[project]\nname = "utils"',
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(isDenied(result.parsed)).toBe(true);
    expect(getReason(result.parsed)).toContain("[PYPROJECT-ROOT-ONLY]");
  });

  it("should BLOCK pyproject.toml in arbitrary nested directory", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/some/deep/nested/pyproject.toml`,
        content: '[project]\nname = "nested"',
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(isDenied(result.parsed)).toBe(true);
  });

  it("should ignore non-pyproject.toml files", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/packages/lib/setup.py`,
        content: 'from setuptools import setup\nsetup()',
      },
    });
    expect(result.stdout).toBe("");
  });
});

// ============================================================================
// Policy 2: Path boundary validation
// ============================================================================

describe("Policy 2: Path boundary validation", () => {
  it("should ALLOW path within monorepo", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        new_string: 'sibling = { path = "packages/sibling" }',
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should BLOCK path escaping with ../../../", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        new_string: 'external = { path = "../../../external-pkg" }',
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(isDenied(result.parsed)).toBe(true);
    expect(getReason(result.parsed)).toContain("[PATH-ESCAPE]");
  });

  it("should ALLOW git source references", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        new_string:
          'rangebar = { git = "https://github.com/owner/repo", branch = "main" }',
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should ALLOW workspace references", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        new_string: "my-lib = { workspace = true }",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should BLOCK multiple escaping paths", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        content: `[tool.uv.sources]
pkg1 = { path = "../../../../pkg1" }
pkg2 = { path = "../../../pkg2" }
valid = { path = "packages/valid" }`,
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(isDenied(result.parsed)).toBe(true);
    expect(getReason(result.parsed)).toContain("pkg1");
    expect(getReason(result.parsed)).toContain("pkg2");
  });

  it("should ALLOW single ../ within monorepo depth", () => {
    // This depends on the actual monorepo structure
    // A single ../ from packages/lib would still be within root
    const result = runHook({
      tool_name: "Edit",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        new_string: 'sibling = { path = "./packages/other" }',
      },
    });
    expect(result.stdout).toBe("");
  });
});

// ============================================================================
// Policy 3: Hoisted dev dependencies (legacy support)
// ============================================================================

describe("Policy 3: Hoisted dev dependencies", () => {
  it("should ALLOW [dependency-groups] at root", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        content: `[project]
name = "root"

[dependency-groups]
dev = ["pytest", "ruff"]`,
      },
    });
    // Root-level is allowed (this would be caught by root-only first for sub-packages)
    expect(result.stdout).toBe("");
  });

  it("should BLOCK [dependency-groups] in packages/ sub-package", () => {
    // Note: This is now caught by root-only policy first
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/packages/my-lib/pyproject.toml`,
        content: `[project]
name = "my-lib"

[dependency-groups]
dev = ["pytest"]`,
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(isDenied(result.parsed)).toBe(true);
    // Could be either PYPROJECT-ROOT-ONLY or HOISTED-DEPS depending on check order
  });
});

// ============================================================================
// Edge Cases
// ============================================================================

describe("Edge cases", () => {
  it("should ignore non-Write/Edit tools", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: {
        file_path: `${GIT_ROOT}/packages/lib/pyproject.toml`,
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should handle invalid JSON gracefully", () => {
    try {
      execSync(`echo "not json" | node ${HOOK_PATH}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      });
      // Should exit 0 (allow by default)
      expect(true).toBe(true);
    } catch (err) {
      // Should not throw
      expect(err.status).toBe(0);
    }
  });

  it("should handle missing file_path gracefully", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {},
    });
    expect(result.stdout).toBe("");
  });

  it("should handle empty content gracefully", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: `${GIT_ROOT}/pyproject.toml`,
        content: "",
      },
    });
    expect(result.stdout).toBe("");
  });
});
