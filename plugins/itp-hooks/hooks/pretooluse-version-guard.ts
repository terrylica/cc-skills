#!/usr/bin/env bun
/**
 * PreToolUse hook: Version SSoT Guard (iter-85 orchestrator-inlined)
 *
 * Blocks ANY hardcoded version numbers in markdown documentation.
 * Forces use of "<version>" placeholder pattern.
 * Universal across all projects - Rust, Python, JavaScript, etc.
 *
 * Plan Mode: Automatically skipped when Claude is in planning phase.
 * This prevents blocking during /plan exploration where version references
 * in plan files are acceptable.
 *
 * Usage:
 *   Installed via /itp:hooks install (formerly .mjs, converted to .ts in iter-85
 *   as part of the in-process orchestrator migration so the orchestrator can
 *   import the classifier with full TypeScript type-checking).
 *   Escape hatch: # SSoT-OK comment in file
 *
 * ADR: /docs/adr/2026-02-05-plan-mode-detection-hooks.md
 *
 * Iter-85 dual-use contract:
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-version-guard.ts < payload.json` runs main() under
 *     the `import.meta.main` guard, reads stdin, emits allow/deny to stdout.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyVersionGuardForOrchestrator` and
 *     invokes it directly inside the single bun process — no per-subhook
 *     bun cold-start cost. The classifier MUST conform to the
 *     PreToolUseSubhookContract: pure async function, no stdin/stdout/exit
 *     side-effects, returns a PreToolUseSubhookDecision object.
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
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";

// ============================================================================
// VERSION PATTERNS - Expanded based on codebase audit
// ============================================================================

const HARDCODED_VERSION_DETECTION_REGEX_PATTERNS: readonly RegExp[] = [
  // Rust/TOML: package = "1.2.3" or version = "1.2.3" (semver only, NOT 2-segment or 1-segment)
  /=\s*"(\d+\.\d+\.\d+)"/g,

  // Python: package==1.2.3, ~=1.2.3
  /==\s*(\d+\.\d+\.\d+)/g,
  /~=\s*(\d+\.\d+\.\d+)/g,

  // JSON: "version": "1.2.3"
  /"version"\s*:\s*"(\d+\.\d+\.\d+)"/g,

  // Prose patterns: Version 1.2.3, **Version**: 1.2.3
  /Version:\s*(\d+\.\d+\.\d+)/gi,
  /\*\*Version\*\*:\s*v?(\d+\.\d+\.\d+)/gi,

  // Exact version pin in prose: v1.2.3 (but NOT v1.2.3+ which is a minimum requirement)
  /\bv(\d+\.\d+\.\d+)\b(?!\+)/g,

  // Pre-release patterns: 1.2.3-alpha.1, 1.2.3-beta.2, 1.2.3-rc.1
  /(\d+\.\d+\.\d+)-(alpha|beta|rc)(\.\d+)?/gi,

  // Calendar versioning: 2024.9.5
  /\b(\d{4}\.\d{1,2}\.\d{1,2})\b/g,
];

// Removed patterns (false positive sources):
// - /=\s*"(\d+\.\d+)"/g — caught XML plist version="1.0" boilerplate
// - /=\s*"(\d+)"/g — caught any ="1" including XML attributes
// - /\bv?(\d+\.\d+\.\d+)\+/g — v1.2.3+ is a minimum requirement, not a pin
// - />=\s*(\d+\.\d+\.\d+)/g — >= is a constraint, not a pin

// ============================================================================
// ALLOWED PATTERNS & EXCLUDED PATHS
// ============================================================================

// Iter-108: migrated to the iter-107 canonical shared escape-hatch-marker
// detection helper. Behavior-preserving: marker token `SSoT-OK` (mixed-case,
// abbreviated from Single-Source-of-Truth) detected file-wide. Default
// case-sensitivity mode matches the pre-iter-108 `/#\s*SSoT-OK/` regex
// (no /i flag — case-sensitive). The `#` comment-prefix anchor from the
// pre-iter-108 regex is dropped because the SSoT-OK marker token never
// collides with code identifiers; substring match against the literal
// token is safe and works equally for `#`-comments (.py, .toml, .yaml),
// `//`-comments (.ts, .js, .rs, .go), and any other comment syntax.
import {
  hasFileWideEscapeHatchMarkerInContent,
  type EscapeHatchMarkerDetectionConfiguration,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
const VERSION_GUARD_SSOT_OK_ESCAPE_HATCH_CONFIGURATION: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "caseSensitivityMode" | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: "SSoT-OK",
  caseSensitivityMode: "CASE_SENSITIVE",
};

// Paths where historical versions are OK
const HARDCODED_VERSION_EXEMPT_FILE_PATH_REGEX_PATTERNS: readonly RegExp[] = [
  /\/\.[^/]+\//i, // Any dot-prefixed directory (.planning/, .claude/, .github/, etc.)
  /CHANGELOG/i, // All changelogs
  /MIGRATION/i, // Migration guides
  /\/archive\//i, // Archived docs
  /\/milestones\//i, // Milestone tracking
  /\/planning\//i, // Planning documents
  /\/plans\//i, // Claude Code plan files
  /\/reports\//i, // Generated reports
  /\/outputs?\//i, // Output directories (output/ or outputs/)
  /\/adr\//i, // Architecture Decision Records
  /ADR-\d+/i, // ADR files by number
  /HISTORY/i, // History files
  /node_modules/i, // Never check node_modules
  /\/crates\/[^/]+\/README\.md$/i, // Crate-level READMEs
  /\/development\//i, // Development docs
  /^\/tmp\//i, // Temp files (gh issue body-file, scratch docs)
  /LOOP_CONTRACT.*\.md$/i, // Autonomous-loop contract files (self-revising version field is the contract's own, not a package)
];

// Fenced code-block strip pattern: xml/html/plist content contains boilerplate
// like <?xml version="1.0"?> that aren't version pins
const FENCED_XML_HTML_PLIST_CODE_BLOCK_STRIP_REGEX = /```(?:xml|html|plist)\b[\s\S]*?```/gi;

// ============================================================================
// PURE CLASSIFIER (iter-85 orchestrator-inlineable contract)
// ============================================================================

const logger = createHookLogger("VERSION-GUARD");

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Identical logic to the standalone main() below, but factored out so the
 * iter-84 in-process orchestrator can invoke it directly without subprocess-
 * spawning this file (which would cost a full bun cold-start per Write|Edit
 * and defeat the orchestrator's purpose — iter-80 measured ~44ms floor).
 *
 * MUST NOT call allow()/deny() or touch stdin/stdout/process.exit. Returns
 * a decision object that the caller (standalone main OR orchestrator)
 * translates to the appropriate Claude Code response shape.
 *
 * Iter-85 hardening: the global RegExp lastIndex shared-state hazard
 * (regex.lastIndex persists across calls when reused) is eliminated by
 * cloning each pattern with `new RegExp(p.source, p.flags)` inside the
 * loop. This is defensive — the original code reset `pattern.lastIndex = 0`
 * BEFORE the loop but the clone-per-call approach is strictly safer and
 * still O(1) per call.
 */
