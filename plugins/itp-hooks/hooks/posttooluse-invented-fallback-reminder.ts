#!/usr/bin/env bun
/**
 * PostToolUse hook: invented-fallback display-value reminder (soft nudge).
 *
 * Policy (operator directive 2026-06-11, statusline official-values arc)
 * ----------------------------------------------------------------------
 * Everything displayed/used must be derived dynamically from its OFFICIAL
 * source — official field names, official enum values, official error text.
 * A hard-coded INVENTED fallback that substitutes for an official value
 * ("Unknown", "N/A", "?") hides real state behind a made-up token. The
 * preferred alternatives, in order:
 *   1. OMIT the token entirely when the data is absent (absent != error).
 *   2. Render the official error/value VERBATIM (first stderr line, exit
 *      code, the actual boolean) — e.g. the statusline now shows git's own
 *      "not a git repository ..." instead of an invented "no git".
 *   3. If a constant must be duplicated, cite its SSoT inline with a date.
 * Precedent: plugins/statusline-tools retired "Unknown", "N/A", "no-branch",
 * "no remote", "no git", "(?)", "∅ rel", "⌁ offline", "✦ ultracode",
 * thinking:on/off — see docs/LESSONS.md (2026-06-11) for the full arc.
 *
 * Channel choice: PostToolUse `{decision:"block", reason}` — the repo's
 * proven Claude-visible channel (ADR 2025-12-17). `block` does NOT undo the
 * completed tool; it only surfaces `reason` as a system reminder. This hook
 * NEVER blocks real work.
 *
 * Detection philosophy (precision over recall, matching code-correctness):
 * only fires on NET-NEW introductions (Edit: occurrences in new_string must
 * exceed old_string) of the canonical invented-fallback shapes, on
 * NON-comment lines of code files, excluding tests/fixtures:
 *   - shell parameter-expansion defaults: ${var:-Unknown} ${var:-N/A} ${var:-?}
 *   - TS/JS nullish/or fallbacks:         ?? "Unknown"   || "N/A"
 *   - Python or/get fallbacks:            or "Unknown"   .get(x, "N/A")
 *   - jq alternative-operator fallbacks:  // "Unknown"   // "N/A"
 * Boolean→"on"/"off" display translations are intentionally NOT pattern-
 * matched (proven false-positive magnet shape); the reminder text covers
 * them as guidance instead.
 *
 * Escape hatch: add `INVENTED-FALLBACK-OK` anywhere in the file/content to
 * silence the nudge (e.g. a deliberate diagnostic marker with an in-file
 * legend, like the doorward render grammar).
 *
 * Fail-open: any error or non-detection exits 0 silently.
 */

import { trackHookError } from "./lib/hook-error-tracker.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

// ── Types ────────────────────────────────────────────────────────────────────

interface HookInput {
  tool_name: string;
  tool_input?: {
    command?: string;
    file_path?: string;
    content?: string;
    old_string?: string;
    new_string?: string;
    edits?: Array<{ old_string?: string; new_string?: string }>;
  };
  session_id?: string;
}

// ── Detection ────────────────────────────────────────────────────────────────

const INVENTED_FALLBACK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG = {
  markerNameTokenIncludingSuffix: "INVENTED-FALLBACK-OK",
  caseSensitivityMode: "CASE_SENSITIVE" as const,
};

/** Code files whose render/display paths the policy covers. */
const CODE_FILE_RX = /\.(sh|bash|zsh|ts|tsx|js|mjs|cjs|py)$/;

/** Test/fixture paths are exempt (they pin behavior, including bad shapes). */
const TEST_PATH_RX = /(\.test\.|\.spec\.|_test\.|\btest_|\/tests?\/|\/fixtures?\/|\.bats$)/;

