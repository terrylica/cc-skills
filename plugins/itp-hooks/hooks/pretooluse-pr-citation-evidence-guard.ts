#!/usr/bin/env bun
/**
 * PreToolUse hook: PR-review citation-evidence guard.
 *
 * OPERATOR DIRECTIVE (2026-09-02, stated twice verbatim)
 *
 *   "Resolutions for PR reviews must contain verbatim citations and quotes from authoritative
 *    online sources, including the URL links as evidence, to demonstrate the state-of-the-artness
 *    of the solutions. This will help our solutions be more readily accepted by the PR reviewers."
 *
 * A directive in a prompt is a REQUEST, not a sandbox — this house has the incident to prove it
 * (~20 unauthorised broker orders placed by agents whose prompts forbade trading). Enforcement has
 * to live at the boundary where the text is actually published.
 *
 * WHAT IT FIRES ON, AND WHY THE SCOPE IS DELIBERATELY NARROW
 *
 * ONLY `gh pr comment` / `gh pr review`, and the `gh api` equivalents writing to a pull request's
 * review or comment endpoints. NOT `gh pr create` (a PR description is authored before review and
 * is not a resolution OF review feedback), NOT issues, NOT releases. A guard that fires on "LGTM",
 * "rebased onto main", or a one-line question is a guard that gets disabled within a week, and
 * then it protects nothing. Narrow and alive beats broad and switched off.
 *
 * Within that scope it fires on exactly two mechanical conditions:
 *
 *   1. NORMATIVE CLAIM, NO SOURCE. The body asserts something is best practice / canonical /
 *      idiomatic / the standard / state of the art, and contains no URL at all. This is the
 *      cheapest possible statement of the directive: if you are telling a reviewer that a solution
 *      is what the field does, name where the field says so.
 *
 *   2. SOURCE, NO VERBATIM QUOTE. The body makes such a claim and cites URLs but quotes nothing
 *      from them. The directive says "verbatim citations and quotes ... including the URL links" —
 *      a bare link asks the reviewer to go and find the supporting sentence, which is the work the
 *      citation was supposed to do.
 *
 * WHAT IT CANNOT CHECK, STATED SO NOBODY MISTAKES GREEN FOR CORRECT
 *
 * It does not fetch anything. It cannot tell whether the quote is real, whether the URL returns
 * 200, or — the failure that actually matters — whether a real quote from a real source supports
 * the claim it is attached to. The pr-evidence-standard skill measured that directly: 64 of 64
 * URLs returned 200 and 64 of 64 quotes were verbatim, and SEVEN citations still failed, because
 * they were genuine sources attached to claims of the wrong SCOPE or the wrong DIRECTION.
 *
 * So this guard checks SHAPE, and its message says so.
 *
 * Escape hatch: `PR-CITATION-OK` anywhere in the command. Deliberately bare (no reason required):
 * the legitimate exceptions — answering a reviewer's factual question about this codebase, or
 * confirming a change was made — are common enough that demanding a justification would train
 * people to write a throwaway one.
 *
 * Fail-open everywhere: any parse/read/logic error → allow.
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
  collectGitHubPublishedBodies,
  type CollectedBody,
} from "./lib/github-published-body-collector.ts";

const HOOK_NAME = "pr-citation-evidence-guard";

const CITATION_OK = {
  markerNameTokenIncludingSuffix: "PR-CITATION-OK",
  windowSemanticsMode: "FILE_WIDE" as const,
  caseSensitivityMode: "CASE_SENSITIVE" as const,
} as const;

/**
 * `gh` at a COMMAND POSITION, not merely somewhere in the string.
 *
 * A `\bgh\s+pr\s+review\b` matches inside quoted prose — `echo 'we should run gh pr review later'`
 * — and the sibling hard-wrap guard has that property today. It is harmless there and here (an
 * `echo` carries no `--body`, so nothing is collected and nothing is denied), but a predicate
 * named `targetsAPrReviewSurface` that answers `true` for an `echo` is a claim wider than its
 * subject, and this house has twenty recorded instances of that costing something. Caught by this
 * guard's own test on the first run.
 *
 * Command position = start of string, or after a separator the shell recognises, optionally
 * preceded by environment assignments or a wrapper (`sudo`, `env`, `command`, `time`).
 */
