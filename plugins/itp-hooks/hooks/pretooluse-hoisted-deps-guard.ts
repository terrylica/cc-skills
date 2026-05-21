#!/usr/bin/env bun
/**
 * PreToolUse hook: pyproject.toml policies (iter-86 orchestrator-inlined)
 *
 * THREE POLICIES ENFORCED on pyproject.toml Write/Edit:
 *   1. Root-only pyproject.toml: Block creation/editing of pyproject.toml outside git root
 *      (except maturin-built Rust extensions, which MUST co-locate with Cargo.toml)
 *   2. Path boundary validation: Block [tool.uv.sources] path references escaping git root
 *   3. Hoisted dev dependencies: Block [dependency-groups] in sub-package pyproject.toml
 *
 * ADR: 2026-01-22-pyproject-toml-root-only-policy
 * Reference: https://docs.astral.sh/uv/concepts/projects/dependencies/
 *
 * Iter-86 dual-use contract (mirrors iter-85 version-guard pattern):
 *   - Standalone CLI mode (preserved for direct testing via bun pretooluse-hoisted-deps-guard.ts):
 *     `main()` reads stdin, invokes the classifier, emits allow/deny via the
 *     iter-84 helpers, gated under `import.meta.main` so importing this
 *     file from the orchestrator does NOT trigger main()-side effects.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyHoistedDepsGuardForOrchestrator` and
 *     invokes it directly in the single bun process. The classifier conforms
 *     to PreToolUseSubhookContract: pure async function, no stdin/stdout/
 *     process.exit side-effects, returns a PreToolUseSubhookDecision.
 */

