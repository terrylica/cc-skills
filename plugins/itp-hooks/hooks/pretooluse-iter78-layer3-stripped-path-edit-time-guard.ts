#!/usr/bin/env bun
/**
 * PreToolUse hook: Iter-78 Layer-3 Stripped-Path Edit-Time Guard
 *
 * Edit-time companion to the iter-77 release-time Check 4k audit gate.
 * Blocks Write|Edit|MultiEdit operations that introduce a reference to
 * ${CLAUDE_PLUGIN_ROOT}/<segment>/ where <segment> is NOT in the cache
 * populator allowlist {hooks, skills, commands, agents, plugin.json}.
 *
 * The cache populator (Layer 2 marketplace mirror to Layer 3 versioned
 * operator cache) strips every plugin-root-level subtree that is not
 * one of those five. A reference written today silently fails at runtime
 * the moment the next release tag promotes the working tree to L3.
 *
 * Forensic source: docs/HOOKS.md "Iter-76 Cache-Populator-Filter Forensic
 * Finding". Live confirmation tool: the iter-76 drift detector mise task.
 *
 * Belt-and-suspenders defense per GitHub issue #37210 (PreToolUse "deny"
 * decision documented as ignored for the Edit tool on some Claude Code
 * versions, while still honored for Write):
 *   1. stdout JSON with permissionDecision "deny"
 *   2. stderr diagnostic so the message is transcript-visible regardless
 *   3. process exit 2 (hard-block signal honored even when stdout JSON
 *      is dropped by the buggy code path)
 *
 * Performance: pre-JSON-parse fastpath. If raw stdin does not contain
 * the substring "CLAUDE_PLUGIN_ROOT", short-circuit allow immediately.
 *
 * Scope: matcher "Write|Edit|MultiEdit" (exact casing, per the Claude
 * Code hook matcher semantics).
 *
 * Escape hatch: same marker as the iter-77 release-time gate:
 *   LAYER3-STRIPPED-PATH-OK: <reason at least 10 characters>
 * On the same line OR within the three preceding lines.
 *
 * ADR: docs/HOOKS.md "Iter-78 Edit-Time Companion to Release-Time Check 4k"
 */

import { trackHookError } from "./lib/hook-error-tracker.ts";

const HOOK_NAME = "iter78-layer3-stripped-path-edit-time-guard";

// Pre-JSON-parse fastpath sentinel. If the raw stdin lacks this
// substring, no plugin-root reference is possible.
const FASTPATH_SENTINEL_SUBSTRING = "CLAUDE_PLUGIN_ROOT";

// Cache-populator allowlist — exactly the subtrees preserved by the
// Layer 2 to Layer 3 promoter. Anything outside this set silently
// disappears at L3 runtime.
const LAYER_3_PRESERVED_PLUGIN_ROOT_SEGMENTS: ReadonlySet<string> = new Set([
  "hooks",
  "skills",
  "commands",
  "agents",
  "plugin.json",
]);

// Plugin-root reference regex. Captures the first path component
// after CLAUDE_PLUGIN_ROOT. Accepts both ${CLAUDE_PLUGIN_ROOT} and
// $CLAUDE_PLUGIN_ROOT spellings. Global flag so each line iteration
// finds every occurrence.
const PLUGIN_ROOT_REFERENCE_FIRST_SEGMENT_REGEX =
  /\$\{?CLAUDE_PLUGIN_ROOT\}?\/([A-Za-z0-9_.-]+)/g;

// Escape-hatch marker regex. Reason must be at least 10 non-whitespace
// characters after "LAYER3-STRIPPED-PATH-OK:".
const ESCAPE_HATCH_MARKER_MIN_TEN_CHAR_REASON_REGEX =
  /LAYER3-STRIPPED-PATH-OK:\s*[^\s].{9,}/;

// Maximum preceding-line context window for escape-hatch lookup
// (matches the iter-77 release-time audit exactly).
const ESCAPE_HATCH_PRECEDING_LINE_LOOKBACK_WINDOW_LINE_COUNT = 3;

