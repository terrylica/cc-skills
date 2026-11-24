#!/usr/bin/env bun
/**
 * PreToolUse guard: every GitHub issue title an agent writes starts with a Braille Tally.
 *
 * The same convention as AskUserQuestion options: a reader scanning an issue list sees at a glance how each issue was
 * assessed (Importance · Urgency · Simplicity by default), in the same shape everywhere. The title is the tally, one
 * space, then the title text: "⣿⣶⣴ Fix the login timeout". The glyph alone: no levels in digits ("(8·6·5)") and no
 * numbering ("1.", "#3", "IV.") in front of the text.
 *
 * What it reads (only literal values; a title built from a variable or a command substitution is not known here, and is
 * allowed):
 *   - Bash: `gh issue create|new|edit … --title/-t VALUE` (also --title=VALUE, -tVALUE, -t=VALUE);
 *           `gh api … repos/OWNER/REPO/issues[/N]` with a `title=` field (-f, -F, --field, --raw-field), unless -X GET;
 *           `gh api graphql` with a createIssue/updateIssue mutation: a literal `title: "…"` or a `title=` field;
 *   - Write / Edit of a shell script (.sh, .bash, .zsh, or a shell shebang): the same commands in the file's text, so a
 *     script run later cannot skip the rule;
 *   - GitHub MCP tools whose name ends in create_issue, update_issue or issue_write: their `title` argument.
 * `gh issue edit` without --title, and `gh issue create` without one (it prompts or opens the browser), are not checked.
 *
 * DENY, never repair: the guard says exactly what to change and hands the call back.
 *
 * Escape hatch: the plugin's one token, BRAILLE-TALLY-EXEMPT, anywhere in the tool input (for example a trailing shell
 * comment), for a title that genuinely cannot carry a tally (a title an upstream template or bot must match exactly).
 * It is named in skills/braille-tally/SKILL.md and here, deliberately NOT in the deny message.
 *
 * Fail-open everywhere: unparseable stdin, an unexpected payload or a thrown error allows the call.
 */
import { CELLS, leadingTally } from "../lib/tally.ts";

export const ESCAPE_TOKEN = "BRAILLE-TALLY-EXEMPT";

/** A shell word: its text after quote removal, and where the first expansion ($VAR, $(…), `…`) begins, or -1. */
export interface Word { text: string; dynamicAt: number }

/**
 * Split shell text into simple commands (lists of words), quote-aware. Control operators (; & | newline, and parentheses
 * outside quotes) end a command; `#` at the start of a word starts a comment. Not a full shell parser: enough to find
 * literal flag values reliably, and on anything it cannot follow it errs toward fewer words, which allows the call.
 */
export function commands(src: string): Word[][] {
  const out: Word[][] = [];
  let cmd: Word[] = [];
  let text = "";
  let dyn = -1;
  let inWord = false;
  const endWord = () => {
    if (inWord) cmd.push({ text, dynamicAt: dyn });
    text = ""; dyn = -1; inWord = false;
  };
  const endCmd = () => { endWord(); if (cmd.length) out.push(cmd); cmd = []; };
  const markDyn = () => { if (dyn < 0) dyn = text.length; };
  let i = 0;
  while (i < src.length) {
    const c = src[i]!;
    if (c === "'") {
      inWord = true;
      const j = src.indexOf("'", i + 1);
      const end = j < 0 ? src.length : j;
      text += src.slice(i + 1, end);
      i = end + 1;
      continue;
    }
    if (c === '"') {
      inWord = true;
      i++;
      while (i < src.length && src[i] !== '"') {
        if (src[i] === "\\" && i + 1 < src.length && '"\\$`\n'.includes(src[i + 1]!)) { text += src[i + 1]; i += 2; continue; }
        if (src[i] === "$" || src[i] === "`") markDyn();
        text += src[i];
        i++;
      }
      i++;
      continue;
    }
    if (c === "\\") {
      if (src[i + 1] === "\n") { i += 2; continue; }
      inWord = true; text += src[i + 1] ?? ""; i += 2; continue;
    }
    if (c === "#" && !inWord) {
      const j = src.indexOf("\n", i);
      i = j < 0 ? src.length : j;
      continue;
    }
    if (c === "\n" || c === ";" || c === "&" || c === "|" || c === "(" || c === ")") {
      if (c === "(" && inWord && text.endsWith("$")) {
        // $( … ): keep the substitution inside this word, unparsed; it makes the word dynamic.
        let depth = 1; let j = i + 1;
        while (j < src.length && depth > 0) { if (src[j] === "(") depth++; else if (src[j] === ")") depth--; j++; }
        markDyn(); text += src.slice(i, j); i = j; continue;
      }
      endCmd(); i++; continue;
    }
    if (c === " " || c === "\t" || c === "\r") { endWord(); i++; continue; }
    if (c === "$" || c === "`") markDyn();
    inWord = true; text += c; i++;
  }
  endCmd();
  return out;
}

