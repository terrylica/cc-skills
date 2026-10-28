#!/usr/bin/env bun
/**
 * PreToolUse HTML measure guard: text on an HTML page follows the browser window.
 *
 * Operator, 2026-10-28: "There shouldn't be any hard wrapping of lines" in anything presented as HTML or
 * Markdown, made a forced convention for every Orca artifact and HTML page. The Markdown half is already
 * guarded (markdown-hard-wrap reminders and the commit guard). This is the HTML half: CSS that fixes where a
 * line of text ends (a 72em measure, a 1560px page cap, pre-line whitespace on prose) is the page equivalent
 * of a hard-wrapped paragraph. Rules: lib/html-text-measure-detector.ts.
 *
 * Two surfaces, one detector:
 *   1. Write|Edit (subhook of pretooluse-write-edit-orchestrator.ts): DENIES writing a page, stylesheet or
 *      page builder (.html .css .py .ts .js …) that INTRODUCES a fixed text width. For an Edit the whole file
 *      after the edit is compared with the file before it, so only net-new findings count and an existing
 *      page stays editable.
 *   2. Bash (entry of pretooluse-bash-guard-orchestrator.ts): DENIES `orca artifacts share|update FILE` of a
 *      page with a fixed text width, and `wrangler pages deploy DIR` when a page in DIR has one. This catches
 *      pages written by generator scripts, which the Write|Edit surface never sees.
 *
 * Escape hatch: HTML-MEASURE-OK (FILE_WIDE) in the file, in the proposed text, or anywhere in the command, for
 * a page that must stay as it is (an outside page archived verbatim). Fails open on any error.
 * Spoke: plugins/itp-hooks/docs/html-measure-guard.md.
 */

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { homedir } from "node:os";
import {
  allow,
  deny,
  isPlanMode,
  parseStdinOrAllow,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-iter84.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/escape-hatch-marker-detection-iter107.ts";
import {
  HTML_MEASURE_ESCAPE_MARKER,
  findTextMeasureViolations,
  isPageOrPageBuilderPath,
  netNewTextMeasureViolations,
} from "./lib/html-text-measure-detector.ts";

const ESCAPE = {
  markerNameTokenIncludingSuffix: HTML_MEASURE_ESCAPE_MARKER,
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 0,
};
const MAX_PAGE_BYTES = 40 * 1024 * 1024;
const MAX_DEPLOY_PAGES = 2000;

function hasEscape(text: string | undefined): boolean {
  return !!text && hasFileWideEscapeHatchMarkerInContent(text, ESCAPE);
}

export function explainTextMeasureFindings(where: string, findings: string[]): string {
  const shown = [...new Set(findings)].slice(0, 6).map((f) => `  - ${f}`).join("\n");
  return `[HTML-MEASURE-GUARD] ${where} fixes where lines of text end:
${shown}

Text on an HTML page follows the browser window (operator, 2026-10-28: no hard wrapping in anything
presented as HTML or Markdown; every Orca artifact and HTML page).
  - No max-width in em, ch or rem (also inside min()/clamp()), and no width in ch.
  - No px max-width on a page container (body, main, article, .inner, .wrap, .container, .page …).
  - No white-space: pre / pre-wrap / pre-line on prose (pre, code and textarea may keep their lines).
Keep: @media conditions, images (max-width:100%), charts, tooltips, banners, table columns (min-width),
and give wide tables their own overflow-x:auto box instead of narrowing the page.

Fix: delete the declaration so the text fills the window.
Escape (an outside page that must stay verbatim): put HTML-MEASURE-OK in the file or the command.`;
}

/** The whole file as it would be after this Write or Edit, and as it is now ("" when new). */
function fileBeforeAndAfter(input: PreToolUseInput): { before: string; after: string } | null {
  const ti = input.tool_input;
  const filePath = ti.file_path;
  if (!filePath) return null;
  let before = "";
  if (existsSync(filePath)) {
    try {
      if (statSync(filePath).size > MAX_PAGE_BYTES) return null;
      before = readFileSync(filePath, "utf8");
    } catch {
      before = "";
    }
  }
  if (input.tool_name === "Write") return { before, after: typeof ti.content === "string" ? ti.content : "" };
  const oldString = typeof ti.old_string === "string" ? ti.old_string : "";
  const newString = typeof ti.new_string === "string" ? ti.new_string : "";
  if (before && oldString && before.includes(oldString)) {
    const after = ti.replace_all === true ? before.split(oldString).join(newString) : before.replace(oldString, () => newString);
    return { before, after };
  }
  return { before: oldString, after: newString };   // file unreadable or edit not locatable: compare the strings
}

// ============================================================================
// Surface 1: Write|Edit subhook (conforms to PreToolUseSubhookClassifierFunction)
// ============================================================================

export async function classifyHtmlMeasureGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  try {
    if (isPlanMode(input).inPlanMode) return ALLOW_DECISION;
    if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(input.tool_name)) return ALLOW_DECISION;
    const filePath = input.tool_input.file_path;
    if (!filePath || !isPageOrPageBuilderPath(filePath)) return ALLOW_DECISION;
    const proposed = String(input.tool_input.content ?? input.tool_input.new_string ?? "");
    if (!/max-width|width\s*:\s*[\d.]+ch|white-space/i.test(proposed)) return ALLOW_DECISION;   // O(1)-ish fastpath
    const pair = fileBeforeAndAfter(input);
    if (!pair) return ALLOW_DECISION;
    if (hasEscape(proposed) || hasEscape(pair.before)) return ALLOW_DECISION;
    const added = netNewTextMeasureViolations(pair.before, pair.after);
    if (added.length === 0) return ALLOW_DECISION;
    return denyDecision(explainTextMeasureFindings(filePath, added));
  } catch (error) {
    trackHookError("html-measure-guard", String(error));
    return ALLOW_DECISION;
  }
}

