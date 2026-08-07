#!/usr/bin/env bun
/**
 * PreToolUse subhook: Skill CLAUDE_PLUGIN_ROOT Guard
 *
 * Blocks Write/Edit/MultiEdit on skill markdown (any `.md` under a `skills/`
 * directory — SKILL.md bodies and their `references/`) that introduces a
 * CLAUDE_PLUGIN_ROOT reference the runtime cannot honor.
 *
 * WHY (forensics, 2026-08-05 — `/notes-commander:draft-hold` exit 127):
 *
 *   `CLAUDE_PLUGIN_ROOT` is NOT a shell environment variable. Claude Code
 *   does exactly two things with it:
 *
 *     1. Text-substitutes the EXACT literal `${CLAUDE_PLUGIN_ROOT}` inside
 *        plugin MANIFESTS (hooks/hooks.json, .mcp.json, .lsp.json, monitor
 *        commands). The bundled helper is literally
 *          e.replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, pluginPath)
 *        so the braces are part of the match.
 *     2. Injects CLAUDE_PLUGIN_ROOT into the ENVIRONMENT of the hook and
 *        MCP/LSP subprocesses it spawns.
 *
 *   It is never exported into the Bash tool's environment, and a SKILL.md
 *   body is served to the model VERBATIM on the Skill-tool path (verified by
 *   live probe: the served body was byte-identical to the file on disk).
 *   So a skill that writes `"$CLAUDE_PLUGIN_ROOT/skills/x/run.sh"` hands zsh
 *   an unset variable, which expands to empty, producing the absolute-looking
 *   `/skills/x/run.sh` — a "no such file or directory" that reads like a
 *   missing file rather than a missing variable.
 *
 * THREE DENIABLE SHAPES (each is provably broken, hence a block not a nudge):
 *
 *   BARE_SPELLING           `$CLAUDE_PLUGIN_ROOT`
 *     Unsubstitutable everywhere — no braces, so the manifest substitution
 *     regex cannot match it either. Broken in skills AND in manifests.
 *
 *   NON_SUBSTITUTING_DEFAULT `${CLAUDE_PLUGIN_ROOT:-/fallback}`
 *     Also never substituted: the regex needs the closing brace immediately
 *     after the name. The idiom "works" only by always taking the fallback,
 *     silently pinning the skill to the Layer-2 marketplace clone instead of
 *     the version Claude Code actually loaded.
 *
 *   BRACED_IN_SHELL_CONTEXT  `${CLAUDE_PLUGIN_ROOT}` on a non-manifest line
 *     Correct inside a hooks.json/.mcp.json snippet, which is why those lines
 *     are exempted by `looksLikeJsonManifestLine`. On a shell command line in
 *     a SKILL.md it is not substituted on the Skill-tool path and reaches
 *     Bash unset.
 *
 * REMEDIATION the denial message steers to: the `cc-plugin-root` resolver
 * (`scripts/cc-plugin-root`, symlinked into `~/.local/bin/`), which reads
 * `~/.claude/plugins/installed_plugins.json` and prints the LIVE install path:
 *
 *     SCRIPT="$(cc-plugin-root my-plugin)/skills/my-skill/run.sh"
 *
 * Globbing `~/.claude/plugins/cache/<mp>/<plugin>/*` for the highest semver is
 * explicitly NOT the fix — that directory retains every previously-installed
 * version and the highest is routinely marked `.orphaned_at` (exactly how the
 * 2026-08-05 manual recovery landed on a stale version).
 *
 * Escape hatch (FILE_WIDE — one marker exempts the whole file, because the
 * files that legitimately discuss this variable are documentation ABOUT it):
 *     SKILL-PLUGIN-ROOT-OK: <reason at least 10 characters>
 * For Edit/MultiEdit the marker is honored whether it appears in the new text
 * or anywhere in the file already on disk (the iter-15 fix pattern).
 *
 * Contract: pure classifier per
 * `lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts`
 * — no stdin/stdout/process.exit, bounded time, never throws, fail-open.
 */

