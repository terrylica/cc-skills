#!/usr/bin/env bun
/**
 * PreToolUse hook: macOS Launchd Native-Binary-Required Guard (iter-90 orchestrator-inlined)
 *
 * Blocks Write/Edit on macOS launchd-related files that would introduce
 * `/bin/bash` / `/bin/sh` / `.sh` shell-script-based service entry points
 * instead of compiled native binaries (Swift preferred).
 *
 * Why: Using `/bin/bash` in launchd plists shows a generic "bash" entry in
 * System Settings > Login Items, which is confusing and looks like
 * unidentified malware. Compiled Swift binaries show their actual executable
 * name (e.g., "calendar-announce").
 *
 * Detection scopes (only when `file_path` is under one of LAUNCHD_DIRS):
 *   1. Write of `.sh`/`.bash` file → DENY
 *   2. Write of `.plist` referencing `/bin/bash` or `/bin/sh` → DENY
 *   3. Write of `.plist` with a `.sh` script path in ProgramArguments → DENY
 *   4. Write of content starting with shebang `#!/usr/bin/bash` etc. → DENY
 *
 * Escape hatch: `# BASH-LAUNCHD-OK` (or `<!-- BASH-LAUNCHD-OK -->` in plists)
 * in proposed content OR in existing on-disk file (iter-15 fix: Edits whose
 * `new_string` targets a region that does NOT include the marker still
 * inherit the file-wide opt-out).
 *
 * Iter-90 dual-use contract (mirrors iter-85/86/87/88/89 migrations):
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-native-binary-guard.ts < payload.json` runs main()
 *     under `import.meta.main` guard. Standalone retains its raw-stdin
 *     keyword fastpath (LAUNCHD-RELATED-KEYWORD prefilter before JSON
 *     parsing) because in standalone-CLI mode that filter pays for itself
 *     by avoiding the JSON.parse on non-launchd payloads.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator`
 *     (with backward-compat alias `classifyNativeBinaryGuardForOrchestrator`)
 *     and invokes it directly in the single bun process. The orchestrator
 *     path replaces the raw-stdin keyword fastpath with an equivalent O(1)
 *     `isLaunchdRelatedDirectoryPath()` check on the already-parsed file_path
 *     (cheaper than the raw-stdin scan because input is already JSON-parsed).
 *
 * ════════════════════════════════════════════════════════════════════════
 *  PreToolUse additionalContext silent-drop NON-USE (iter-90 audit finding,
 *  GitHub #15664) — DEFENSE-IN-DEPTH COMMENT
 * ════════════════════════════════════════════════════════════════════════
 *
 * This classifier (and the orchestrator that imports it) MUST NOT set a
 * `hookSpecificOutput.additionalContext` field on PreToolUse output.
 * Per GitHub Issue #15664 (Dec 2025) + the official TypeScript SDK type
 * definitions, `additionalContext` on PreToolUse is silently ignored by
 * Claude Code — Claude never sees it. This is the same shape of silent-drop
 * bug iter-66 documented for Stop hooks. If you find yourself wanting to
 * inject "tool-specific guidance" from a PreToolUse hook, instead emit
 * `permissionDecision: "ask"` with the guidance text in
 * `permissionDecisionReason` — that path IS honored.
 *
 * Iter-90 sweep verified that NO classifier in the orchestrator registry
 * currently emits `additionalContext` on PreToolUse paths. This comment is
 * preventive scaffolding for future migrations.
 */

