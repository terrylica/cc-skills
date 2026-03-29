#!/usr/bin/env bun
/**
 * PreToolUse hook: Inline Ignore Guard
 *
 * Blocks Write/Edit that introduce inline lint/type ignore comments.
 * Policy: suppressions belong in config files, not scattered in source.
 *
 * Detected patterns:
 *   Python: noqa, type-ignore, ty-ignore, ruff-noqa (INLINE-IGNORE-OK)
 *   JS/TS:  eslint-disable, biome-ignore, oxlint-ignore (INLINE-IGNORE-OK)
 *
 * Hierarchy enforced:
 *   1. Fix the error (preferred)
 *   2. Config-level ignore (ruff.toml, ty.toml, oxlint.json, biome.json)
 *   3. NEVER inline ignore
 *
 * Escape hatch: # INLINE-IGNORE-OK or // INLINE-IGNORE-OK on the same line
 *
 * For Edit tool: only denies if net-new ignores are introduced
 * (count in new_string > count in old_string).
 */

import {
  parseStdinOrAllow,
  allow,
  deny,
  isPlanMode,
  trackHookError,
} from "./pretooluse-helpers.ts";

// ============================================================================
// Constants
// ============================================================================

const PYTHON_EXTENSIONS = new Set([".py", ".pyi"]);
const JS_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".mjs", ".jsx"]);

const ESCAPE_HATCH = /INLINE-IGNORE-OK/;

// Python inline ignore patterns
const PYTHON_IGNORE_PATTERNS: RegExp[] = [
  /# noqa\b/,
  /# ruff:\s*noqa\b/,
  /# type:\s*ignore\b/,
  /# ty:\s*ignore\b/,
];

// JS/TS inline ignore patterns
const JS_IGNORE_PATTERNS: RegExp[] = [
  /\/\/\s*eslint-disable-next-line\b/,
  /\/\/\s*eslint-disable-line\b/,
  /\/\*\s*eslint-disable\b/,
  /\/\/\s*biome-ignore\b/,
  /\/\/\s*oxlint-ignore\b/,
];

// ============================================================================
// Detection
// ============================================================================

function getExtension(filePath: string): string {
  const lastDot = filePath.lastIndexOf(".");
  return lastDot === -1 ? "" : filePath.slice(lastDot);
}

function getPatternsForExtension(ext: string): RegExp[] | null {
  if (PYTHON_EXTENSIONS.has(ext)) return PYTHON_IGNORE_PATTERNS;
  if (JS_EXTENSIONS.has(ext)) return JS_IGNORE_PATTERNS;
  return null;
}

interface IgnoreMatch {
  line: string;
  lineNumber: number;
  pattern: string;
}

function findInlineIgnores(content: string, patterns: RegExp[]): IgnoreMatch[] {
  const matches: IgnoreMatch[] = [];
  const lines = content.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Skip lines with escape hatch
    if (ESCAPE_HATCH.test(line)) continue;

    for (const pattern of patterns) {
      if (pattern.test(line)) {
        matches.push({
          line: line.trim(),
          lineNumber: i + 1,
          pattern: pattern.source,
        });
        break; // One match per line is enough
      }
    }
  }

  return matches;
}

function countInlineIgnores(content: string, patterns: RegExp[]): number {
  return findInlineIgnores(content, patterns).length;
}

// ============================================================================
// Fix Guidance
// ============================================================================

function buildDenyMessage(matches: IgnoreMatch[], filePath: string, ext: string): string {
  const sample = matches.slice(0, 3);
  const sampleLines = sample
    .map((m) => `  Line ${m.lineNumber}: ${m.line}`)
    .join("\n");
  const moreCount = matches.length - sample.length;
  const moreMsg = moreCount > 0 ? `\n  ...and ${moreCount} more` : "";

  const configGuidance = PYTHON_EXTENSIONS.has(ext)
    ? `  ruff: Add to [lint.per-file-ignores] in ruff.toml or pyproject.toml
    Example: "${filePath}" = ["E501"]
  ty: Add to [[overrides]] in ty.toml with include pattern
    Example: [[overrides]]
             include = ["${filePath}"]
             [overrides.rules]
             rule-name = "ignore"`
    : `  oxlint: Add to .oxlintrc.json "rules" section
  biome: Add to biome.json "linter.rules" section
    Example: { "linter": { "rules": { "category": { "ruleName": "off" } } } }`;

  return `[INLINE-IGNORE-GUARD] Found ${matches.length} inline ignore comment(s) in proposed content:

${sampleLines}${moreMsg}

POLICY: Inline ignores are FORBIDDEN. Follow this hierarchy:

1. FIX THE ERROR (preferred):
   - Add type annotations, casts, None checks
   - Use __all__ for re-exports (not # noqa: F401)
   - Add str() casts for union types from Polars/dict.get()

2. CONFIG-LEVEL IGNORE (only for tool/library limitations):
${configGuidance}

3. NEVER: Inline # noqa / # type: ignore / // eslint-disable

Escape hatch: Add "INLINE-IGNORE-OK" on the same line if truly unavoidable.`;
}

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow();
  if (!input) return;

  // Only handle Write/Edit
  const toolName = input.tool_name;
  if (toolName !== "Write" && toolName !== "Edit") {
    return allow();
  }

  // Plan mode skip
  const planContext = isPlanMode(input, { checkPermission: true, checkPath: true });
  if (planContext.inPlanMode) {
    return allow();
  }

  const filePath = input.tool_input.file_path;
  if (!filePath) return allow();

  // Check extension
  const ext = getExtension(filePath);
  const patterns = getPatternsForExtension(ext);
  if (!patterns) return allow();

  try {
    if (toolName === "Write") {
      // Write: scan full content
      const content = input.tool_input.content;
      if (!content || typeof content !== "string") return allow();

      const matches = findInlineIgnores(content, patterns);
      if (matches.length > 0) {
        return deny(buildDenyMessage(matches, filePath, ext));
      }
    } else {
      // Edit: only deny if net-new ignores
      const newString = input.tool_input.new_string;
      const oldString = input.tool_input.old_string;
      if (!newString || typeof newString !== "string") return allow();

      const newCount = countInlineIgnores(newString, patterns);
      const oldCount = oldString && typeof oldString === "string"
        ? countInlineIgnores(oldString, patterns)
        : 0;

      if (newCount > oldCount) {
        const matches = findInlineIgnores(newString, patterns);
        return deny(buildDenyMessage(matches, filePath, ext));
      }
    }
  } catch (err: unknown) {
    trackHookError(
      "pretooluse-inline-ignore-guard",
      err instanceof Error ? err.message : String(err),
    );
  }

  return allow();
}

main().catch(() => {
  process.exit(0);
});