// Literal "$" character extracted to a named constant so the operator-
// facing denial message can render the documentation example
//   ${CLAUDE_PLUGIN_ROOT}
// without biome flagging an unintended template-literal-in-string-
// literal (lint/suspicious/noTemplateCurlyInString) or oxlint flagging
// a string concatenation (no-useless-concat).
const DOLLAR_LITERAL_FOR_DISPLAY = String.fromCharCode(36);

interface StrippedSegmentViolation {
  segment: string;
  lineNumber: number;
  lineContent: string;
}

interface PreToolUseInputShape {
  tool_name: string;
  tool_input: {
    file_path?: string;
    content?: string;
    new_string?: string;
    edits?: Array<{ new_string?: string }>;
  };
}

function emitAllow(): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
      },
    }),
  );
}

function emitDenyBeltAndSuspenders(reason: string): never {
  // Layer 1: stdout JSON with permissionDecision "deny" (the spec-
  // compliant signal honored by all non-buggy Claude Code versions).
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    }),
  );
  // Layer 2: stderr diagnostic. Always transcript-visible via Ctrl-R
  // regardless of whether stdout JSON was honored.
  process.stderr.write(`\n[${HOOK_NAME}] BLOCKED\n${reason}\n`);
  // Layer 3: exit 2 — the documented hard-block signal honored even
  // when stdout JSON is silently dropped (GitHub issue #37210
  // belt-and-suspenders pattern).
  process.exit(2);
}

/**
 * Detect Layer-3-stripped plugin-root references in the supplied
 * content blob and return one violation per offending reference
 * (excluding those covered by an in-window escape-hatch marker).
 */
function detectLayer3StrippedPathReferencesInContentBlob(
  contentBlob: string,
): StrippedSegmentViolation[] {
  const collectedViolations: StrippedSegmentViolation[] = [];
  const lines = contentBlob.split("\n");

  lines.forEach((currentLineContent, currentLineZeroBasedIndex) => {
    // matchAll returns a fresh stateless iterator each call — no
    // lastIndex stewardship needed, and no in-condition assignment
    // (biome lint/suspicious/noAssignInExpressions).
    const perLineMatchIterator = currentLineContent.matchAll(
      PLUGIN_ROOT_REFERENCE_FIRST_SEGMENT_REGEX,
    );
    for (const singleRegexMatch of perLineMatchIterator) {
      const extractedFirstPathSegment = singleRegexMatch[1];
      if (LAYER_3_PRESERVED_PLUGIN_ROOT_SEGMENTS.has(extractedFirstPathSegment)) {
        continue;
      }
      // Build the escape-hatch lookup window: current line plus
      // ESCAPE_HATCH_PRECEDING_LINE_LOOKBACK_WINDOW_LINE_COUNT lines
      // before it.
      const windowStartZeroBasedIndex = Math.max(
        0,
        currentLineZeroBasedIndex -
          ESCAPE_HATCH_PRECEDING_LINE_LOOKBACK_WINDOW_LINE_COUNT,
      );
      const escapeHatchLookupWindowText = lines
        .slice(windowStartZeroBasedIndex, currentLineZeroBasedIndex + 1)
        .join("\n");
      if (
        ESCAPE_HATCH_MARKER_MIN_TEN_CHAR_REASON_REGEX.test(
          escapeHatchLookupWindowText,
        )
      ) {
        continue;
      }
      collectedViolations.push({
        segment: extractedFirstPathSegment,
        lineNumber: currentLineZeroBasedIndex + 1,
        lineContent: currentLineContent,
      });
    }
  });

  return collectedViolations;
}