import { dirname, basename, resolve, relative, join } from "path";
import { existsSync, readFileSync } from "fs";
import { execSync } from "child_process";
import {
  allow,
  deny,
  parseStdinOrAllow,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";

// ============================================================================
// Pure helpers (synchronous, no I/O contract violations)
// ============================================================================

/**
 * Get git root directory for a given path.
 * Falls back to cwd-based detection if path directory doesn't exist.
 * Returns null on git failure.
 *
 * NOTE: execSync is a synchronous subprocess spawn — it's the ONE I/O escape
 * hatch in the classifier because git boundary detection is intrinsic to the
 * policy. The PreToolUseSubhookContract forbids stdin/stdout/process.exit;
 * subprocess execution for read-only environment queries is permitted (same
 * as readFileSync which file-size-guard also uses for Edit ops).
 */
function resolveGitRootForFilePathAllowingCwdFallbackOnMissingDir(filePath: string): string | null {
  try {
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

/** Check if pyproject.toml is at git root (root-only policy). */
function isFileLocatedAtGitRoot(filePath: string, gitRoot: string): boolean {
  return dirname(filePath) === gitRoot;
}

/**
 * Check if pyproject.toml is a maturin-built Rust extension.
 * These MUST co-locate with Cargo.toml because maturin reads both from the
 * crate directory; they are the canonical PyO3 + maturin layout, NOT
 * monorepo fragmentation.
 *
 * Heuristic: sibling Cargo.toml exists AND either
 *   (a) the pyproject.toml content declares build-backend = "maturin", OR
 *   (b) no content is visible yet (Write hook fires before file exists) and
 *       the sibling Cargo.toml declares crate-type = "cdylib".
 */
function isPyprojectTomlForMaturinBuiltPyo3RustExtensionCoLocatedWithCargoToml(
  filePath: string,
  content: string,
): boolean {
  const fileDir = dirname(filePath);
  const cargoToml = join(fileDir, "Cargo.toml");

  if (!existsSync(cargoToml)) {
    return false;
  }

  if (content && /build-backend\s*=\s*["']maturin["']/.test(content)) {
    return true;
  }

  try {
    const cargoContent = readFileSync(cargoToml, "utf8");
    if (/crate-type\s*=\s*\[[^\]]*["']cdylib["']/.test(cargoContent)) {
      return true;
    }
  } catch {
    // Fall through to false
  }

  return false;
}

/** Check if path matches a common monorepo sub-package pattern. */
const MONOREPO_SUBPACKAGE_PYPROJECT_PATH_REGEX_PATTERNS: readonly RegExp[] = [
  /\/packages\/[^/]+\/pyproject\.toml$/,
  /\/libs\/[^/]+\/pyproject\.toml$/,
  /\/services\/[^/]+\/pyproject\.toml$/,
  /\/apps\/[^/]+\/pyproject\.toml$/,
];

function isFilePathInMonorepoSubPackageDirectory(filePath: string): boolean {
  return MONOREPO_SUBPACKAGE_PYPROJECT_PATH_REGEX_PATTERNS.some((pattern) => pattern.test(filePath));
}

/** Detect [dependency-groups] section header in pyproject.toml content. */
function hasDependencyGroupsSectionHeaderDeclaration(content: string): boolean {
  return /^\s*\[dependency-groups\]/m.test(content);
}

/**
 * Extract path references from [tool.uv.sources] section.
 * Returns array of { package, path, resolved } for paths that escape git root.
 */
interface UvSourcePathReferenceEscapingGitRoot {
  package: string;
  path: string;
  resolved: string;
}

function findUvSourcePathReferencesEscapingMonorepoGitRoot(
  content: string,
  filePath: string,
  gitRoot: string,
): UvSourcePathReferenceEscapingGitRoot[] {
  const escapingPaths: UvSourcePathReferenceEscapingGitRoot[] = [];
  const fileDir = dirname(filePath);

  // Match patterns like: package-name = { path = "../../../something" }
  // Also matches: package-name = { path = "../sibling" }
  const pathPattern = /^([a-zA-Z0-9_-]+)\s*=\s*\{[^}]*path\s*=\s*["']([^"']+)["']/gm;

  for (const match of content.matchAll(pathPattern)) {
    const packageName = match[1];
    const pathValue = match[2];
    if (!packageName || !pathValue) continue;

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

// ============================================================================
// Pure classifier (iter-86 orchestrator-inlineable contract)
// ============================================================================

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Identical 3-policy logic to the pre-iter-86 .mjs main() body, but factored
 * out so the iter-84 orchestrator can invoke it without subprocess-spawning
 * this file (which would defeat the orchestrator's ~44ms cold-start saving).
 *
 * Policy short-circuit order (first deny wins):
 *   1. tool_name not Write/Edit → ALLOW (early exit)
 *   2. file_path not pyproject.toml → ALLOW (early exit, O(1) extension check)
 *   3. POLICY 1: pyproject.toml outside git root and NOT a maturin crate → DENY
 *   4. POLICY 2: [tool.uv.sources] path escapes git root → DENY
 *   5. POLICY 3: sub-package has [dependency-groups] → DENY
 *   6. All policies clean → ALLOW
 */
export async function classifyHoistedDepsGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input = {} } = input;

  // Early exit: Only check Write and Edit tools
  if (tool_name !== "Write" && tool_name !== "Edit") {
    return ALLOW_DECISION;
  }

  const filePath = (tool_input.file_path as string) || "";

  // Early exit: Only check pyproject.toml files
  if (!filePath.endsWith("pyproject.toml")) {
    return ALLOW_DECISION;
  }

  // Get git root for boundary validation
  const gitRoot = resolveGitRootForFilePathAllowingCwdFallbackOnMissingDir(filePath);

  // Capture proposed content (Write.content or Edit.new_string)
  const newContent =
    tool_name === "Write"
      ? ((tool_input.content as string) || "")
      : ((tool_input.new_string as string) || "");

  // --- POLICY 1: Root-only pyproject.toml ---
  if (
    gitRoot &&
    !isFileLocatedAtGitRoot(filePath, gitRoot) &&
    !isPyprojectTomlForMaturinBuiltPyo3RustExtensionCoLocatedWithCargoToml(filePath, newContent)
  ) {
    const relPath = relative(gitRoot, filePath);
    const reason = [
      "[PYPROJECT-ROOT-ONLY] Blocked: pyproject.toml outside monorepo root",
      "",
      `DETECTED: Writing to ${relPath}`,
      "",
      "POLICY: pyproject.toml should ONLY exist at monorepo root.",
      "",
      "WHY:",
      "- Sub-directory pyproject.toml creates implicit monorepo fragmentation",
      "- 'uv sync' from root won't pick up sub-package dependencies",
      "- Breaks workspace member discovery and lockfile coherence",
      "",
      "FIX:",
      "1. Use workspace members in ROOT pyproject.toml:",
      "   [tool.uv.workspace]",
      `   members = ["packages/*"]`,
      "",
      "2. Sub-packages should be workspace members, not standalone projects",
      "",
      "3. If this IS the root, run from the correct directory",
      "",
      "REFERENCE: https://docs.astral.sh/uv/concepts/projects/workspaces/",
    ].join("\n");
    return denyDecision(reason);
  }

  // --- POLICY 2: Path boundary validation ---
  if (gitRoot && newContent) {
    const escapingPaths = findUvSourcePathReferencesEscapingMonorepoGitRoot(
      newContent,
      filePath,
      gitRoot,
    );
    if (escapingPaths.length > 0) {
      const pathList = escapingPaths
        .map((p) => `  - ${p.package} = { path = "${p.path}" }`)
        .join("\n");

      const reason = [
        "[PATH-ESCAPE] Blocked: [tool.uv.sources] path escapes monorepo boundary",
        "",
        "DETECTED:",
        pathList,
        "",
        "POLICY: Path references in [tool.uv.sources] must resolve within git root.",
        "",
        "WHY:",
        "- Paths escaping monorepo (../../../) create implicit external dependencies",
        "- Breaks portability when code is cloned elsewhere",
        "- Violates monorepo encapsulation principle",
        "",
        "FIX:",
        "1. Use Git source for external packages:",
        `   package = { git = "https://github.com/owner/repo", branch = "main" }`,
        "",
        "2. Or add package as workspace member:",
        "   [tool.uv.workspace]",
        `   members = ["packages/*"]`,
        "",
        "3. For sibling monorepo packages, use workspace reference:",
        "   package = { workspace = true }",
        "",
        `GIT ROOT: ${gitRoot}`,
        "REFERENCE: https://docs.astral.sh/uv/concepts/projects/dependencies/",
      ].join("\n");
      return denyDecision(reason);
    }
  }

  // --- POLICY 3: Hoisted dev dependencies ---
  if (
    isFilePathInMonorepoSubPackageDirectory(filePath) &&
    hasDependencyGroupsSectionHeaderDeclaration(newContent)
  ) {
    const packageDir = dirname(filePath);
    const packageName = basename(packageDir);
    const reason = [
      "[HOISTED-DEPS] Blocked: [dependency-groups] in sub-package pyproject.toml",
      "",
      `DETECTED: Adding [dependency-groups] to ${packageName}/pyproject.toml`,
      "",
      "POLICY: Dev dependencies must be hoisted to workspace root.",
      "",
      "WHY:",
      "- Sub-package [dependency-groups] are NOT installed by 'uv sync' from root",
      `- Causes "unnecessary package" warnings and environment drift`,
      "- Single 'uv sync --group dev' should install all dev tools",
      "",
      "FIX:",
      "1. Add dev dependencies to ROOT pyproject.toml:",
      "   [dependency-groups]",
      `   dev = ["pytest", "ruff", ...]`,
      "",
      "2. In sub-package, add only a comment:",
      "   # NOTE: Dev dependencies hoisted to workspace root pyproject.toml",
      "   # Use 'uv sync --group dev' from workspace root",
      "",
      "REFERENCE: https://docs.astral.sh/uv/concepts/projects/dependencies/",
    ].join("\n");
    return denyDecision(reason);
  }

  return ALLOW_DECISION;
}

// ============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("HOISTED-DEPS-GUARD");
  if (!input) return;

  const decision = await classifyHoistedDepsGuardForOrchestrator(input);

  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      // hoisted-deps-guard doesn't currently use ask; treat as deny for safety
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// import.meta.main is true only for the entry-point script; when the
// orchestrator imports classifyHoistedDepsGuardForOrchestrator, this branch
// does NOT fire (preserves dual-mode contract).
if (import.meta.main) {
  main().catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    trackHookError("pretooluse-hoisted-deps-guard", `Unhandled error: ${message}`);
    allow();
  });
}
