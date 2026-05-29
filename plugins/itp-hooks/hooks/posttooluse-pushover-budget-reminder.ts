#!/usr/bin/env bun
/**
 * PostToolUse hook: Pushover message-budget reminder (soft nudge).
 *
 * Problem
 * -------
 * Pushover push-notification messages have hard size limits, and the
 * lock-screen / banner PREVIEW truncates long bodies even though the full
 * body IS delivered. Operators who pack verbose machine-readable provenance
 * into a message routinely (a) overflow the budget, (b) waste the title /
 * url / url_title channels, and (c) never realize an image attachment is the
 * right tool for "must be readable at a glance" provenance. This hook fires
 * whenever Claude writes/edits code that CONSTRUCTS a Pushover message (in
 * Python, Go, TypeScript/JS, or Bash), or runs an inline Pushover send via
 * Bash, and injects a reminder to use the full budget well.
 *
 * Pushover hard limits (official API, verified 2026-05-29):
 *   message    1024 UTF-8 chars   (delivered in full; PREVIEW truncates)
 *   title       250
 *   url         512               (supplementary, clickable)
 *   url_title   100
 *   attachment  ONE per message, <= 5 MB, image/png|jpeg
 *
 * Channel choice (important — see GitHub #19432, #55889, #15664):
 *   PreToolUse `additionalContext` is silently dropped on current Claude Code
 *   versions (and ALL injection channels are dropped for the Bash matcher),
 *   so this is a PostToolUse hook that emits `{decision:"block", reason}` —
 *   the repo's proven Claude-visible channel (ADR 2025-12-17). `block` here
 *   does NOT undo the already-completed tool; it only surfaces `reason` as a
 *   system reminder. This hook NEVER blocks real work.
 *
 * Detection philosophy (precision over recall, matching code-correctness-guard):
 *   Every rule is anchored on Pushover-specific evidence. Generic shapes such
 *   as a bare `{title, message}` object, a `FormData.append('message')`, or a
 *   Slack lookalike are deliberately NOT matched (they were proven false-
 *   positive magnets by the adversarial spike workflow).
 *
 * Detection arms (union; applied to Bash `command` or Write/Edit content):
 *   1. Library / CLI usage (endpoint-independent):
 *        - gregdel/pushover (Go):   pushover.New(...) ... SendMessage(
 *        - chump / python-pushover: .send_message(title=/message=
 *        - pushover-notifications:  new Pushover
 *        - a pushover client import (pushover-notifications/node-pushover/chump/...)
 *        - pushover-notify CLI:     pushover-notify --title/--message/...
 *   2. Endpoint usage: `api.pushover.net` on a NON-comment line AND a real
 *      send call present (curl -d/-F, requests/httpx .post(, http.Post/PostForm(,
 *      fetch(, axios, urlopen(). Comments/docstrings/heredoc-prose mention the
 *      endpoint but lack a send call, so they are correctly excluded.
 *
 * Escape hatch: add `PUSHOVER-BUDGET-OK` anywhere in the file/command to
 * silence the nudge (e.g. for an intentionally terse alert).
 *
 * Fail-open: any error or non-detection exits 0 silently.
 */

import { trackHookError } from "./lib/hook-error-tracker.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

// ── Types ──────────────────────────────────────────────────────────────────

interface HookInput {
  tool_name: string;
  tool_input?: {
    command?: string;
    file_path?: string;
    content?: string;
    new_string?: string;
    edits?: Array<{ old_string?: string; new_string?: string }>;
  };
  session_id?: string;
}

// ── Detection ────────────────────────────────────────────────────────────────

/**
 * Explicit opt-out marker (checked before any positive rule). Detection routes
 * through the iter-107 canonical shared helper (FILE_WIDE, CASE_SENSITIVE)
 * per the marketplace escape-hatch-marker convention, and the marker is
 * declared in the iter-111 canonical producer-marker registry. The
 * UPPER-KEBAB-CASE token never collides with code identifiers, so a
 * comment-prefix-agnostic substring match is safe.
 */
const PUSHOVER_BUDGET_ESCAPE_HATCH_MARKER_DETECTION_CONFIG = {
  markerNameTokenIncludingSuffix: "PUSHOVER-BUDGET-OK",
  caseSensitivityMode: "CASE_SENSITIVE" as const,
};

/** The canonical Pushover send endpoint. */
const ENDPOINT = /api\.pushover\.net/i;

/**
 * A line is a comment / prose line (so an endpoint mention on it does NOT
 * count as real code). Covers Python/Bash (#), Go/TS (//), block-comment
 * continuations (*, /*), and HTML (<!--).
 */
