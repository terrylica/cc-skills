#!/usr/bin/env bun
/**
 * PreToolUse hook: GitHub hard-wrap guard.
 *
 * Blocks GitHub-bound prose text (`gh` commands that publish to GFM-rendering
 * surfaces) when hard-wrapped at a fixed column width. GFM renders every `\n`
 * as an HTML `<br>`, so prose wrapped at ~100 columns becomes columns of short
 * mid-sentence lines instead of paragraphs that reflow to the reader's window.
 *
 * Interception points (see survey in the directive):
 *   - `gh release create|edit` → measure inline --notes / --notes-file text
 *   - `gh issue create` → measure inline --body / -b text
 *   - `gh issue edit` → measure inline --body text
 *   - `gh issue comment` → measure inline --body / -b text
 *   - `gh pr create` → measure inline --body / -b text
 *   - `gh pr edit` → measure inline --body text
 *   - `gh pr comment` → measure inline --body / -b text
 *   - `gh api` writing to a releases/issues/pulls endpoint → measure the
 *     `body=`/`notes=` field, or the `.body` of an `--input` JSON envelope
 *
 * GFM hard-break surfaces:
 *   ✓ release notes, issue body, PR body, issue comments, PR comments
 *   ✗ gist descriptions, repo descriptions (both plain-text, not GFM)
 *   ✗ git objects — commit messages and annotated tag messages
 *
 * Do not extend this guard to `git commit` or `git tag`. A git object is not a
 * GFM surface, and hard wrapping at 72 columns is the correct git convention.
 * The reflow belongs at the PUBLISH boundary, which is exactly what this guard
 * covers: a release built from hard-wrapped commit bodies must be reflowed on
 * its way into `--notes`/`--notes-file`, not by rewriting the commits.
 *
 * Output: PreToolUse `deny` with a reminder listing the offending lines and the
 * single fix. Escape hatch: `GH-HARD-WRAP-OK` anywhere in the command.
 *
 * Fail-open everywhere: any parse/read/logic error → allow (never blocks real
 * work). A missing/unreadable notes-file or body-file is skipped, not blocked.
 *
 * Doctrine SSoT: ~/~/.claude/release-notes-doctrine-CLAUDE.md (release-notes section)
 * Operator directive: hard-wrapped prose must never be published to GitHub
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { detectHardWraps, type WrapIssue } from "./lib/hard-wrap-detector.ts";
import {
  collectGitHubPublishedBodies,
  type UnreadableWrittenFile,
} from "./lib/github-published-body-collector.ts";

const HOOK_NAME = "github-hard-wrap-guard";

/**
 * File-wide escape hatch: GH-HARD-WRAP-OK anywhere in the command.
 * No reason required (bare marker OK) — the guard's purpose is simple enough.
 */
const HARD_WRAP_OK = {
  markerNameTokenIncludingSuffix: "GH-HARD-WRAP-OK",
  windowSemanticsMode: "FILE_WIDE" as const,
  caseSensitivityMode: "CASE_SENSITIVE" as const,
} as const;

/**
 * ════════════════════════════════════════════════════════════════════════
 *  Where the command parsing went
 * ════════════════════════════════════════════════════════════════════════
 *
 * Every `gh` verb pattern, flag extractor, heredoc resolver and `gh api` field parser that used
 * to live here now lives in `lib/github-published-body-collector.ts`, unchanged. It was moved out
 * on 2026-09-02 when the PR-citation guard needed the same answer to the same question — "what
 * text will this command put on GitHub?" — and re-implementing it would have re-inherited all
 * eight bypasses this guard closed one at a time.
 *
 * What stays here is what is specific to THIS guard: the hard-wrap predicate and its two
 * reminders. The collector deliberately does not judge the text.
 *
 * The refactor is behaviour-preserving by construction and was verified against this file's own
 * 54 tests, which passed before and after with no edits.
 */

interface TextSource {
  label: string;
  text: string;
  issues: WrapIssue[];
}