function buildOperatorFacingDenialReason(
  filePath: string,
  violations: StrippedSegmentViolation[],
): string {
  const headerLines = [
    "[ITER-78 L3-STRIPPED-PATH GUARD] Blocked: edit introduces references",
    "to plugin-root subtrees stripped by the cache populator (Layer 2 to",
    "Layer 3). These references silently fail at L3 runtime.",
    "",
    `File: ${filePath}`,
    "",
    `Violations (${violations.length}):`,
  ];
  const violationLines = violations.slice(0, 5).map((singleViolation) => {
    return `  Line ${singleViolation.lineNumber}: \${CLAUDE_PLUGIN_ROOT}/${singleViolation.segment}/...`;
  });
  if (violations.length > 5) {
    violationLines.push(`  ...and ${violations.length - 5} more`);
  }
  const remediationLines = [
    "",
    "Cache populator preserves ONLY:",
    `  ${DOLLAR_LITERAL_FOR_DISPLAY}{CLAUDE_PLUGIN_ROOT}/{hooks, skills, commands, agents, plugin.json}`,
    "",
    "Remediation options:",
    "  (a) Move the referenced asset under hooks/ (which IS cached at L3)",
    "      and update the reference path.",
    "  (b) Add LAYER3-STRIPPED-PATH-OK: <reason at least 10 chars> on the",
    "      same line OR within the 3 preceding lines if the reference is",
    "      intentional (for example, dev-only L2 mirror probe).",
    "",
    "Forensic source: docs/HOOKS.md Iter-76 Cache-Populator-Filter section.",
    "Release-time twin: preflight Check 4k (iter-77).",
  ];
  return [...headerLines, ...violationLines, ...remediationLines].join("\n");
}

function extractTargetContentBlobsFromToolInput(
  toolName: string,
  toolInput: PreToolUseInputShape["tool_input"],
): string[] {
  if (toolName === "Write") {
    return toolInput.content ? [toolInput.content] : [];
  }
  if (toolName === "Edit") {
    return toolInput.new_string ? [toolInput.new_string] : [];
  }
  if (toolName === "MultiEdit") {
    const editList = toolInput.edits ?? [];
    return editList
      .map((singleEdit) => singleEdit.new_string ?? "")
      .filter((blob) => blob.length > 0);
  }
  return [];
}

async function main(): Promise<void> {
  // Read raw stdin.
  let rawStdinText: string;
  try {
    rawStdinText = await Bun.stdin.text();
  } catch {
    emitAllow();
    return;
  }

  // Pre-JSON-parse fastpath. If the raw stdin lacks the
  // FASTPATH_SENTINEL_SUBSTRING, no plugin-root reference is possible.
  if (!rawStdinText.includes(FASTPATH_SENTINEL_SUBSTRING)) {
    emitAllow();
    return;
  }

  // Slow path: parse JSON.
  let parsedInput: PreToolUseInputShape;
  try {
    parsedInput = JSON.parse(rawStdinText) as PreToolUseInputShape;
  } catch (parseError) {
    trackHookError(
      HOOK_NAME,
      `Failed to parse stdin JSON: ${
        parseError instanceof Error ? parseError.message : String(parseError)
      }`,
    );
    emitAllow();
    return;
  }

  const toolName = parsedInput.tool_name;
  if (toolName !== "Write" && toolName !== "Edit" && toolName !== "MultiEdit") {
    emitAllow();
    return;
  }

  const filePath = parsedInput.tool_input.file_path ?? "<unknown-path>";

  const contentBlobsToScan = extractTargetContentBlobsFromToolInput(
    toolName,
    parsedInput.tool_input,
  );
  if (contentBlobsToScan.length === 0) {
    emitAllow();
    return;
  }

  const aggregatedViolations: StrippedSegmentViolation[] = [];
  contentBlobsToScan.forEach((singleContentBlob) => {
    const perBlobViolations =
      detectLayer3StrippedPathReferencesInContentBlob(singleContentBlob);
    aggregatedViolations.push(...perBlobViolations);
  });

  if (aggregatedViolations.length === 0) {
    emitAllow();
    return;
  }

  const denialReason = buildOperatorFacingDenialReason(
    filePath,
    aggregatedViolations,
  );
  emitDenyBeltAndSuspenders(denialReason);
}

main().catch((unhandledError) => {
  trackHookError(
    HOOK_NAME,
    `Unhandled error: ${
      unhandledError instanceof Error
        ? unhandledError.message
        : String(unhandledError)
    }`,
  );
  emitAllow();
});
