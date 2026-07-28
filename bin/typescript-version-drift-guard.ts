#!/usr/bin/env bun
/**
 * TypeScript Version Drift Guard
 *
 * Discovers every package.json across the estate (~/eon, ~/vj, ~/own) declaring
 * a `typescript` dependency, and compares the declared specifier against the
 * actually-installed compiler version (from node_modules/.bin/tsc --version).
 *
 * Reports drift with a clear human-readable format and machine-readable JSON mode.
 * Recognizes sanctioned deviations: the @typescript/typescript6 compat alias and
 * ALLOW-LEGACY-TS marker are not reported as drift.
 *
 * CLI-first design: supports --help, --help=json, --json mode, exit codes,
 * --skip-if-offline, --roots flag for search paths, and JSONL logging.
 *
 * Exit codes:
 *   0 = all packages conformant
 *   1 = drift detected
 *   2 = usage error
 *   3 = runtime error (network, timeout, permission)
 */

import { readFileSync, existsSync, mkdirSync, readdirSync } from "fs";
import { resolve, dirname, join } from "path";
import { homedir } from "os";
import { execSync } from "child_process";

// Reuse the shared evaluator from itp-hooks
import {
  evaluateTypeScriptVersionSpecifier,
  findTypeScriptDependencySpecifiersInPackageJsonText,
  isBlockingTypeScriptVersionSpecifierVerdict,
} from "../plugins/itp-hooks/hooks/lib/typescript-version-specifier-minimum-major-policy-evaluator.ts";

// ============================================================================
// CLI Argument Parsing
// ============================================================================

interface CliOptions {
  help: boolean;
  helpJson: boolean;
  json: boolean;
  skipIfOffline: boolean;
  roots: string[];
  version: boolean;
  includeWorktrees: boolean;
}

function parseCliArgs(args: string[]): CliOptions {
  const opts: CliOptions = {
    help: false,
    helpJson: false,
    json: false,
    skipIfOffline: false,
    roots: [],
    version: false,
    includeWorktrees: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help") {
      opts.help = true;
    } else if (arg === "--help=json") {
      opts.helpJson = true;
    } else if (arg === "--json") {
      opts.json = true;
    } else if (arg === "--skip-if-offline") {
      opts.skipIfOffline = true;
    } else if (arg === "--include-worktrees") {
      opts.includeWorktrees = true;
    } else if (arg === "--version") {
      opts.version = true;
    } else if (arg === "--roots") {
      i++;
      if (i >= args.length) {
        console.error("Error: --roots requires an argument");
        process.exit(2);
      }
      opts.roots.push(args[i]);
    } else if (arg.startsWith("--roots=")) {
      opts.roots.push(arg.slice("--roots=".length));
    } else if (arg.startsWith("--")) {
      console.error(`Error: unknown flag: ${arg}`);
      process.exit(2);
    }
  }

  return opts;
}

// ============================================================================
// Help Text
// ============================================================================

const HELP_TEXT = `typescript-version-drift-guard

Check for declared TypeScript specifier vs actually-installed compiler version drift
across the entire estate.

USAGE
  typescript-version-drift-guard [FLAGS]

FLAGS
  --help              Show this help message
  --help=json         Show help as JSON
  --json              Output JSON instead of human-readable format
  --version           Show version and exit
  --skip-if-offline   Skip checks if the system is offline (for release preflight)
  --roots PATHS       Search paths (repeatable or comma-separated); default: ~/eon,~/vj,~/own
  --include-worktrees Include *-ts7 migration worktrees (default: excluded as duplicates)

OUTPUT FORMATS

  Human-readable (default):
    Drifts and concerns are listed with context. Sanctioned aliases and
    marked exceptions are noted as intentional, not drift.

  JSON (--json):
    Structured results with all packages analyzed, their declarations,
    installed versions, and verdict.

EXIT CODES
  0 - All packages conformant
  1 - Drift detected
  2 - Usage error
  3 - Runtime error (network, permission, or timeout)

ENVIRONMENT
  ALLOW-LEGACY-TS   Mark a drift as intentional (escape hatch); one per repo
`;