/** Comment / prose lines never count (Python/Bash #, TS //, block continuations). */
const COMMENT_LINE = /^\s*(?:#|\/\/|\*|\/\*|<!--)/;

/**
 * The canonical invented-fallback value shapes. Each regex anchors on BOTH a
 * fallback OPERATOR and one of the canonical invented VALUES — a bare string
 * "Unknown" in a message or a legitimate default like `?? ""` never matches.
 */
const INVENTED_VALUES = "(?:Unknown|UNKNOWN|unknown|N\\/A|n\\/a)";
const FALLBACK_RULES: { name: string; rx: RegExp }[] = [
  {
    name: "shell-parameter-expansion-default",
    rx: new RegExp(`\\$\\{[A-Za-z_][A-Za-z0-9_]*:-(?:${INVENTED_VALUES}|\\?)\\}`),
  },
  {
    name: "nullish-or-logical-or-fallback",
    rx: new RegExp(`(?:\\?\\?|\\|\\|)\\s*["']${INVENTED_VALUES}["']`),
  },
  {
    name: "python-or-fallback",
    rx: new RegExp(`\\bor\\s+["']${INVENTED_VALUES}["']`),
  },
  {
    name: "python-dict-get-fallback",
    rx: new RegExp(`\\.get\\([^)]+,\\s*["']${INVENTED_VALUES}["']\\s*\\)`),
  },
  {
    name: "jq-alternative-operator-fallback",
    rx: new RegExp(`\\/\\/\\s*["']${INVENTED_VALUES}["']`),
  },
];

/** Count rule hits on non-comment lines. */
function countHits(text: string): number {
  let hits = 0;
  for (const line of text.split("\n")) {
    if (COMMENT_LINE.test(line)) continue;
    for (const rule of FALLBACK_RULES) {
      if (rule.rx.test(line)) hits++;
    }
  }
  return hits;
}

/** First rule name matched on a non-comment line (for the reminder header). */
function firstRuleName(text: string): string {
  for (const line of text.split("\n")) {
    if (COMMENT_LINE.test(line)) continue;
    for (const rule of FALLBACK_RULES) {
      if (rule.rx.test(line)) return rule.name;
    }
  }
  return "invented-fallback";
}

/**
 * Net-new detection: Write fires on any hit in content; Edit/MultiEdit fire
 * only when new_string introduces MORE hits than old_string removes (so
 * touching a line that already carried a legacy fallback does not nag).
 */
export function detectNetNewInventedFallback(input: HookInput): { matched: boolean; rule: string } {
  const ti = input.tool_input || {};

  // Bash arm (2026-06-11 operator extension): inline commands — heredoc
  // scripts, one-off renderers — are code too. Every hit is net-new by
  // definition (there is no old_string for a command). The escape hatch
  // works inside the command text.
  if (input.tool_name === "Bash") {
    const command = ti.command || "";
    if (
      hasFileWideEscapeHatchMarkerInContent(command, INVENTED_FALLBACK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG)
    ) {
      return { matched: false, rule: "" };
    }
    return countHits(command) > 0
      ? { matched: true, rule: firstRuleName(command) }
      : { matched: false, rule: "" };
  }

  const filePath = ti.file_path || "";
  if (!CODE_FILE_RX.test(filePath) || TEST_PATH_RX.test(filePath)) {
    return { matched: false, rule: "" };
  }

  if (input.tool_name === "Write") {
    const content = ti.content || "";
    if (
      hasFileWideEscapeHatchMarkerInContent(content, INVENTED_FALLBACK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG)
    ) {
      return { matched: false, rule: "" };
    }
    return countHits(content) > 0
      ? { matched: true, rule: firstRuleName(content) }
      : { matched: false, rule: "" };
  }

  const pairs: Array<{ oldS: string; newS: string }> =
    input.tool_name === "MultiEdit"
      ? (ti.edits || []).map((e) => ({ oldS: e.old_string || "", newS: e.new_string || "" }))
      : [{ oldS: ti.old_string || "", newS: ti.new_string || "" }];

  for (const { oldS, newS } of pairs) {
    if (
      hasFileWideEscapeHatchMarkerInContent(newS, INVENTED_FALLBACK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG)
    ) {
      continue;
    }
    if (countHits(newS) > countHits(oldS)) {
      return { matched: true, rule: firstRuleName(newS) };
    }
  }
  return { matched: false, rule: "" };
}

// ── Reminder ─────────────────────────────────────────────────────────────────

export function buildReminder(rule: string): string {
  return [
    `[INVENTED-FALLBACK] New hard-coded fallback display value detected (${rule}).`,
    "Policy (operator directive 2026-06-11): derive everything from OFFICIAL names/values — never invent display tokens.",
    "Prefer, in order:",
    '  1. OMIT the token when the data is absent (absent is a state, not an error — render nothing).',
    "  2. Render the OFFICIAL value/error VERBATIM: the actual boolean (true/false, never on/off), the first line of the tool's own stderr, or the official exit code.",
    "  3. If a constant must be duplicated, cite its SSoT inline with a date.",
    "Precedent: statusline-tools retired Unknown/N-A/no-branch/no-git/(?)/on-off — see docs/LESSONS.md 2026-06-11.",
    "Deliberate diagnostic marker with an in-file legend? Add INVENTED-FALLBACK-OK to the file.",
  ].join("\n");
}

// ── Entrypoint ───────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText) as HookInput;
  } catch {
    process.exit(0); // invalid JSON → fail-open
  }

  if (!["Bash", "Write", "Edit", "MultiEdit"].includes(input.tool_name)) process.exit(0);

  const { matched, rule } = detectNetNewInventedFallback(input);
  if (matched) {
    // ADR /docs/adr/2025-12-17-posttooluse-hook-visibility.md — only the
    // `reason` field of a {decision:"block"} payload is visible to Claude.
    console.log(JSON.stringify({ decision: "block", reason: buildReminder(rule) }));
  }
  process.exit(0);
}

// Run only as a hook entrypoint; stay importable by tests.
if (import.meta.main) {
  main().catch((err) => {
    trackHookError(
      "posttooluse-invented-fallback-reminder",
      err instanceof Error ? err.message : String(err),
    );
    process.exit(0);
  });
}