const COMMENT_LINE = /^\s*(?:#|\/\/|\*|\/\*|<!--)/;

/**
 * Evidence that an actual network send happens in the text. Used together
 * with an endpoint-on-a-code-line to separate real sends from documentation
 * that merely mentions the endpoint.
 */
const SEND_CALL =
  /(?:\bcurl\b[\s\S]{0,300}?(?:--data-urlencode|--data\b|-d\b|--form-string|--form\b|-F\b|-X\b|token=|user=|message=))|requests\.(?:post|get|request)\s*\(|httpx|\.post\s*\(|http\.PostForm\s*\(|http\.Post\s*\(|http\.NewRequest\s*\(|url\.Values\s*\{|fetch\s*\(|axios|urlopen\s*\(/i;

/** Endpoint-independent Pushover library / CLI usage. */
const LIBRARY_OR_CLI_RULES: { name: string; rx: RegExp }[] = [
  // gregdel/pushover (Go): client instantiation followed by a send.
  { name: "go-gregdel-sendmessage", rx: /\bpushover\.New\s*\([\s\S]{0,400}?SendMessage\s*\(/i },
  // chump / python-pushover: user.send_message(title=..., message=...)
  { name: "py-client-send_message", rx: /\.send_message\s*\([\s\S]{0,200}?(?:title|message)\s*=/i },
  // pushover-notifications (Node): new Pushover({...})
  { name: "ts-new-pushover", rx: /\bnew\s+Pushover\b/ },
  // import of a known Pushover client package.
  {
    name: "pushover-client-import",
    rx: /(?:import|require|from)\b[\s\S]{0,80}?['"`](?:pushover-notifications|node-pushover|python-pushover|chump|pushover)['"`]/i,
  },
  // pushover-notify CLI wrapper invoked with flags.
  {
    name: "pushover-notify-cli",
    rx: /\bpushover-notify\b[\s\S]{0,80}?--(?:title|message|priority|url|sound|service|level|device)/i,
  },
];

function hasEndpointOnCodeLine(text: string): boolean {
  for (const line of text.split("\n")) {
    if (ENDPOINT.test(line) && !COMMENT_LINE.test(line)) return true;
  }
  return false;
}

export interface PushoverDetectionResult {
  matched: boolean;
  /** Name of the rule that matched, or "escape-hatch" / null. */
  rule: string | null;
}

/**
 * Detect whether `text` constructs / sends a Pushover message.
 * Pure function — exported for fixture-backed regression tests.
 */
export function detectPushoverMessageConstruction(text: string): PushoverDetectionResult {
  if (!text) return { matched: false, rule: null };

  // Escape hatch wins over every positive rule (iter-107 canonical helper).
  if (hasFileWideEscapeHatchMarkerInContent(text, PUSHOVER_BUDGET_ESCAPE_HATCH_MARKER_DETECTION_CONFIG)) {
    return { matched: false, rule: "escape-hatch" };
  }

  for (const rule of LIBRARY_OR_CLI_RULES) {
    if (rule.rx.test(text)) return { matched: true, rule: rule.name };
  }

  if (hasEndpointOnCodeLine(text) && SEND_CALL.test(text)) {
    return { matched: true, rule: "endpoint+send-call" };
  }

  return { matched: false, rule: null };
}

// ── Reminder text ────────────────────────────────────────────────────────────

function buildReminder(rule: string): string {
  return [
    "[PUSHOVER-BUDGET] Pushover message construction detected — use the full budget for verbose, machine-readable provenance (and don't overflow it).",
    "",
    "Hard limits (UTF-8 chars): message 1024 · title 250 · url 512 · url_title 100 · ONE image attachment ≤ 5 MB (image/png|jpeg).",
    "The full 1024-char body IS delivered, but the lock-screen/banner PREVIEW truncates — so FRONT-LOAD the highest-value identifiers in the first ~120 chars AND in the title.",
    "",
    "Provenance priority within budget:",
    "  1. Stable IDs first — UUID, ticket#/order#, deal#, magic, symbol (put the at-a-glance identity in the TITLE).",
    "  2. Decision time in BOTH UTC and the display/broker tz (the screenshot-vs-UTC mismatch is the classic confusion).",
    "  3. Rule/git provenance — config SHA, gitHEAD, file path.",
    "  4. A machine-readable retrieval pointer — e.g. `grep <uuid> <path> | jq .`",
    "",
    "Spend the side channels instead of body budget:",
    "  • title (250): symbol/direction/ticket — the glance identity.",
    "  • url (512) + url_title (100): offload the long grep/retrieval command or a deep link.",
    "  • OVERFLOW / CEO-readable-at-a-glance: render the provenance as an IMAGE (PNG table/dashboard) and attach it — ONE per message, ≤ 5 MB, via multipart `attachment` or base64 `attachment_base64` + `attachment_type`. Claude Code can generate that image on request — just ask it to render a provenance table to PNG.",
    "",
    `(matched: ${rule} · soft nudge, nothing was blocked · add \`PUSHOVER-BUDGET-OK\` to silence)`,
  ].join("\n");
}

// ── Main (PostToolUse protocol) ──────────────────────────────────────────────

/** Collect the text to scan from the tool input, per tool type. */
function extractText(input: HookInput): string {
  const tool = input.tool_name || "";
  const ti = input.tool_input || {};
  if (tool === "Bash") return ti.command || "";
  if (tool === "Write") return ti.content || "";
  if (tool === "Edit") return ti.new_string || "";
  if (tool === "MultiEdit") {
    return (ti.edits || []).map((e) => e.new_string || "").join("\n");
  }
  return "";
}

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

  const text = extractText(input);
  if (!text) process.exit(0);

  const { matched, rule } = detectPushoverMessageConstruction(text);
  if (matched && rule) {
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
      "posttooluse-pushover-budget-reminder",
      err instanceof Error ? err.message : String(err),
    );
    process.exit(0);
  });
}