// Assignments and wrappers INTERLEAVE — `GH_TOKEN=x gh …` and `env GH_HOST=y gh …` are both real,
// and a fixed order matched only the first. Caught by this file's own table on the second run.
const COMMAND_POSITION = String.raw`(?:^|[\n;&|(){}]|&&|\|\|)\s*(?:(?:sudo|env|command|time)\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*`;

const ghCommand = (rest: string) => new RegExp(`${COMMAND_POSITION}gh\\s+${rest}`, "i");

/** The review surfaces this guard covers. `create` and `edit` are absent on purpose. */
const GH_PR_REVIEW_SURFACE = ghCommand(String.raw`pr\s+(?:comment|review)\b`);

/** `gh api` writing to a PR's comments or reviews endpoint — the same surface, different door. */
const GH_API_PR_REVIEW_SURFACE = ghCommand(String.raw`api\b[^\n;|&]*\/pulls\/\d+\/(?:comments|reviews)\b`);
/** GitHub models PR conversation comments as ISSUE comments; `gh api` writes them that way. */
const GH_API_ISSUE_COMMENT_ON_PR = ghCommand(String.raw`api\b[^\n;|&]*\/issues\/\d+\/comments\b`);

export function targetsAPrReviewSurface(command: string): boolean {
  return (
    GH_PR_REVIEW_SURFACE.test(command) ||
    GH_API_PR_REVIEW_SURFACE.test(command) ||
    GH_API_ISSUE_COMMENT_ON_PR.test(command)
  );
}

/**
 * Phrases that assert a solution is what the field does.
 *
 * Kept to claims ABOUT AN EXTERNAL AUTHORITY. "This is faster" is a claim about the measurement in
 * front of you and needs a benchmark, not a citation; "this is the idiomatic way" is a claim about
 * the wider world and needs a source. Only the second kind is listed.
 */
const NORMATIVE_CLAIM_PATTERNS: readonly { readonly pattern: RegExp; readonly label: string }[] = [
  { pattern: /\bbest[- ]practice/i, label: "best practice" },
  {
    pattern: /\bstate[- ]of[- ]the[- ]art\b|\bstate-of-the-artness\b|\bSOTA\b/i,
    label: "state of the art",
  },
  { pattern: /\bidiomatic\b/i, label: "idiomatic" },
  { pattern: /\bcanonical (?:way|approach|form|pattern|solution)\b/i, label: "canonical approach" },
  { pattern: /\b(?:the|an) industry standard\b/i, label: "industry standard" },
  { pattern: /\brecommended (?:by|approach|way|practice)\b/i, label: "recommended by" },
  {
    pattern: /\bthe (?:official|documented) (?:recommendation|guidance|approach)\b/i,
    label: "official recommendation",
  },
  { pattern: /\bper the spec(?:ification)?\b/i, label: "per the spec" },
  { pattern: /\baccording to the (?:docs|documentation|standard|spec)/i, label: "according to the docs" },
  { pattern: /\bwidely (?:used|adopted|accepted)\b/i, label: "widely adopted" },
  { pattern: /\bconventional wisdom\b/i, label: "conventional wisdom" },
  { pattern: /\bthe standard (?:way|approach|practice|pattern)\b/i, label: "the standard way" },
];