// ============================================================================
// Surface 2: Bash (orca artifacts share|update FILE; wrangler pages deploy DIR)
// ============================================================================

function unquote(token: string): string {
  return token.replace(/^(['"])([\s\S]*)\1$/, "$2");
}

function resolvePath(raw: string, cwd: string | undefined): string {
  const p = unquote(raw).replace(/^~(?=\/|$)/, homedir());
  return isAbsolute(p) ? p : resolve(cwd || process.cwd(), p);
}

/** The first non-flag argument after each match of `verb` in the command. */
export function targetsAfter(command: string, verb: RegExp): string[] {
  const out: string[] = [];
  for (const m of command.matchAll(verb)) {
    const rest = command.slice(m.index! + m[0].length);
    const tokens = rest.match(/"[^"]*"|'[^']*'|[^\s;&|)]+/g) ?? [];
    for (const t of tokens) {
      if (t.startsWith("-")) continue;
      out.push(t);
      break;
    }
  }
  return out;
}

const ORCA_PUBLISH = /\borca\s+artifacts\s+(?:share|update)\b/g;
const WRANGLER_PAGES_DEPLOY = /\bwrangler(?:@[\w.]+)?\s+pages\s+deploy\b/g;

function pagesUnder(dir: string): string[] {
  const out: string[] = [];
  const walk = (d: string) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      if (out.length >= MAX_DEPLOY_PAGES) return;
      const p = join(d, e.name);
      if (e.isDirectory() && e.name !== "node_modules" && !e.name.startsWith(".")) walk(p);
      else if (e.isFile() && /\.html?$/i.test(e.name)) out.push(p);
    }
  };
  walk(dir);
  return out;
}

function pageFindings(path: string): string[] {
  try {
    const st = statSync(path);
    if (!st.isFile() || st.size > MAX_PAGE_BYTES) return [];
    const text = readFileSync(path, "utf8");
    return hasEscape(text) ? [] : findTextMeasureViolations(text);
  } catch {
    return [];
  }
}

/** Pages this command would publish that fix their text width: [label, findings][]. */
export function publishedPageFindings(command: string, cwd: string | undefined): [string, string[]][] {
  const bad: [string, string[]][] = [];
  for (const raw of targetsAfter(command, ORCA_PUBLISH)) {
    const path = resolvePath(raw, cwd);
    if (!/\.html?$/i.test(path) || !existsSync(path)) continue;     // a remote path (ssh) or a non-page: skip
    const f = pageFindings(path);
    if (f.length) bad.push([unquote(raw), f]);
  }
  for (const raw of targetsAfter(command, WRANGLER_PAGES_DEPLOY)) {
    const dir = resolvePath(raw, cwd);
    try {
      if (!existsSync(dir) || !statSync(dir).isDirectory()) continue;
    } catch {
      continue;
    }
    for (const page of pagesUnder(dir)) {
      const f = pageFindings(page);
      if (f.length) bad.push([page.slice(dir.length + 1) || page, f]);
    }
  }
  return bad;
}

export async function main(): Promise<void> {
  const input = await parseStdinOrAllow("HTML-MEASURE-GUARD");
  if (!input) return;
  try {
    if (input.tool_name !== "Bash") return allow();
    const command = input.tool_input.command || "";
    if (!/\borca\s+artifacts\b|\bwrangler\b/.test(command) || hasEscape(command)) return allow();
    const bad = publishedPageFindings(command, input.cwd);
    if (bad.length === 0) return allow();
    const [label, findings] = bad[0]!;
    const more = bad.length > 1 ? `\n(and ${bad.length - 1} more page(s): ${bad.slice(1, 4).map((b) => b[0]).join(", ")})` : "";
    return deny(explainTextMeasureFindings(`Publishing ${label}`, findings) + more);
  } catch (error) {
    trackHookError("html-measure-guard", String(error));
    return allow();
  }
}

if (import.meta.main) {
  void main().catch((err) => {
    trackHookError("html-measure-guard", String(err));
    allow();
  });
}