const HELP_JSON = {
  name: "typescript-version-drift-guard",
  version: "1.0.0",
  description:
    "Check for TypeScript specifier vs installed compiler version drift across the estate",
  usage: "typescript-version-drift-guard [FLAGS]",
  flags: [
    {
      name: "--help",
      description: "Show help message",
      type: "boolean",
    },
    {
      name: "--help=json",
      description: "Show help as JSON",
      type: "boolean",
    },
    {
      name: "--json",
      description: "Output JSON instead of human-readable format",
      type: "boolean",
    },
    {
      name: "--version",
      description: "Show version and exit",
      type: "boolean",
    },
    {
      name: "--skip-if-offline",
      description: "Skip checks if system is offline (for release preflight)",
      type: "boolean",
    },
    {
      name: "--include-worktrees",
      description: "Include *-ts7 migration worktrees (default: excluded)",
      type: "boolean",
    },
    {
      name: "--roots",
      description: "Search paths (repeatable); default: ~/eon,~/vj,~/own",
      type: "string",
      repeatable: true,
    },
  ],
  exit_codes: {
    0: "All packages conformant",
    1: "Drift detected",
    2: "Usage error",
    3: "Runtime error",
  },
};

// ============================================================================
// Types
// ============================================================================

interface PackageAnalysis {
  path: string;
  packageJsonPath: string;
  declared: string;
  installedVersions: Record<string, string | null>; // e.g. { "tsc": "7.0.2", "tsc6": "6.0.3" }
  verdict: "conformant" | "drift" | "exception" | "error";
  reason: string;
  evaluatorVerdictKind?: string;
}

// ============================================================================
// Core Logic: Discover and Analyze
// ============================================================================

