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

import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { detectHardWraps, type WrapIssue } from "./lib/hard-wrap-detector.ts";
import { extractFlagValues } from "./lib/shell-arg-extractor.ts";

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

/** Expand a leading `~` and resolve a file path relative to the tool cwd. */
function resolveFilePath(rawPath: string, cwd: string | undefined): string {
  let p = rawPath;
  if (p === "~") p = homedir();
  else if (p.startsWith("~/")) p = `${homedir()}/${p.slice(2)}`;
  if (isAbsolute(p)) return p;
  const base = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  return resolve(base, p);
}

/**
 * Match the verb as an ADJACENT token sequence (`gh release create`), never as
 * independent substrings anywhere in the command.
 *
 * Testing `/\bgh\s/` and `/\brelease\s+(create|edit)/` separately makes any
 * command that merely MENTIONS the pattern a match — writing documentation
 * about this guard, grepping for it, or committing a message that quotes it.
 * The sibling release-notes-extensiveness-guard has that flaw and blocked a
 * `cat >> notes.md` heredoc whose prose quoted the command it watches for.
 */
const adjacent = (noun: string, verbs: string) =>
  new RegExp(String.raw`\bgh\s+${noun}\s+(?:${verbs})\b`, "i");

const GH_RELEASE = adjacent("release", "create|edit");
const GH_ISSUE = adjacent("issue", "create|edit|comment");
const GH_PR = adjacent("pr", "create|edit|comment");

/** True when the command is a `gh release` create or edit. */
function isGhReleaseCommand(command: string): boolean {
  return GH_RELEASE.test(command);
}

/** True when the command is a `gh issue` command (create/edit/comment). */
function isGhIssueCommand(command: string): boolean {
  return GH_ISSUE.test(command);
}

/** True when the command is a `gh pr` command (create/edit/comment). */
function isGhPrCommand(command: string): boolean {
  return GH_PR.test(command);
}

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
    "Override (rare — e.g. an intentional code sample): add GH-HARD-WRAP-OK anywhere in the command.",
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

  // Operator escape hatch.
  if (hasFileWideEscapeHatchMarkerInContent(command, HARD_WRAP_OK)) {
    allow();
    return;
  }

  // Fast path: if none of the target patterns match, no guard needed.
  if (!isGhReleaseCommand(command) && !isGhIssueCommand(command) && !isGhPrCommand(command)) {
    allow();
    return;
  }

  const sources: TextSource[] = [];
  const cwd = input.cwd;

  // ---- gh release create|edit: --notes / --notes-file ----
  if (isGhReleaseCommand(command)) {
    const inlineNotes = extractFlagValues(command, ["--notes", "-n"]);
    for (const notes of inlineNotes) {
      const issues = detectHardWraps(notes);
      if (issues.length > 0) sources.push({ label: "--notes (inline)", text: notes, issues });
    }

    const notesFiles = extractFlagValues(command, ["--notes-file", "-F"]);
    for (const rawPath of notesFiles) {
      const resolved = resolveFilePath(rawPath, cwd);
      if (!existsSync(resolved)) continue;
      let text: string;
      try {
        text = await Bun.file(resolved).text();
      } catch {
        continue; // unreadable → skip, never block
      }
      const issues = detectHardWraps(text);
      if (issues.length > 0)
        sources.push({ label: `--notes-file "${rawPath}"`, text, issues });
    }
  }

  // ---- gh issue/pr create: --body / -b ----
  if (isGhIssueCommand(command) || isGhPrCommand(command)) {
    const inlineBody = extractFlagValues(command, ["--body", "-b"]);
    for (const body of inlineBody) {
      const issues = detectHardWraps(body);
      if (issues.length > 0) sources.push({ label: "--body (inline)", text: body, issues });
    }

    // Only issue/pr create accept --body-file, not edit/comment.
    // The guard checks conservatively: if the flag is present, process it.
    const bodyFiles = extractFlagValues(command, ["--body-file"]);
    for (const rawPath of bodyFiles) {
      const resolved = resolveFilePath(rawPath, cwd);
      if (!existsSync(resolved)) continue;
      let text: string;
      try {
        text = await Bun.file(resolved).text();
      } catch {
        continue; // unreadable → skip, never block
      }
      const issues = detectHardWraps(text);
      if (issues.length > 0)
        sources.push({ label: `--body-file "${rawPath}"`, text, issues });
    }
  }

  if (sources.length > 0) {
    deny(buildHardWrapReminder(sources));
    return;
  }

  allow();
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