const URL_PATTERN = /https?:\/\/[^\s<>()[\]"']+/g;

/**
 * The length floor for what counts as a quote.
 *
 * It matters. Almost every technical comment contains `` `someFunction` ``, and counting that as a
 * quote would make condition 2 unreachable — a guard that can never fire is indistinguishable from
 * one that was never written.
 */
const MIN_QUOTE_CHARS = 25;

const longEnough = (s: string): boolean => s.trim().length >= MIN_QUOTE_CHARS;

/**
 * A verbatim quote: a markdown blockquote line, a fenced block, or a quoted / inline-code span
 * long enough to be a sentence fragment rather than a symbol name.
 */
export function hasVerbatimQuote(text: string): boolean {
  const blockquoted = text
    .split("\n")
    .map((line) => /^\s*>\s?(.*)$/.exec(line)?.[1] ?? "")
    .some(longEnough);
  if (blockquoted) return true;

  const fenced = (text.match(/```[\s\S]*?```/g) ?? []).some((b) => longEnough(b.replace(/```/g, "")));
  if (fenced) return true;

  const spans = [
    ...(text.match(/`([^`\n]+)`/g) ?? []),
    ...(text.match(/"([^"\n]+)"/g) ?? []),
    ...(text.match(/“([^”\n]+)”/g) ?? []),
  ];
  return spans.some((s) => longEnough(s.replace(/[`"“”]/g, "")));
}

export interface CitationFinding {
  readonly label: string;
  readonly kind: "normative-claim-without-source" | "source-without-verbatim-quote";
  readonly detail: string;
}

export function findCitationGaps(body: CollectedBody): CitationFinding | null {
  const text = body.text;
  const urls = text.match(URL_PATTERN) ?? [];
  const claims = NORMATIVE_CLAIM_PATTERNS.filter((c) => c.pattern.test(text)).map((c) => c.label);

  if (claims.length === 0) return null;
  const asserted = claims.map((c) => `"${c}"`).join(", ");

  if (urls.length === 0) {
    return {
      label: body.label,
      kind: "normative-claim-without-source",
      detail: `asserts ${asserted} and cites no URL`,
    };
  }

  if (!hasVerbatimQuote(text)) {
    return {
      label: body.label,
      kind: "source-without-verbatim-quote",
      detail: `asserts ${asserted} and cites ${urls.length} URL(s), but quotes nothing from them`,
    };
  }

  return null;
}

function buildReminder(findings: readonly CitationFinding[]): string {
  const lines: string[] = [
    "[PR-CITATION-GUARD] This PR-review text makes a claim about what the field does, without the",
    "evidence the operator directive requires.",
    "",
    "  Resolutions for PR reviews must contain verbatim citations and quotes from authoritative",
    "  online sources, including the URL links as evidence, to demonstrate the state-of-the-artness",
    "  of the solutions.",
    "",
    "Found:",
    ...findings.slice(0, 3).map((f) => `  ${f.label} — ${f.detail}`),
  ];
  if (findings.length > 3) lines.push(`  …and ${findings.length - 3} more.`);

  const kinds = new Set(findings.map((f) => f.kind));
  lines.push("");
  if (kinds.has("normative-claim-without-source")) {
    lines.push(
      "Fix (no source): if you are telling a reviewer that a solution is what the field does, name",
      "where the field says so — a specification section, the project's own documentation, an RFC, a",
      "PEP, or a maintainer's decision, with the URL.",
    );
  }
  if (kinds.has("source-without-verbatim-quote")) {
    lines.push(
      "Fix (no quote): a bare link asks the reviewer to go and find the supporting sentence, which is",
      "the work the citation was supposed to do. Quote it — a `>` blockquote of the exact sentence,",
      "copy-pasted from the RENDERED page.",
    );
  }

  lines.push(
    "",
    "Prefer an immutable ref (a commit permalink, a dated spec edition, an RFC or PEP number, a DOI).",
    "If the source is a living document, say so, and quote enough that the claim survives the page",
    "changing.",
    "",
    "Verify the quotes are real before publishing:",
    "  bun ~/.claude/skills/pr-evidence-standard/verify-citations.ts --emit-template > citations.json",
    "  bun ~/.claude/skills/pr-evidence-standard/verify-citations.ts citations.json",
    "",
    "🔴 A green verifier means the quote is REAL, never that the citation is CORRECT. Measured on",
    "that skill's own run: 64/64 URLs returned 200 and 64/64 quotes were verbatim, and SEVEN",
    "citations still failed — real sources attached to claims of the wrong scope or direction. This",
    "guard checks SHAPE only; it fetches nothing.",
    "",
    "Override (a factual answer about this codebase, or confirming a change landed):",
    "add PR-CITATION-OK anywhere in the command.",
  );

  return lines.join("\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";
  if (!command.trim()) {
    allow();
    return;
  }

  if (hasFileWideEscapeHatchMarkerInContent(command, CITATION_OK)) {
    allow();
    return;
  }

  // Narrower than the collector's notion of "publishes to GitHub": review surfaces only.
  if (!targetsAPrReviewSurface(command)) {
    allow();
    return;
  }

  const collected = await collectGitHubPublishedBodies(command, input.cwd);
  const findings = collected.bodies
    .map(findCitationGaps)
    .filter((f): f is CitationFinding => f !== null);

  // A body this guard could not read is NOT denied. Unlike hard wrapping — where an unreadable
  // body means an unmeasurable defect being hidden from the check — a missing citation is a
  // judgement about content, and denying on absence of evidence would block every
  // write-then-publish call regardless of whether it cites anything. The hard-wrap guard already
  // denies that shape, so such a command does not slip past unexamined.
  if (findings.length > 0) {
    deny(buildReminder(findings));
    return;
  }

  allow();
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    allow();
  });
}