const ISSUE_ENDPOINT = /^\/?repos\/[^/\s]+\/[^/\s]+\/issues(?:\/\d+)?\/?(?:\?.*)?$/;
const FIELD_FLAGS = new Set(["-f", "-F", "--field", "--raw-field"]);
const MUTATION = /\b(?:createIssue|updateIssue)\b/;
const LITERAL_TITLE = /\btitle\s*:\s*"((?:[^"\\]|\\.)*)"/g;

/** Every literal issue title a shell text would write, as Words (a dynamic title keeps its known prefix). */
export function titlesIn(src: string): Word[] {
  const found: Word[] = [];
  for (const words of commands(src)) {
    const at = words.findIndex((w) => w.dynamicAt < 0 && /(^|\/)gh$/.test(w.text));
    if (at < 0) continue;
    const args = words.slice(at + 1);
    const sub = args.map((w) => w.text);
    if (sub[0] === "issue" && ["create", "new", "edit"].includes(sub[1] ?? "")) {
      for (let k = 2; k < args.length; k++) {
        const t = args[k]!.text;
        const take = (w: Word, from: number) => found.push({ text: w.text.slice(from), dynamicAt: w.dynamicAt < 0 ? -1 : Math.max(0, w.dynamicAt - from) });
        if ((t === "--title" || t === "-t") && args[k + 1]) { found.push(args[k + 1]!); k++; }
        else if (t.startsWith("--title=")) take(args[k]!, 8);
        else if (t.startsWith("-t=")) take(args[k]!, 3);
        else if (/^-t./.test(t)) take(args[k]!, 2);
      }
      continue;
    }
    if (sub[0] !== "api") continue;
    const isGet = sub.some((t, k) => ((t === "-X" || t === "--method") && /^get$/i.test(sub[k + 1] ?? "")) || /^--method=get$/i.test(t) || /^-XGET$/i.test(t));
    const graphql = sub.includes("graphql");
    const rest = sub.some((t) => ISSUE_ENDPOINT.test(t));
    if (isGet || (!rest && !graphql)) continue;
    const fields: Word[] = [];
    for (let k = 1; k < args.length; k++) {
      const t = args[k]!.text;
      if (FIELD_FLAGS.has(t) && args[k + 1]) { fields.push(args[k + 1]!); k++; }
      else for (const p of ["--field=", "--raw-field=", "-f", "-F"]) if (t.startsWith(p) && t.length > p.length) { const w = args[k]!; fields.push({ text: t.slice(p.length), dynamicAt: w.dynamicAt < 0 ? -1 : Math.max(0, w.dynamicAt - p.length) }); break; }
    }
    const query = fields.find((f) => f.text.startsWith("query="))?.text ?? "";
    if (graphql && !MUTATION.test(query)) continue;
    for (const f of fields) if (f.text.startsWith("title=")) found.push({ text: f.text.slice(6), dynamicAt: f.dynamicAt < 0 ? -1 : Math.max(0, f.dynamicAt - 6) });
    if (graphql) for (const m of query.matchAll(LITERAL_TITLE)) found.push({ text: m[1]!.replace(/\\(.)/g, "$1"), dynamicAt: -1 });
  }
  return found;
}

