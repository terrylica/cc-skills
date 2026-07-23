#!/usr/bin/env bun
/**
 * PreToolUse hook: Gmail draft body guard.
 *
 * Blocks a `gmail draft` / `draft-update` whose body would render badly in the
 * recipient's inbox — BEFORE the bad draft is created. Two failure modes:
 *   1. HARD-WRAP — the gmail CLI turns every authored newline into an HTML `<br>`
 *      (gmail-drafts.ts `toHtmlBody`), so a paragraph wrapped at a fixed column
 *      renders as a column of short mid-sentence lines instead of reflowing.
 *   2. RAW MARKDOWN — the CLI HTML-escapes the body and does not render markdown,
 *      so `**bold**` / `` `code` `` / `[text](url)` / `#` / `|tables|` show
 *      literally.
 * The rule it enforces — single-line paragraphs, plain prose — is the gmail
 * skill's own doctrine (gmail-access/SKILL.md Evolution Log 2026-07-10 / -07-22).
 *
 * Inspected inputs:
 *   - `--body "<inline>"`  (single/double/`$'…'`/bare quoting)
 *   - `--body-file <path>` (read from disk; `~` and cwd-relative resolved)
 *
 * Output: PreToolUse `deny` with a reminder listing the offending lines and the
 * single fix. Escape hatch: `GMAIL-BODY-OK` anywhere in the command.
 *
 * Fail-open everywhere: any parse/read/logic error → allow (never blocks real
 * work). A missing/unreadable `--body-file` is skipped, not blocked.
 */

import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import {
  type BodySource,
  buildBodyReminder,
  detectBodyIssues,
  hasBodyIssues,
  isGmailDraftCommand,
  parseGmailDraftBodies,
} from "./lib/gmail-body-detector.ts";

const HOOK_NAME = "gmail-body-guard";

/** Operator escape hatch for an intentional wrapped/markdown body (e.g. an ASCII table). */
const BODY_OK_OVERRIDE = /\bGMAIL-BODY-OK\b/;

/** Expand a leading `~` and resolve a body-file path relative to the tool cwd. */
function resolveBodyFilePath(rawPath: string, cwd: string | undefined): string {
  let p = rawPath;
  if (p === "~") p = homedir();
  else if (p.startsWith("~/")) p = `${homedir()}/${p.slice(2)}`;
  if (isAbsolute(p)) return p;
  const base = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  return resolve(base, p);
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("GMAIL-BODY-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";
  if (!command.trim() || !isGmailDraftCommand(command)) {
    allow();
    return;
  }

  // Operator escape hatch.
  if (BODY_OK_OVERRIDE.test(command)) {
    allow();
    return;
  }

  const { inline, bodyFilePaths } = parseGmailDraftBodies(command);
  const sources: BodySource[] = [];

  for (const body of inline) {
    const issues = detectBodyIssues(body);
    if (hasBodyIssues(issues)) sources.push({ label: "--body", issues });
  }

  for (const rawPath of bodyFilePaths) {
    const resolved = resolveBodyFilePath(rawPath, input.cwd);
    if (!existsSync(resolved)) continue; // missing file → skip, never block
    let text: string;
    try {
      text = await Bun.file(resolved).text();
    } catch {
      continue; // unreadable → skip, never block
    }
    const issues = detectBodyIssues(text);
    if (hasBodyIssues(issues)) sources.push({ label: `--body-file ${rawPath}`, issues });
  }

  if (sources.length > 0) {
    deny(buildBodyReminder(sources));
    return;
  }

  allow();
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