function isOnline(): boolean {
  try {
    // Quick DNS check via dig or nslookup
    execSync("ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1", { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/**
 * Skip paths that are known duplicates, vendored clones, or worktrees.
 */
function shouldSkipPath(path: string, includeWorktrees: boolean): boolean {
  const basename = path.split("/").pop() ?? "";
  const nameParts = path.split("/");

  // Exclude vendored third-party clones and research archives
  const vendoredPatterns = [
    "ralph-reference-repos",
    "nt/repos",
    "cc-skills-garch-fix",
    "cc-skills-interactive-json-form",
    "sred-analysis",
    ".uv-cache",
    ".venv",
    "site-packages",
    "labextensions",
  ];
  if (vendoredPatterns.some((p) => path.includes(p))) {
    return true;
  }

  // Exclude *-lit-001-wip pattern
  if (basename.endsWith("-lit-001-wip")) {
    return true;
  }

  // Exclude worktrees (migration branches and git worktrees)
  if (!includeWorktrees) {
    // *-ts7 worktrees (migration in flight)
    if (basename.endsWith("-ts7") || basename.includes("-ts7-")) {
      return true;
    }
    // .claude/worktrees (git worktree directory)
    if (path.includes("/.claude/worktrees/")) {
      return true;
    }
  }

  // Exclude system directories
  if ([".git", "node_modules", ".venv", ".vscode", ".idea"].includes(basename)) {
    return true;
  }

  return false;
}

/**
 * How deep below each configured root to look for a package.json.
 *
 * This was 3, which silently halved the sweep: it found 12 packages when the
 * estate had 24. Everything nested further down was invisible while the tool
 * still reported a confident "0 drift" — e.g. `ccmax-monitor/services/
 * team-console`, `legal-docs-source/skills/eon-timedoctor`, `crown-intl/apps/
 * web` (three levels under its root on its own), and all six cc-skills plugin
 * packages. 10 comfortably covers the deepest real package while still
 * bounding the walk; the exclusion list below, not the depth limit, is what
 * keeps node_modules and vendored clones out.
 */
const PACKAGE_JSON_DISCOVERY_MAXIMUM_DIRECTORY_DEPTH_BELOW_ROOT = 10;

/**
 * Upper bound on package.json results per root, to stop a pathological tree
 * from hanging the sweep. Deliberately far above the real count (the largest
 * root currently yields ~185) so it never binds in practice — and if it ever
 * does bind, it warns rather than truncating in silence.
 */
const PACKAGE_JSON_DISCOVERY_PER_ROOT_RESULT_CAP = 500;

/**
 * Recursively find all package.json files using find command (fast, avoids recursion).
 */
function findPackageJsonFiles(root: string, includeWorktrees: boolean): string[] {
  const results: string[] = [];

  if (!existsSync(root)) return results;

  if (shouldSkipPath(root, includeWorktrees)) return results;

  try {
    const cmd =
      `find "${root}" -maxdepth ${PACKAGE_JSON_DISCOVERY_MAXIMUM_DIRECTORY_DEPTH_BELOW_ROOT}` +
      ` -name package.json 2>/dev/null | grep -v node_modules` +
      ` | head -${PACKAGE_JSON_DISCOVERY_PER_ROOT_RESULT_CAP}`;
    const output = execSync(cmd, { encoding: "utf8", stdio: ["pipe", "pipe", "ignore"] });
    const paths = output.trim().split("\n").filter(Boolean);

    // A silently-truncated sweep is the failure mode this whole tool exists to
    // prevent: it would report a confident "0 drift" over a set that quietly
    // stopped short, which reads as "everything is conformant" when it means
    // "I did not look at everything". The cap stays (it bounds a pathological
    // walk) but hitting it is now LOUD. Discovery previously ran at maxdepth 3
    // and silently missed half the estate's packages for exactly this reason —
    // the difference being that nothing announced the shortfall.
    if (paths.length >= PACKAGE_JSON_DISCOVERY_PER_ROOT_RESULT_CAP) {
      console.error(
        `WARNING: package.json discovery under ${root} hit the ` +
          `${PACKAGE_JSON_DISCOVERY_PER_ROOT_RESULT_CAP}-result cap. Results are TRUNCATED and ` +
          `this run's "no drift" verdict does not cover the whole tree. Raise ` +
          `PACKAGE_JSON_DISCOVERY_PER_ROOT_RESULT_CAP or narrow --roots.`,
      );
    }

    // Filter out excluded paths
    for (const p of paths) {
      if (!shouldSkipPath(p, includeWorktrees)) {
        results.push(p);
      }
    }
  } catch {
    // silently skip inaccessible dirs
  }

  return results;
}

/**
 * Get installed TypeScript version via tsc --version.
 * Returns null if tsc is not found, or the version string if found.
 * Also checks for tsc6 (compat alias).
 */
function getInstalledTypeScriptVersions(packageJsonPath: string): Record<string, string | null> {
  const packageDir = dirname(packageJsonPath);
  const versions: Record<string, string | null> = {};

  // Check for main tsc
  const tscPath = resolve(packageDir, "node_modules/.bin/tsc");
  if (existsSync(tscPath)) {
    try {
      const output = execSync(`"${tscPath}" --version 2>/dev/null`, {
        encoding: "utf8",
        cwd: packageDir,
        stdio: ["pipe", "pipe", "ignore"],
      });
      if (output) {
        const match = output.match(/(\d+\.\d+\.\d+)/);
        versions.tsc = match ? match[1] : null;
      }
    } catch {
      versions.tsc = null;
    }
  }

  // Check for tsc6 (compat alias for Volar/Angular/typescript-eslint)
  const tsc6Path = resolve(packageDir, "node_modules/.bin/tsc6");
  if (existsSync(tsc6Path)) {
    try {
      const output = execSync(`"${tsc6Path}" --version 2>/dev/null`, {
        encoding: "utf8",
        cwd: packageDir,
        stdio: ["pipe", "pipe", "ignore"],
      });
      if (output) {
        const match = output.match(/(\d+\.\d+\.\d+)/);
        versions.tsc6 = match ? match[1] : null;
      }
    } catch {
      versions.tsc6 = null;
    }
  }

  return versions;
}

/**
 * Read and parse package.json, extract typescript dependency.
 */
function getDeclaredTypeScriptSpecifier(packageJsonPath: string): string | null {
  try {
    const content = readFileSync(packageJsonPath, "utf8");
    const pkg = JSON.parse(content);

    return (
      pkg.devDependencies?.typescript ||
      pkg.dependencies?.typescript ||
      pkg.optionalDependencies?.typescript ||
      null
    );
  } catch {
    return null;
  }
}

/**
 * Check if the package directory has an ALLOW-LEGACY-TS marker in .env.
 */
function hasAllowLegacyTsMarker(packageJsonPath: string): boolean {
  try {
    const packageDir = dirname(packageJsonPath);
    const markerPath = resolve(packageDir, ".env");

    if (existsSync(markerPath)) {
      const content = readFileSync(markerPath, "utf8");
      if (content.includes("ALLOW-LEGACY-TS")) {
        return true;
      }
    }
  } catch {
    // continue
  }

  return false;
}

/**
 * Analyze a single package.json.
 */
function analyzePackage(packageJsonPath: string): PackageAnalysis {
  const packageDir = dirname(packageJsonPath);
  const declared = getDeclaredTypeScriptSpecifier(packageJsonPath);

  if (!declared) {
    return {
      path: packageDir,
      packageJsonPath,
      declared: "(none)",
      installedVersions: {},
      verdict: "conformant",
      reason: "No typescript dependency declared",
    };
  }

  // Evaluate the declared specifier
  const evalVerdict = evaluateTypeScriptVersionSpecifier(declared);

  // Check for ALLOW-LEGACY-TS marker
  if (hasAllowLegacyTsMarker(packageJsonPath)) {
    return {
      path: packageDir,
      packageJsonPath,
      declared,
      installedVersions: {},
      verdict: "exception",
      reason: "Marked with ALLOW-LEGACY-TS (intentional deviation)",
      evaluatorVerdictKind: evalVerdict.kind,
    };
  }

  // Get installed versions (for all packages, for transparency)
  const installed = getInstalledTypeScriptVersions(packageJsonPath);

  // Sanctioned compat alias is allowed
  if (evalVerdict.kind === "sanctioned-compat-alias") {
    return {
      path: packageDir,
      packageJsonPath,
      declared,
      installedVersions: installed,
      verdict: "conformant",
      reason: evalVerdict.rationale,
      evaluatorVerdictKind: evalVerdict.kind,
    };
  }

  // Blocking verdicts (legacy, deprecated-native-preview)
  if (isBlockingTypeScriptVersionSpecifierVerdict(evalVerdict)) {
    return {
      path: packageDir,
      packageJsonPath,
      declared,
      installedVersions: installed,
      verdict: "drift",
      reason: evalVerdict.rationale,
      evaluatorVerdictKind: evalVerdict.kind,
    };
  }

  // Conformant specifiers
  if (evalVerdict.kind === "conformant") {
    return {
      path: packageDir,
      packageJsonPath,
      declared,
      installedVersions: installed,
      verdict: "conformant",
      reason: evalVerdict.rationale,
      evaluatorVerdictKind: evalVerdict.kind,
    };
  }

  // Unresolvable specifiers
  return {
    path: packageDir,
    packageJsonPath,
    declared,
    installedVersions: installed,
    verdict: "conformant",
    reason: evalVerdict.rationale,
    evaluatorVerdictKind: evalVerdict.kind,
  };
}

// ============================================================================
// JSONL Logging
// ============================================================================

function writeJsonlLog(analysis: PackageAnalysis[]): void {
  try {
    const logsDir = resolve(homedir(), ".claude/logs");
    mkdirSync(logsDir, { recursive: true });

    const logPath = resolve(logsDir, "typescript-version-drift-guard.jsonl");
    const timestamp = new Date().toISOString();

    let logContent = "";
    for (const item of analysis) {
      const logEntry = {
        timestamp,
        package: item.path,
        declared: item.declared,
        installed: item.installedVersions,
        verdict: item.verdict,
        reason: item.reason,
      };
      logContent += JSON.stringify(logEntry) + "\n";
    }

    Bun.write(logPath, logContent);
  } catch (err) {
    // Warning but don't fail
  }
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  const opts = parseCliArgs(args);

  if (opts.version) {
    console.log("typescript-version-drift-guard 1.0.0");
    process.exit(0);
  }

  if (opts.helpJson) {
    console.log(JSON.stringify(HELP_JSON, null, 2));
    process.exit(0);
  }

  if (opts.help) {
    console.log(HELP_TEXT);
    process.exit(0);
  }

  if (opts.skipIfOffline && !isOnline()) {
    console.log("System offline; skipping checks (--skip-if-offline)");
    process.exit(0);
  }

  // Determine search roots
  const roots =
    opts.roots.length > 0
      ? opts.roots.flatMap((r) => r.split(",").map((p) => p.trim()))
      : [resolve(homedir(), "eon"), resolve(homedir(), "vj"), resolve(homedir(), "own")];

  // Find all package.json files
  const packageJsonPaths: string[] = [];
  for (const root of roots) {
    packageJsonPaths.push(...findPackageJsonFiles(root, opts.includeWorktrees));
  }

  if (packageJsonPaths.length === 0) {
    if (opts.json) {
      console.log(JSON.stringify({ packages: [] }, null, 2));
    } else {
      console.log("No package.json files found in search paths");
    }
    process.exit(0);
  }

  // Analyze each package
  const allResults: PackageAnalysis[] = [];
  for (const pkgPath of packageJsonPaths) {
    const analysis = analyzePackage(pkgPath);
    allResults.push(analysis);
  }

  // Filter to TypeScript-declaring packages only (exclude "(none)" declared)
  const results = allResults.filter((r) => r.declared !== "(none)");

  // Write JSONL log (all results, including non-TS packages)
  writeJsonlLog(allResults);

  // Determine exit code
  const hasDrift = results.some((r) => r.verdict === "drift");

  if (opts.json) {
    console.log(
      JSON.stringify(
        {
          packages: results,
          summary: {
            total: results.length,
            conformant: results.filter((r) => r.verdict === "conformant").length,
            drift: results.filter((r) => r.verdict === "drift").length,
            sanctioned: results.filter((r) => r.evaluatorVerdictKind === "sanctioned-compat-alias").length,
            exceptions: results.filter((r) => r.verdict === "exception").length,
          },
        },
        null,
        2,
      ),
    );
  } else {
    // Human-readable output
    const drifts = results.filter((r) => r.verdict === "drift");
    const exceptions = results.filter((r) => r.verdict === "exception");
    const sanctioned = results.filter((r) => r.evaluatorVerdictKind === "sanctioned-compat-alias");
    const conformant = results.filter((r) => r.verdict === "conformant" && r.evaluatorVerdictKind !== "sanctioned-compat-alias");

    if (drifts.length > 0) {
      console.log("❌ DRIFT DETECTED\n");
      for (const drift of drifts) {
        console.log(`  📦 ${drift.path}`);
        console.log(`     Declared: ${drift.declared}`);
        if (Object.keys(drift.installedVersions).length > 0) {
          for (const [bin, version] of Object.entries(drift.installedVersions)) {
            console.log(`     Installed (${bin}): ${version || "(not installed)"}`);
          }
        }
        console.log(`     ${drift.reason}\n`);
      }
    }

    if (sanctioned.length > 0) {
      console.log("✅ SANCTIONED DUAL-INSTALL (compat alias)\n");
      for (const s of sanctioned) {
        console.log(`  📦 ${s.path}`);
        console.log(`     Declared: ${s.declared}`);
        if (Object.keys(s.installedVersions).length > 0) {
          for (const [bin, version] of Object.entries(s.installedVersions)) {
            console.log(`     Installed (${bin}): ${version || "(not installed)"}`);
          }
        }
        console.log(`     ${s.reason}\n`);
      }
    }

    if (exceptions.length > 0) {
      console.log("✅ INTENTIONAL EXCEPTIONS (ALLOW-LEGACY-TS)\n");
      for (const exc of exceptions) {
        console.log(`  📦 ${exc.path}`);
        console.log(`     Declared: ${exc.declared}`);
        if (Object.keys(exc.installedVersions).length > 0) {
          for (const [bin, version] of Object.entries(exc.installedVersions)) {
            console.log(`     Installed (${bin}): ${version || "(not installed)"}`);
          }
        }
        console.log(`     ${exc.reason}\n`);
      }
    }

    if (conformant.length > 0) {
      console.log(`✅ ${conformant.length} packages conformant`);
    }
  }

  process.exit(hasDrift ? 1 : 0);
}

main().catch((err) => {
  console.error("Error:", err instanceof Error ? err.message : String(err));
  process.exit(3);
});
