#!/usr/bin/env bun
/**
 * PreToolUse hook: TypeScript Legacy Install Command Guard
 *
 * Blocks package-manager commands that would install a pre-7 TypeScript version.
 *
 * Covers: npm install/add/update/up, bun add/update, pnpm add/update, yarn add/upgrade
 *
 * Detects `typescript@<spec>` tokens (and `@typescript/native-preview@<spec>`)
 * anywhere in the command, including inside quotes. Reuses the shared TypeScript
 * version evaluator (lib/typescript-version-specifier-minimum-major-policy-evaluator.ts)
 * to determine if a specifier is legacy, so the guard cannot drift from the
 * package.json editor guard.
 *
 * Escape hatch:
 *   - Environment: `ALLOW_LEGACY_TS=1 npm i typescript@5.9.3`
 *   - Inline marker: `npm i typescript@5.9.3 # ALLOW-LEGACY-TS`
 *
 * SSoT: ~/.claude/typescript-latest-CLAUDE.md
 * Hub row: ~/.claude/CLAUDE.md § "TypeScript 7 ONLY"
 *
 * ADR: (pending) iter-92 TypeScript 7 enforcement doctrine
 *
 * Usage:
 *   Installed via hooks.json in itp-hooks plugin
 */

import {
  allow,
  deny,
  parseStdinOrAllow,
  isPlanMode,
  createHookLogger,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  evaluateTypeScriptVersionSpecifier,
  isBlockingTypeScriptVersionSpecifierVerdict,
  type TypeScriptVersionSpecifierVerdict,
} from "./lib/typescript-version-specifier-minimum-major-policy-evaluator.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

// ────────────────────────────────────────────────────────────────────────
// Shell parsing helpers (extract package specifiers from command)
// ────────────────────────────────────────────────────────────────────────

/**
 * Match patterns like:
 *   `typescript@5.9.3`
 *   `@typescript/native-preview@^6.0`
 *   `@typescript/typescript6@^6.0.2`
 *   Inside npm: prefix: `npm:typescript@^6` inside a larger specifier
 *
 * Note: This pattern is used with matchAll(), so we construct it fresh each time
 * to avoid lastIndex state issues with the global flag.
 */