/** Build a user-facing reminder message for hard-wrapped text. */
function buildHardWrapReminder(sources: TextSource[]): string {
  const sourcesWithIssues = sources.filter((s) => s.issues.length > 0);
  if (sourcesWithIssues.length === 0) return "";

  const totalIssues = sourcesWithIssues.reduce((sum, s) => sum + s.issues.length, 0);

  const lines: string[] = [
    "[GH-HARD-WRAP-GUARD] This text contains hard-wrapped prose, which will render as columns of short lines on GitHub.",
    "",
    "Why: GitHub Flavored Markdown renders every newline as `<br>`. A paragraph wrapped at ~100",
    "columns becomes columns of short mid-sentence lines instead of reflowing to the reader's window.",
    "",
    "Affected text (showing first 2 sources, first 2 wraps per source):",
  ];

  for (const src of sourcesWithIssues.slice(0, 2)) {
    lines.push(``, `  ${src.label}:`);
    for (const w of src.issues.slice(0, 2)) {
      lines.push(`    L${w.line}: ${w.width} cols → continues: "${w.nextPreview}"`);
    }
    if (src.issues.length > 2) {
      lines.push(`    …and ${src.issues.length - 2} more wrapped line(s).`);
    }
  }

  if (sourcesWithIssues.length > 2) {
    lines.push(``, `  …and ${sourcesWithIssues.length - 2} more source(s) with wraps.`);
  }

  lines.push(
    "",
    "Fix: author each PARAGRAPH as ONE unbroken line. Let GitHub reflow it to the reader's window.",
    "Keep only intentional breaks (list items, headings, code blocks, blank lines).",
    "",
    "Or repair an existing file mechanically (joins lines only; refuses to run if content would change):",
    '  bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" <file>',
    '  bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" --check <file>   # just report',
    "",
    "Override (rare — e.g. an intentional code sample): add GH-HARD-WRAP-OK anywhere in the command.",
  );

  return lines.join("\n");
}

/**
 * The reminder for a body the guard could not see because this same command
 * creates it.
 *
 * This is deliberately a DENY and not a silent allow. Fail-open is right when a
 * guard cannot tell whether there is a problem; it is wrong when the guard can
 * see that the evidence is being created after it has looked. The remedy asked
 * for is trivial and always available: two Bash calls instead of one.
 */
function buildUnreadableReminder(unreadable: readonly UnreadableWrittenFile[]): string {
  return [
    "[GH-HARD-WRAP-GUARD] This command writes the body file and publishes it in ONE step, so the",
    "text cannot be checked for hard wrapping before it reaches GitHub.",
    "",
    ...unreadable.map((u) => `  ${u.flag} "${u.rawPath}" — does not exist yet; this command creates it.`),
    "",
    "Why it matters: GitHub Flavored Markdown renders every newline inside a paragraph as `<br>`.",
    "Prose wrapped at ~100 columns is frozen at that width and cannot reflow to the reader's window.",
    "",
    "Fix: split it into TWO Bash calls — write the file first, then publish it. The guard reads the",
    "file on the second call and can then vouch for it.",
    "",
    "  call 1:  cat > /tmp/body.md <<'EOF'  …  EOF",
    "  call 2:  gh issue comment N --body-file /tmp/body.md",
    "",
    "A heredoc redirected straight into the published path IS readable and needs no split — this",
    "message means the write used a form the guard cannot parse (printf, tee, a script).",
    "",
    "Override: add GH-HARD-WRAP-OK anywhere in the command.",
  ].join("\n");
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

  // Operator escape hatch.
  if (hasFileWideEscapeHatchMarkerInContent(command, HARD_WRAP_OK)) {
    allow();
    return;
  }

  // The collector applies the same verb matching and reports whether this command publishes at
  // all, so the fast path lives there now rather than being duplicated here — one place for the
  // "is this a GFM surface?" question means the two guards cannot disagree about it.
  const collected = await collectGitHubPublishedBodies(command, input.cwd);
  if (!collected.isPublishingCommand) {
    allow();
    return;
  }

  const sources: TextSource[] = [];
  for (const body of collected.bodies) {
    const issues = detectHardWraps(body.text);
    if (issues.length > 0) sources.push({ label: body.label, text: body.text, issues });
  }
  const unreadable: readonly UnreadableWrittenFile[] = collected.unreadable;

  // A measured wrap outranks an unmeasurable body: report the concrete defect.
  if (sources.length > 0) {
    deny(buildHardWrapReminder(sources));
    return;
  }

  if (unreadable.length > 0) {
    deny(buildUnreadableReminder(unreadable));
    return;
  }

  allow();
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