export async function classifyVersionGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input = {} } = input;

  // Iter-102: route through canonical contract helper (closes iter-101 residual gap).
  if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(tool_name)) {
    return ALLOW_DECISION;
  }
  // Iter-102 staged-migration short-circuit: MultiEdit payload-shape
  // adaptation is iter-103+ per-classifier work. Preserves status quo.
  if (tool_name === "MultiEdit") {
    return ALLOW_DECISION;
  }

  // Early exit: Skip in plan mode
  // Plan files and planning phase should not be blocked by version checks
  const planContext = isPlanMode(input, { checkPermission: true, checkPath: true });
  if (planContext.inPlanMode) {
    logger.debug("Skipping version check in plan mode", {
      hook_event: "PreToolUse",
      tool_name,
      trace_id: input.tool_use_id,
      reason: planContext.reason,
      permission_mode: planContext.permissionMode,
    });
    return ALLOW_DECISION;
  }

  const filePath = (tool_input.file_path as string) || "";
  const content = ((tool_input.content as string) || (tool_input.new_string as string) || "");

  // Early exit: Only check markdown files
  if (!filePath.endsWith(".md")) {
    return ALLOW_DECISION;
  }

  // Early exit: Excluded paths (changelogs, migrations, etc.)
  if (HARDCODED_VERSION_EXEMPT_FILE_PATH_REGEX_PATTERNS.some((p) => p.test(filePath))) {
    return ALLOW_DECISION;
  }

  // Early exit: Escape hatch comment present (iter-108: delegated to
  // canonical shared helper; behavior-preserving file-wide marker scan).
  if (hasFileWideEscapeHatchMarkerInContent(content, VERSION_GUARD_SSOT_OK_ESCAPE_HATCH_CONFIGURATION)) {
    return ALLOW_DECISION;
  }

  // NOTE: Placeholder pattern does NOT exempt file from checking (STRICT mode)
  // Block if ANY hardcoded version, even if placeholder is also present

  // Strip content inside fenced code blocks with xml/html/plist language tags
  // These contain boilerplate like <?xml version="1.0"?> that aren't version pins
  const strippedContent = content.replace(
    FENCED_XML_HTML_PLIST_CODE_BLOCK_STRIP_REGEX,
    "",
  );

  // Find hardcoded versions. Iter-85 hardening: clone each pattern with fresh
  // lastIndex to defend against the global-RegExp shared-state hazard — if
  // a previous call set lastIndex via matchAll on a non-empty string, the
  // next call's matchAll could skip matches. Cloning per-call guarantees
  // a fresh starting position.
  const versionsDetectedInProposedMarkdownContent = new Set<string>();
  for (const pattern of HARDCODED_VERSION_DETECTION_REGEX_PATTERNS) {
    const freshPatternClone = new RegExp(pattern.source, pattern.flags);
    for (const match of strippedContent.matchAll(freshPatternClone)) {
      if (match[1]) versionsDetectedInProposedMarkdownContent.add(match[1]);
    }
  }

  // No versions found = allow
  if (versionsDetectedInProposedMarkdownContent.size === 0) {
    return ALLOW_DECISION;
  }

  // Build deny reason
  const fileName = filePath.split("/").pop();
  const versionList = [...versionsDetectedInProposedMarkdownContent]
    .map((v) => `"${v}"`)
    .join(", ");
  const denyReason = [
    `[VERSION-GUARD] Hardcoded version in ${fileName}`,
    "",
    `Found: ${versionList}`,
    "",
    "Fix by using one of:",
    `  my-package = "<version>"  (placeholder pattern)`,
    "  See [crates.io](link)     (registry link)",
    "  # SSoT-OK                 (escape hatch comment)",
    "",
    "SSoT: Version only in Cargo.toml/pyproject.toml/package.json",
  ].join("\n");

  return denyDecision(denyReason);
}

// ============================================================================
// STANDALONE MAIN (backward-compat for direct CLI invocation)
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("VERSION-GUARD");
  if (!input) return;

  const decision = await classifyVersionGuardForOrchestrator(input);

  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      // version-guard doesn't currently use ask; treat as deny for safety
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// Only run main() when this file is invoked directly. import.meta.main is
// true only for the entry-point script; when the orchestrator imports
// classifyVersionGuardForOrchestrator, this branch does NOT fire.
if (import.meta.main) {
  main().catch((e: unknown) => {
    const message = e instanceof Error ? e.message : String(e);
    trackHookError("pretooluse-version-guard", `Unhandled error: ${message}`);
    allow();
  });
}