function getTypeScriptPackageSpecifierPattern(): RegExp {
  return /@?typescript[-/\w]*@[^\s"']+/gi;
}

/**
 * Extract all TypeScript-family package specifier tokens from a shell command.
 * Handles tokens inside quotes and naked on the command line.
 * Does NOT execute the command — purely lexical.
 *
 * Returns: array of objects { token, packageName, specifier }
 *   - token: the full matched substring from the command (e.g., `typescript@5.9.3`)
 *   - packageName: the package name part (e.g., `typescript`, `@typescript/native-preview`)
 *   - specifier: the version/range part (e.g., `5.9.3`, `^6.0.2`)
 *
 * Examples:
 *   `npm i typescript@5.9.3` → [{ token: "typescript@5.9.3", packageName: "typescript", specifier: "5.9.3" }]
 *   `bun add -d @typescript/typescript6@^6.0.2` → [{ token: "@typescript/typescript6@^6.0.2", packageName: "@typescript/typescript6", specifier: "^6.0.2" }]
 *   `npm i typescript@npm:@typescript/typescript6@^6.0.2` → [{ token: "typescript@npm:...", packageName: "typescript", specifier: "npm:@typescript/typescript6@^6.0.2" }]
 */
function extractTypeScriptPackageSpecifiers(command: string): Array<{
  token: string;
  packageName: string;
  specifier: string;
}> {
  const results: Array<{ token: string; packageName: string; specifier: string }> = [];

  for (const match of command.matchAll(getTypeScriptPackageSpecifierPattern())) {
    const token = match[0];

    // Split on the first `@` (after the optional leading `@` for scoped packages)
    // Examples:
    //   `typescript@5.9.3` → pkg=`typescript`, spec=`5.9.3`
    //   `@typescript/native-preview@^6.0` → pkg=`@typescript/native-preview`, spec=`^6.0`
    //   `@typescript/typescript6@^6.0.2` → pkg=`@typescript/typescript6`, spec=`^6.0.2`

    const lastAtSignIndex = token.lastIndexOf("@");
    if (lastAtSignIndex <= 0) {
      // No `@` after the package name (malformed), skip
      continue;
    }

    const packageName = token.slice(0, lastAtSignIndex);
    const specifier = token.slice(lastAtSignIndex + 1);

    if (!packageName || !specifier) {
      continue;
    }

    results.push({ token, packageName, specifier });
  }

  return results;
}

// ────────────────────────────────────────────────────────────────────────
// Package-manager command detection
// ────────────────────────────────────────────────────────────────────────

/**
 * Determine if a Bash command is an install-shaped invocation.
 * Returns true if the command's first non-option argument matches an install verb.
 *
 * Covers:
 *   - npm: `install`, `i`, `add`, `update`, `up`
 *   - bun: `add`, `update`, `up`
 *   - pnpm: `add`, `install`, `i`, `update`, `up`
 *   - yarn: `add`, `upgrade`, `install`, `up`
 */
function isInstallCommand(command: string): boolean {
  // Fast path: skip commands that don't mention install-like verbs
  if (!/\b(npm|bun|pnpm|yarn|install|add|update|upgrade|i|up)\b/i.test(command)) {
    return false;
  }

  // Extract the first "word" argument (tool name) and check if it's a package manager
  let i = 0;
  let toolName = "";

  // Skip leading whitespace
  while (i < command.length && /\s/.test(command[i])) i++;

  // Read the tool name (npm, bun, pnpm, yarn, or similar)
  while (i < command.length && !/\s/.test(command[i])) {
    toolName += command[i];
    i++;
  }

  const normalizedTool = toolName.toLowerCase();
  if (!/(npm|bun|pnpm|yarn)$/.test(normalizedTool)) {
    return false;
  }

  // Skip whitespace after tool name
  while (i < command.length && /\s/.test(command[i])) i++;

  // Read the subcommand (install, add, update, etc.)
  let subcommand = "";
  while (i < command.length && !/\s/.test(command[i]) && command[i] !== "-") {
    subcommand += command[i];
    i++;
  }

  const normalizedSubcommand = subcommand.toLowerCase();
  const installVerbs = ["install", "i", "add", "update", "up", "upgrade"];

  return installVerbs.includes(normalizedSubcommand);
}

// ────────────────────────────────────────────────────────────────────────
// Denial message formatting
// ────────────────────────────────────────────────────────────────────────

/**
 * Format an actionable denial reason for a legacy TypeScript install.
 */
function formatInstallCommandDenialReason(
  offendingToken: string,
  verdict: TypeScriptVersionSpecifierVerdict,
  _command: string,
): string {
  const lines: string[] = [];

  lines.push(`🚫 Blocked: installing ${offendingToken}`);
  lines.push("");

  if (verdict.kind === "legacy" || verdict.kind === "deprecated-native-preview") {
    lines.push(verdict.rationale);
  } else {
    // Should not happen given the guard logic, but fail-open
    lines.push(`Reason: ${verdict.rationale}`);
  }

  lines.push("");

  lines.push(
    "✅ Fix: Use `typescript@latest` (or `typescript@next` for nightlies). " +
      "Commit the resulting lockfile.",
  );

  lines.push("");

  lines.push(
    "🔀 For compiler-embedding tools (Volar/Vue/Svelte/Astro, Angular templates, " +
      "typescript-eslint, ts-morph) that cannot run on TypeScript 7.0's missing programmatic API " +
      "(available 7.1+), use the sanctioned dual-install compat alias:",
  );
  lines.push("  npm i -D @typescript/typescript6@^6.0.2 @typescript/native@npm:typescript@latest");
  lines.push(
    "  Or bun: bun add -d @typescript/typescript6@^6.0.2 @typescript/native@npm:typescript@latest",
  );

  lines.push("");

  lines.push("🚪 Escape hatch (to skip this check):");
  lines.push("  • Environment: ALLOW_LEGACY_TS=1 npm install typescript@5.9.3");
  lines.push("  • Inline marker: npm install typescript@5.9.3 # ALLOW-LEGACY-TS");

  lines.push("");

  lines.push("📖 Doctrine SSoT: ~/.claude/typescript-latest-CLAUDE.md");

  return lines.join("\n");
}

// ────────────────────────────────────────────────────────────────────────
// Pure classifier (no stdin/stdout side effects)
// ────────────────────────────────────────────────────────────────────────

/**
 * Pure async classifier: does not touch stdin/stdout/process.exit.
 * Returns a decision that the orchestrator or standalone main() will act on.
 */
export async function classifyTypeScriptLegacyInstallCommandForOrchestrator(
  input: PreToolUseInput,
): Promise<{ verdict: "allow" } | { verdict: "deny"; reason: string }> {
  const { tool_name, tool_input = {} } = input;

  // Only check Bash commands
  if (tool_name !== "Bash") {
    return { verdict: "allow" };
  }

  // Skip in plan mode
  if (isPlanMode(input).inPlanMode) {
    return { verdict: "allow" };
  }

  const command = tool_input.command || "";

  // Not an install command — nothing to check
  if (!isInstallCommand(command)) {
    return { verdict: "allow" };
  }

  // Check for environment escape hatch
  if (command.startsWith("ALLOW_LEGACY_TS=1 ")) {
    return { verdict: "allow" };
  }

  // Check for inline marker escape hatch
  if (hasFileWideEscapeHatchMarkerInContent(command, { markerNameTokenIncludingSuffix: "ALLOW-LEGACY-TS" })) {
    return { verdict: "allow" };
  }

  // Extract all TypeScript specifiers from the command
  const specifiers = extractTypeScriptPackageSpecifiers(command);

  // Check each specifier against the policy
  for (const { token, packageName, specifier } of specifiers) {
    // Special case: @typescript/native-preview is deprecated (frozen, no longer maintained)
    // Block regardless of version
    if (packageName.toLowerCase().includes("@typescript/native-preview")) {
      const reason = formatInstallCommandDenialReason(
        token,
        {
          kind: "deprecated-native-preview",
          rationale: "`@typescript/native-preview` is FROZEN and deprecated now that TypeScript 7 ships the native compiler as `tsc` itself. Use `typescript@latest` (nightlies: `typescript@next`).",
        },
        command,
      );
      return { verdict: "deny", reason };
    }

    // Special case: the sanctioned compat alias. The evaluator will detect it,
    // but we also check the package name directly to be absolutely sure.
    if (packageName.toLowerCase().includes("@typescript/typescript6")) {
      // This is the compat alias for TypeScript 6.0 API (Volar/Angular/typescript-eslint/ts-morph)
      continue;
    }

    const verdict = evaluateTypeScriptVersionSpecifier(specifier);

    if (isBlockingTypeScriptVersionSpecifierVerdict(verdict)) {
      const reason = formatInstallCommandDenialReason(token, verdict, command);
      return { verdict: "deny", reason };
    }
  }

  // All specifiers passed; allow the command
  return { verdict: "allow" };
}

// ────────────────────────────────────────────────────────────────────────
// Standalone CLI entry point (with stdin/stdout/exit)
// ────────────────────────────────────────────────────────────────────────

async function main() {
  const input = await parseStdinOrAllow("pretooluse-typescript-legacy-install-command-guard");
  if (!input) return;

  try {
    const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(input);

    if (result.verdict === "allow") {
      allow();
    } else {
      deny(result.reason);
    }
  } catch (err) {
    const logger = createHookLogger("pretooluse-typescript-legacy-install-command-guard");
    const errorMessage = err instanceof Error ? err.message : String(err);
    logger.error("Error in classifier", { error: errorMessage });
    trackHookError("pretooluse-typescript-legacy-install-command-guard", errorMessage);
    allow();
  }
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError("pretooluse-typescript-legacy-install-command-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