import {
  parseStdinOrAllow,
  deny,
  allow,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";

// ============================================================================
// Configuration
// ============================================================================

const NATIVE_BINARY_GUARD_HOOK_NAME = "NATIVE-BINARY-GUARD";

/**
 * Raw-stdin keyword prefilter (used ONLY by the standalone-CLI main() path).
 * If the raw stdin string lacks every one of these substrings the standalone
 * hook can short-circuit to ALLOW without paying JSON.parse. The orchestrator
 * path does not use this — it uses the structured `isLaunchdRelatedDirectoryPath`
 * check on `tool_input.file_path` instead.
 */
const NATIVE_BINARY_GUARD_STANDALONE_RAW_STDIN_LAUNCHD_RELATED_KEYWORD_PREFILTER: readonly string[] = [
  ".plist",
  ".sh",
  ".bash",
  "LaunchAgent",
  "LaunchDaemon",
  "automation/",
] as const;

/** Same-line `# BASH-LAUNCHD-OK` or `<!-- BASH-LAUNCHD-OK -->` escape hatch. */
const NATIVE_BINARY_GUARD_BASH_LAUNCHD_OK_ESCAPE_HATCH_REGEX = /[#/]\s*BASH-LAUNCHD-OK/i;

/** macOS launchd-related directory substrings — file_path must include one to be in scope. */
const NATIVE_BINARY_GUARD_LAUNCHD_RELATED_DIRECTORY_SUBSTRINGS: readonly string[] = [
  "/.claude/automation/",
  "/Library/LaunchAgents/",
  "/Library/LaunchDaemons/",
] as const;

/** Shebang regex — first-line `#!/bin/bash`, `#!/usr/bin/bash`, `#!/bin/sh`, `#!/usr/bin/sh` etc. */
const NATIVE_BINARY_GUARD_BASH_OR_SH_SHEBANG_LINE_REGEX = /^#!\s*\/(?:usr\/)?bin\/(?:ba)?sh/m;

/** Plist `<string>/bin/bash</string>` / `<string>/usr/bin/sh</string>` references. */
const NATIVE_BINARY_GUARD_PLIST_BASH_OR_SH_ABSOLUTE_PATH_REFERENCE_REGEX =
  /<string>\/(?:usr\/)?bin\/(?:ba)?sh<\/string>/i;

/** Plist `<string>...something.sh</string>` ProgramArguments shell-script references. */
const NATIVE_BINARY_GUARD_PLIST_SH_SCRIPT_PATH_REFERENCE_REGEX = /<string>[^<]*\.sh<\/string>/i;

// ============================================================================
// Detection helpers (pure functions)
// ============================================================================

/** Returns true if `filePath` contains one of the launchd-related directory substrings. */
function isLaunchdRelatedDirectoryPath(filePath: string): boolean {
  return NATIVE_BINARY_GUARD_LAUNCHD_RELATED_DIRECTORY_SUBSTRINGS.some(
    (substring) => filePath.includes(substring),
  );
}

/** Returns true if `filePath` has a shell-script extension OR content starts with a bash/sh shebang. */
function fileIsShellScriptByExtensionOrShebangContent(filePath: string, content: string): boolean {
  return (
    filePath.endsWith(".sh") ||
    filePath.endsWith(".bash") ||
    NATIVE_BINARY_GUARD_BASH_OR_SH_SHEBANG_LINE_REGEX.test(content)
  );
}

/** Returns true if `content` looks like a plist with bash/sh or .sh-script ProgramArguments references. */
function plistContentReferencesBashShOrShellScriptPath(content: string): boolean {
  return (
    NATIVE_BINARY_GUARD_PLIST_BASH_OR_SH_ABSOLUTE_PATH_REFERENCE_REGEX.test(content) ||
    NATIVE_BINARY_GUARD_PLIST_SH_SCRIPT_PATH_REFERENCE_REGEX.test(content)
  );
}

/** Build the deny message for shell-script-in-launchd-directory violations. */
function buildShellScriptInLaunchdDirectoryViolationMessage(filePath: string): string {
  return [
    `[${NATIVE_BINARY_GUARD_HOOK_NAME}] Shell scripts are not allowed for macOS launchd automation.`,
    "",
    `File: ${filePath}`,
    "",
    "macOS launchd services MUST use compiled native binaries (Swift preferred) so they show with proper names in System Settings > Login Items.",
    'Using /bin/bash shows a generic "bash" entry which looks like unidentified malware.',
    "",
    "FIX: Write the logic in Swift and compile with:",
    "  swiftc -O -framework EventKit -o binary-name Source.swift",
    "",
    "Reference: ~/.claude/automation/calendar-alarm-sweep/swift-cli/ for examples.",
    'Escape hatch: Add `# BASH-LAUNCHD-OK` comment if bash is truly required.',
  ].join("\n");
}

/** Build the deny message for bash-or-sh-or-shellscript references in launchd plists. */
function buildPlistBashOrShOrShellScriptReferenceViolationMessage(filePath: string): string {
  return [
    `[${NATIVE_BINARY_GUARD_HOOK_NAME}] Launchd plist must not reference /bin/bash or .sh scripts.`,
    "",
    `File: ${filePath}`,
    "",
    "ProgramArguments must point to a compiled native binary, not a shell script.",
    'Using /bin/bash in ProgramArguments shows "bash" in Login Items.',
    "",
    "FIX: Compile your script as a Swift binary and reference it directly:",
    "  <string>/path/to/compiled-binary</string>",
    "",
    "Reference: ~/.claude/automation/calendar-alarm-sweep/swift-cli/ for examples.",
    'Escape hatch: Add `<!-- BASH-LAUNCHD-OK -->` comment in plist.',
  ].join("\n");
}

// ============================================================================
// Pure classifier (iter-90 orchestrator-inlineable contract)
// ============================================================================

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Short-circuit order (cheap → expensive):
 *   1. tool_name not Write/Edit → ALLOW
 *   2. file_path NOT in launchd-related directory (O(1) substring scan) → ALLOW
 *      (replaces the standalone path's raw-stdin keyword prefilter; cheaper
 *      because input is already JSON-parsed in orchestrator mode)
 *   3. content escape-hatch present → ALLOW
 *   4. Edit AND existing on-disk file contains escape hatch (iter-15 fix) → ALLOW
 *   5. shell-script-by-extension-or-shebang → DENY
 *   6. plist with bash/sh/shellscript references → DENY
 *   7. all clean → ALLOW
 *
 * MUST NOT call allow()/deny() or touch stdin/stdout/process.exit.
 * MUST NOT emit `hookSpecificOutput.additionalContext` (silently dropped on
 * PreToolUse per GH #15664 — see file-header defense-in-depth comment).
 */
export async function classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input } = input;

  if (tool_name !== "Write" && tool_name !== "Edit") {
    return ALLOW_DECISION;
  }

  const filePath = (tool_input?.file_path as string) || "";

  // O(1) substring fastpath — replaces standalone-mode raw-stdin keyword prefilter
  if (!isLaunchdRelatedDirectoryPath(filePath)) {
    return ALLOW_DECISION;
  }

  const proposedContent =
    (tool_input?.content as string) || (tool_input?.new_string as string) || "";

  // Escape hatch in proposed content
  if (NATIVE_BINARY_GUARD_BASH_LAUNCHD_OK_ESCAPE_HATCH_REGEX.test(proposedContent)) {
    return ALLOW_DECISION;
  }

  // Iter-15 fix preserved: Edit may target a region NOT containing the marker, but
  // the file on disk has it. We're already gated by isLaunchdRelatedDirectoryPath()
  // so the file read is rare; cost is acceptable.
  if (tool_name === "Edit" && filePath) {
    try {
      const existingFileContent = await Bun.file(filePath).text();
      if (NATIVE_BINARY_GUARD_BASH_LAUNCHD_OK_ESCAPE_HATCH_REGEX.test(existingFileContent)) {
        return ALLOW_DECISION;
      }
    } catch {
      // File doesn't exist or unreadable — fall through to normal check
    }
  }

  // Detection 1: shell scripts under launchd directories
  if (fileIsShellScriptByExtensionOrShebangContent(filePath, proposedContent)) {
    return denyDecision(buildShellScriptInLaunchdDirectoryViolationMessage(filePath));
  }

  // Detection 2: plists referencing bash/sh/shellscript
  if (filePath.endsWith(".plist") && plistContentReferencesBashShOrShellScriptPath(proposedContent)) {
    return denyDecision(buildPlistBashOrShOrShellScriptReferenceViolationMessage(filePath));
  }

  return ALLOW_DECISION;
}

/**
 * Backward-compat alias for symmetric naming with sibling iter-84/85/86/87/88/89
 * subhook cohort (`classify<FilenamePrefix>ForOrchestrator`). The precise
 * algorithm-encoding name (`classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator`)
 * is what should be read for understanding the actual policy.
 */
export const classifyNativeBinaryGuardForOrchestrator = classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator;

// ============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// ============================================================================

/**
 * Standalone-CLI entry. Retains the raw-stdin LAUNCHD-RELATED-KEYWORD prefilter
 * (which pays for itself by avoiding JSON.parse on non-launchd payloads in
 * direct-CLI invocation). The orchestrator path does not need this because
 * input is already parsed.
 */
async function main(): Promise<void> {
  // Raw-stdin read for the prefilter (standalone CLI mode only)
  let rawStdinText: string;
  try {
    rawStdinText = await Bun.stdin.text();
  } catch {
    allow();
    return;
  }

  // Raw-stdin prefilter: bail to allow if no launchd-related keyword is present
  const hasAnyLaunchdRelatedKeyword =
    NATIVE_BINARY_GUARD_STANDALONE_RAW_STDIN_LAUNCHD_RELATED_KEYWORD_PREFILTER.some(
      (keyword) => rawStdinText.includes(keyword),
    );
  if (!hasAnyLaunchdRelatedKeyword) {
    allow();
    return;
  }

  // Parse the raw stdin into the structured PreToolUseInput shape and delegate
  // to the shared pure classifier (so standalone + orchestrator paths share
  // detection logic without duplicating policy code).
  let input: PreToolUseInput;
  try {
    input = JSON.parse(rawStdinText) as PreToolUseInput;
  } catch {
    allow(); // Fail-open
    return;
  }

  const decision = await classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator(input);
  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      // Standalone has no `ask` helper analog → fall through to deny so user
      // still sees the blocking message. Orchestrator handles `ask` via belt-and-suspenders.
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// parseStdinOrAllow is intentionally NOT used here — standalone path keeps its
// raw-stdin prefilter optimization. Unused import suppression: re-export so
// the helpers stay in the public surface for any future refactor.
export { parseStdinOrAllow };

// import.meta.main is true only for the entry-point script; when the orchestrator
// imports classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator (or its
// classifyNativeBinaryGuardForOrchestrator alias), this branch does NOT fire.
if (import.meta.main) {
  main().catch((err: unknown) => {
    trackHookError("pretooluse-native-binary-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