const NUMBERING = /^(?:\(\s*\d[\d\s·.,/-]*\)|\d+[.)]\s|#\d+\b|[IVXLC]+[.)]\s)/;

/** What is wrong with one title, or undefined when it passes (or is not known here). */
export function titleProblem(title: Word): string | undefined {
  const known = title.dynamicAt < 0 ? title.text : title.text.slice(0, title.dynamicAt);
  if (title.dynamicAt === 0) return undefined;
  const lead = leadingTally(known);
  if (!lead) {
    // a dynamic title whose known prefix is only tally cells, or cells and a space, may still be fine
    if (title.dynamicAt > 0 && new RegExp(`^[${CELLS}]{0,6} ?$`, "u").test(known)) return undefined;
    return `${JSON.stringify(title.text)} does not start with a Braille Tally and one space`;
  }
  if (NUMBERING.test(lead.rest)) return `${JSON.stringify(title.text)} puts levels or a number after the tally; the glyph alone, then the title text`;
  if (title.dynamicAt < 0 && !lead.rest.trim()) return `${JSON.stringify(title.text)} has a tally but no title text`;
  return undefined;
}

const SHELL_FILE = /\.(?:sh|bash|zsh)$/;
const SHELL_SHEBANG = /^#!.*\b(?:ba|z|da|k)?sh\b/;

/** The problems with one tool call, as plain sentences; empty means it passes. */
export function problems(toolName: string, input: unknown): string[] {
  if (!input || typeof input !== "object") return [];
  let serialized = "";
  try { serialized = JSON.stringify(input) ?? ""; } catch { return []; }
  if (serialized.includes(ESCAPE_TOKEN)) return [];
  const o = input as Record<string, unknown>;
  let titles: Word[] = [];
  if (toolName === "Bash") {
    if (typeof o.command !== "string" || !/\bgh\b/.test(o.command)) return [];
    titles = titlesIn(o.command);
  } else if (toolName === "Write" || toolName === "Edit") {
    const text = typeof o.content === "string" ? o.content : typeof o.new_string === "string" ? o.new_string : "";
    const path = typeof o.file_path === "string" ? o.file_path : "";
    if (!text || !/\bgh\b/.test(text) || !(SHELL_FILE.test(path) || SHELL_SHEBANG.test(text))) return [];
    titles = titlesIn(text);
  } else if (/(?:create_issue|update_issue|issue_write)$/.test(toolName)) {
    if (typeof o.title === "string") titles = [{ text: o.title, dynamicAt: -1 }];
  }
  return titles.map(titleProblem).filter((p): p is string => !!p);
}

export function denyMessage(found: string[]): string {
  return [
    "Every GitHub issue title starts with a Braille Tally (braille-tally plugin), the same convention as AskUserQuestion options: one Braille cell per axis, one space, then the title, e.g. \"⣿⣶⣴ Fix the login timeout\".",
    "Level n (1-8) is the cell with n dots: ⡀ ⣀ ⣠ ⣤ ⣴ ⣶ ⣾ ⣿. Axes, in this order: Importance (how much it serves the goal), Urgency (how soon it matters), Simplicity (how little it takes). The glyph alone: no digits like (8·6·5), no numbering.",
    "Problems:",
    ...found.map((f) => `- ${f}`),
    "Fix the title, then run it again. `bun \"$(cc-plugin-root braille-tally)/scripts/braille-tally.ts\" tally 8 6 5` prints a tally; retitle an existing issue with `gh issue edit N --title \"⣿⣶⣴ …\"`.",
  ].join("\n");
}

if (import.meta.main) {
  try {
    const raw = await Bun.stdin.text();
    if (raw.includes("gh") || raw.includes("issue")) {
      const payload = JSON.parse(raw) as { tool_name?: string; tool_input?: unknown };
      const found = problems(payload.tool_name ?? "", payload.tool_input);
      if (found.length) {
        console.log(JSON.stringify({
          hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: denyMessage(found) },
        }));
      }
    }
  } catch {
    // fail open
  }
  process.exit(0);
}