import type { PreToolUseInput } from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
import {
  hasFileWideEscapeHatchMarkerInContent,
  type EscapeHatchMarkerDetectionConfiguration,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

const SKILL_PLUGIN_ROOT_ESCAPE_HATCH_CONFIGURATION: EscapeHatchMarkerDetectionConfiguration =
  {
    markerNameTokenIncludingSuffix: "SKILL-PLUGIN-ROOT-OK",
    windowSemanticsMode: "FILE_WIDE",
    requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
  };

// O(1) fastpath sentinel — if the proposed content lacks this substring no
// violation is possible.
const FASTPATH_SENTINEL_SUBSTRING = "CLAUDE_PLUGIN_ROOT";

// Bare `$CLAUDE_PLUGIN_ROOT`. `\$CLAUDE` cannot match `${CLAUDE` (the char
// after `$` is `{` there), so this isolates the brace-less spelling.
const BARE_SPELLING_REGEX = /\$CLAUDE_PLUGIN_ROOT/;
// `${CLAUDE_PLUGIN_ROOT:-...}` — the shell default that defeats substitution.
const NON_SUBSTITUTING_DEFAULT_REGEX = /\$\{CLAUDE_PLUGIN_ROOT\s*:[-=?+]/;
// Plain braced form.
const BRACED_REGEX = /\$\{CLAUDE_PLUGIN_ROOT\}/;

// Literal "$" so the operator-facing message can show the braced placeholder
// without tripping biome's lint/suspicious/noTemplateCurlyInString.
const DOLLAR_LITERAL_FOR_DISPLAY = String.fromCharCode(36);

type SkillPluginRootViolationKind =
  "BARE_SPELLING" | "NON_SUBSTITUTING_DEFAULT" | "BRACED_IN_SHELL_CONTEXT";

interface SkillPluginRootViolation {
  kind: SkillPluginRootViolationKind;
  lineNumber: number;
  lineContent: string;
}

/**
 * True when the file is skill markdown — a SKILL.md body or one of its
 * on-demand `references/` docs. Both are served to the model as text, so both
 * are subject to the same "no placeholder substitution" reality.
 */
export function isSkillMarkdownFilePath(filePath: string | undefined): boolean {
  if (!filePath) return false;
  return filePath.includes("/skills/") && filePath.endsWith(".md");
}

/**
 * True when the line is plausibly part of a JSON manifest snippet quoted
 * inside the doc (a hooks.json / .mcp.json / .lsp.json example). On those
 * lines the braced placeholder is CORRECT and must not be flagged.
 *
 * Two shapes cover the realistic cases — a key-value pair such as
 *   "command": "bun <braced-placeholder>/hooks/x.ts",
 * and a bare array element such as
 *   "<braced-placeholder>/server.js"
 */
export function looksLikeJsonManifestLine(lineContent: string): boolean {
  const trimmedLine = lineContent.trim();
  if (/^"[A-Za-z_][\w.-]*"\s*:/.test(trimmedLine)) return true;
  if (/^"[^"]*"\s*,?$/.test(trimmedLine)) return true;
  return false;
}

/**
 * Collect one violation per offending line in the supplied content blob.
 * Pure — no I/O, no escape-hatch lookup (the caller owns that, because the
 * marker may live on disk rather than in the proposed text).
 */
export function detectSkillPluginRootViolationsInContentBlob(
  contentBlob: string,
): SkillPluginRootViolation[] {
  const collectedViolations: SkillPluginRootViolation[] = [];
  const lines = contentBlob.split("\n");

  lines.forEach((currentLineContent, currentLineZeroBasedIndex) => {
    if (!currentLineContent.includes(FASTPATH_SENTINEL_SUBSTRING)) return;

    let detectedKind: SkillPluginRootViolationKind | undefined;
    if (BARE_SPELLING_REGEX.test(currentLineContent)) {
      // Broken in every context, manifest snippets included.
      detectedKind = "BARE_SPELLING";
    } else if (NON_SUBSTITUTING_DEFAULT_REGEX.test(currentLineContent)) {
      detectedKind = "NON_SUBSTITUTING_DEFAULT";
    } else if (
      BRACED_REGEX.test(currentLineContent) &&
      !looksLikeJsonManifestLine(currentLineContent)
    ) {
      detectedKind = "BRACED_IN_SHELL_CONTEXT";
    }

    if (!detectedKind) return;
    collectedViolations.push({
      kind: detectedKind,
      lineNumber: currentLineZeroBasedIndex + 1,
      lineContent: currentLineContent.trim().slice(0, 120),
    });
  });

  return collectedViolations;
}

const PER_KIND_EXPLANATION: Record<SkillPluginRootViolationKind, string> = {
  BARE_SPELLING:
    "bare $CLAUDE_PLUGIN_ROOT — never substituted anywhere (the substitution regex requires braces), so it reaches the shell unset",
  NON_SUBSTITUTING_DEFAULT: `${DOLLAR_LITERAL_FOR_DISPLAY}{CLAUDE_PLUGIN_ROOT:-...} — also never substituted (the regex needs the closing brace right after the name), so this silently always takes the hardcoded fallback`,
  BRACED_IN_SHELL_CONTEXT: `${DOLLAR_LITERAL_FOR_DISPLAY}{CLAUDE_PLUGIN_ROOT} in a shell command — a SKILL.md body is served to the model verbatim, so nothing substitutes it and Bash sees an unset variable`,
};

function buildOperatorFacingDenialReason(
  filePath: string,
  violations: SkillPluginRootViolation[],
): string {
  const headerLines = [
    "[SKILL-PLUGIN-ROOT GUARD] Blocked: this skill doc references CLAUDE_PLUGIN_ROOT",
    "in a form the runtime cannot honor. It is NOT a shell variable — Claude Code",
    `substitutes only the exact literal ${DOLLAR_LITERAL_FOR_DISPLAY}{CLAUDE_PLUGIN_ROOT} inside plugin MANIFESTS`,
    "(hooks.json / .mcp.json / .lsp.json) and sets it in hook + MCP subprocess envs.",
    "It never reaches the Bash tool.",
    "",
    `File: ${filePath}`,
    "",
    `Violations (${violations.length}):`,
  ];

  const violationLines = violations.slice(0, 5).map((singleViolation) => {
    return [
      `  Line ${singleViolation.lineNumber} [${singleViolation.kind}]`,
      `    ${singleViolation.lineContent}`,
      `    ${PER_KIND_EXPLANATION[singleViolation.kind]}`,
    ].join("\n");
  });
  if (violations.length > 5) {
    violationLines.push(`  ...and ${violations.length - 5} more`);
  }

  const remediationLines = [
    "",
    "Fix — resolve the plugin's LIVE install path with the cc-plugin-root helper:",
    '  SCRIPT="$(cc-plugin-root <plugin-name>)/skills/<skill>/run.sh"',
    "",
    "  <plugin-name> is the directory under plugins/, not the skill name. The helper",
    "  reads ~/.claude/plugins/installed_plugins.json, so it returns the version",
    "  Claude Code actually loaded.",
    "",
    "Do NOT glob ~/.claude/plugins/cache/<mp>/<plugin>/* for the highest version —",
    "that directory retains orphaned versions and the highest is often one of them.",
    "",
    "If this line is a hooks.json / .mcp.json snippet, keep the BRACED form and put",
    "it on a JSON key-value or array-element line so it is recognized as a manifest.",
    "",
    "If this file is documentation ABOUT the variable, add anywhere in the file:",
    "  SKILL-PLUGIN-ROOT-OK: <reason at least 10 chars>",
    "",
    "Forensics: plugins/plugin-dev/skills/skill-architecture/references/advanced-topics.md",
  ];

  return [...headerLines, ...violationLines, ...remediationLines].join("\n");
}

function extractProposedContentBlobs(input: PreToolUseInput): string[] {
  const toolInput = (input.tool_input ?? {}) as {
    content?: string;
    new_string?: string;
    edits?: Array<{ new_string?: string }>;
  };
  if (input.tool_name === "Write") {
    return toolInput.content ? [toolInput.content] : [];
  }
  if (input.tool_name === "Edit") {
    return toolInput.new_string ? [toolInput.new_string] : [];
  }
  if (input.tool_name === "MultiEdit") {
    return (toolInput.edits ?? [])
      .map((singleEdit) => singleEdit.new_string ?? "")
      .filter((blob) => blob.length > 0);
  }
  return [];
}

/**
 * Iter-15 fix pattern: an Edit may target a region that does NOT contain the
 * FILE_WIDE marker while the file on disk does. Honor the on-disk marker.
 * Fail-open (treat as "no marker") if the file cannot be read.
 */
async function hasEscapeHatchMarkerOnDisk(filePath: string): Promise<boolean> {
  try {
    const existingFileText = await Bun.file(filePath).text();
    return hasFileWideEscapeHatchMarkerInContent(
      existingFileText,
      SKILL_PLUGIN_ROOT_ESCAPE_HATCH_CONFIGURATION,
    );
  } catch {
    return false;
  }
}

export async function classifySkillPluginRootGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  try {
    if (
      !isFileEditToolNameHonoredByPreToolUseBlockingSubhook(input.tool_name)
    ) {
      return ALLOW_DECISION;
    }

    const filePath = (input.tool_input as { file_path?: string })?.file_path;
    if (!isSkillMarkdownFilePath(filePath) || !filePath) return ALLOW_DECISION;

    const contentBlobs = extractProposedContentBlobs(input);
    if (contentBlobs.length === 0) return ALLOW_DECISION;

    // O(1) sentinel check across all blobs before any per-line work.
    if (
      !contentBlobs.some((blob) => blob.includes(FASTPATH_SENTINEL_SUBSTRING))
    ) {
      return ALLOW_DECISION;
    }

    // FILE_WIDE marker in the proposed text short-circuits before line scan.
    if (
      contentBlobs.some((blob) =>
        hasFileWideEscapeHatchMarkerInContent(
          blob,
          SKILL_PLUGIN_ROOT_ESCAPE_HATCH_CONFIGURATION,
        ),
      )
    ) {
      return ALLOW_DECISION;
    }

    const aggregatedViolations: SkillPluginRootViolation[] = [];
    for (const singleBlob of contentBlobs) {
      aggregatedViolations.push(
        ...detectSkillPluginRootViolationsInContentBlob(singleBlob),
      );
    }
    if (aggregatedViolations.length === 0) return ALLOW_DECISION;

    // Only now pay the disk read — and only for a real candidate violation.
    if (await hasEscapeHatchMarkerOnDisk(filePath)) return ALLOW_DECISION;

    return denyDecision(
      buildOperatorFacingDenialReason(filePath, aggregatedViolations),
    );
  } catch {
    // Fail-open per the subhook contract.
    return ALLOW_DECISION;
  }
}
