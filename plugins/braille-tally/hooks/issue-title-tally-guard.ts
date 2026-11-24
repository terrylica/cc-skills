#!/usr/bin/env bun
// # PROCESS-STORM-OK: spawns no process; every loop scans a string in memory and is bounded.
/**
 * PreToolUse guard: every GitHub issue title an agent writes starts with a Braille Tally.
 *
 * The same convention as AskUserQuestion options: a reader scanning an issue list sees at a glance how each issue was
 * assessed (Importance · Urgency · Simplicity by default), in the same shape everywhere. The title is the tally, one
 * space, then the title text: "⣿⣶⣴ Fix the login timeout". The glyph alone: no levels in digits ("(8·6·5)") and no
 * numbering ("1.", "#3", "IV.") in front of the text.
 *
 * What it reads (only literal values; a title built from a variable, a command substitution or a file is not known
 * here, and is allowed):
 *   - Bash: `gh issue create|new|edit … --title/-t VALUE` (also --title=VALUE, -tVALUE, -t=VALUE), including inside
 *           $( … ), backticks and a heredoc fed to a shell;
 *           `gh api … repos/OWNER/REPO/issues[/N]` with a `title=` field (-f, -F, --field, --raw-field), unless -X GET;
 *           `gh api graphql` with a createIssue/updateIssue mutation: its literal `title: "…"`, or the field that
 *           supplies the variable it names;
 *   - Write / Edit of a shell script (.sh, .bash, .zsh, or a shell shebang): titles the change adds, so a script run
 *     later cannot skip the rule, while titles already in the file are left alone;
 *   - GitHub MCP tools (a server name containing "github") ending in create_issue, update_issue or issue_write.
 * Known limit: a JSON body sent with `gh api --input` is not read.
 *
 * DENY, never repair: the guard says exactly what to change and hands the call back.
 *
 * Escape hatch: the plugin's one token, BRAILLE-TALLY-EXEMPT, anywhere in the tool input (for example a trailing shell
 * comment), for a title that genuinely cannot carry a tally (a title an upstream template or bot must match exactly).
 * It is named in skills/braille-tally/SKILL.md and here, deliberately NOT in the deny message.
 *
 * Fail-open everywhere: unparseable stdin, an unexpected payload or a thrown error allows the call.
 */
import { readFileSync, statSync } from "node:fs";
import { CELLS, leadingTally } from "../lib/tally.ts";

export const ESCAPE_TOKEN = "BRAILLE-TALLY-EXEMPT";

/** A shell word: its text after quote removal, and where the first expansion ($VAR, $(…), `…`) begins, or -1. */
export interface Word { text: string; dynamicAt: number }

const SHELLS = new Set(["sh", "bash", "zsh", "dash", "ksh"]);
const WRAPPERS = new Set(["env", "command", "builtin", "exec", "nohup", "time", "sudo", "nice", "stdbuf", "timeout"]);
const ASSIGNMENT = /^[A-Za-z_]\w*=/;
const base = (w: Word | undefined) => (w ? w.text.slice(w.text.lastIndexOf("/") + 1) : "");

/** Index of the word that is run: past assignments (X=1), wrappers (env, sudo, timeout 5, …) and their flags. */
export function executableAt(words: readonly Word[]): number {
  let i = 0;
  for (let hops = 0; hops < 16; hops++) {
    while (i < words.length && ASSIGNMENT.test(words[i]!.text)) i++;
    const b = base(words[i]);
    if (!WRAPPERS.has(b)) return i;
    i++;
    while (i < words.length && (words[i]!.text.startsWith("-") || ASSIGNMENT.test(words[i]!.text))) i++;
    if (b === "timeout") i++;
  }
  return i;
}

/** Index just past the ")" that closes a "(" whose body starts at `from`; quote-aware, depth-counted. */
function closeParen(src: string, from: number): number {
  let depth = 1;
  let j = from;
  while (j < src.length && depth > 0) {
    const ch = src[j]!;
    if (ch === "'") { const k = src.indexOf("'", j + 1); j = k < 0 ? src.length : k + 1; continue; }
    if (ch === '"') { j++; while (j < src.length && src[j] !== '"') j += src[j] === "\\" ? 2 : 1; j++; continue; }
    if (ch === "\\") { j += 2; continue; }
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
    j++;
  }
  return j;
}

const ANSI_C: Record<string, string> = { n: "\n", t: "\t", r: "\r", "\\": "\\", "'": "'", '"': '"', e: "\u001b", a: "\u0007" };

/**
 * Split shell text into simple commands (lists of words), quote-aware. Control operators (; & | newline, and parentheses
 * outside quotes) end a command; `#` at the start of a word starts a comment. Commands inside $( … ) and backticks, and
 * the body of a heredoc fed to a shell, are returned as commands too; any other heredoc body is data and is skipped.
 * Not a full shell parser: enough to find literal flag values, and on anything it cannot follow it errs toward fewer
 * words, which allows the call.
 */
export function commands(src: string, depth = 0): Word[][] {
  const out: Word[][] = [];
  const nested = (body: string) => { if (depth < 4) out.push(...commands(body, depth + 1)); };
  let cmd: Word[] = [];
  let text = "";
  let dyn = -1;
  let inWord = false;
  let heredocs: { delim: string; strip: boolean; cmd: Word[] }[] = [];
  const endWord = () => {
    if (inWord) cmd.push({ text, dynamicAt: dyn });
    text = ""; dyn = -1; inWord = false;
  };
  const endCmd = () => { endWord(); if (cmd.length) out.push(cmd); cmd = []; };
  const markDyn = () => { if (dyn < 0) dyn = text.length; };
  let i = 0;
  while (i < src.length) {
    const c = src[i]!;
    if (c === "$" && src[i + 1] === "'") {
      inWord = true;
      let j = i + 2;
      while (j < src.length && src[j] !== "'") {
        if (src[j] === "\\" && j + 1 < src.length) { text += ANSI_C[src[j + 1]!] ?? src[j + 1]; j += 2; continue; }
        text += src[j]; j++;
      }
      i = j + 1;
      continue;
    }
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
        const d = src[i]!;
        if (d === "\\" && i + 1 < src.length && '"\\$`\n'.includes(src[i + 1]!)) { text += src[i + 1]; i += 2; continue; }
        if (d === "$" && src[i + 1] === "(") { const end = closeParen(src, i + 2); nested(src.slice(i + 2, end - 1)); markDyn(); text += src.slice(i, end); i = end; continue; }
        if (d === "`") { const k = src.indexOf("`", i + 1); const end = k < 0 ? src.length : k + 1; nested(src.slice(i + 1, end - 1)); markDyn(); text += src.slice(i, end); i = end; continue; }
        if (d === "$") markDyn();
        text += d;
        i++;
      }
      i++;
      continue;
    }
    if (c === "\\") {
      if (src[i + 1] === "\n") { i += 2; continue; }
      inWord = true; text += src[i + 1] ?? ""; i += 2; continue;
    }
    if (c === "$" && src[i + 1] === "(") {
      inWord = true; markDyn();
      const end = closeParen(src, i + 2);
      nested(src.slice(i + 2, end - 1));
      text += src.slice(i, end); i = end;
      continue;
    }
    if (c === "`") {
      inWord = true; markDyn();
      const k = src.indexOf("`", i + 1);
      const end = k < 0 ? src.length : k + 1;
      nested(src.slice(i + 1, end - 1));
      text += src.slice(i, end); i = end;
      continue;
    }
    if (c === "#" && !inWord) {
      const j = src.indexOf("\n", i);
      i = j < 0 ? src.length : j;
      continue;
    }
    if (c === "<" && src[i + 1] === "<" && src[i + 2] !== "<" && !inWord) {
      let j = i + 2;
      const strip = src[j] === "-";
      if (strip) j++;
      while (src[j] === " " || src[j] === "\t") j++;
      const m = /^(?:'([^']*)'|"([^"]*)"|([^\s;&|<>()]+))/.exec(src.slice(j, j + 256));
      if (m) {
        heredocs.push({ delim: (m[1] ?? m[2] ?? m[3] ?? "").replaceAll("\\", ""), strip, cmd });
        i = j + m[0].length;
        continue;
      }
    }
    if (c === "\n" && heredocs.length) {
      endCmd();
      let j = i + 1;
      for (const h of heredocs) {
        const lines: string[] = [];
        while (j < src.length) {
          const nl = src.indexOf("\n", j);
          const line = src.slice(j, nl < 0 ? src.length : nl);
          j = nl < 0 ? src.length : nl + 1;
          if ((h.strip ? line.replace(/^\t+/, "") : line) === h.delim) break;
          lines.push(line);
        }
        if (SHELLS.has(base(h.cmd[executableAt(h.cmd)]))) nested(lines.join("\n"));
      }
      heredocs = [];
      i = j;
      continue;
    }
    if (c === "\n" || c === ";" || c === "&" || c === "|" || c === "(" || c === ")") { endCmd(); i++; continue; }
    if (c === " " || c === "\t" || c === "\r") { endWord(); i++; continue; }
    if (c === "$") markDyn();
    inWord = true; text += c; i++;
  }
  endCmd();
  return out;
}

const ISSUE_ENDPOINT = /^\/?repos\/[^/\s]+\/[^/\s]+\/issues(?:\/\d+)?\/?(?:\?.*)?$/;
/** gh issue create/edit flags that take no value; every other `--flag` or `-x` consumes the next word. */
const NO_VALUE = new Set(["--web", "-w", "--remove-milestone", "--help", "-h"]);
const MUTATION = /\b(?:createIssue|updateIssue)\s*\(/g;
const shifted = (w: Word, from: number): Word => ({ text: w.text.slice(from), dynamicAt: w.dynamicAt < 0 ? -1 : Math.max(0, w.dynamicAt - from) });

/** The `key=value` fields of a gh api call; a typed field (-F) whose value starts with "@" reads a file and is unknown. */
function apiFields(args: readonly Word[]): Map<string, Word> {
  const fields = new Map<string, Word>();
  const add = (w: Word, typed: boolean) => {
    const eq = w.text.indexOf("=");
    if (eq <= 0) return;
    const value = shifted(w, eq + 1);
    fields.set(w.text.slice(0, eq), typed && value.text.startsWith("@") ? { text: value.text, dynamicAt: 0 } : value);
  };
  for (let k = 0; k < args.length; k++) {
    const t = args[k]!.text;
    if ((t === "-f" || t === "--raw-field" || t === "-F" || t === "--field") && args[k + 1]) { add(args[k + 1]!, t === "-F" || t === "--field"); k++; }
    else if (t.startsWith("--raw-field=")) add(shifted(args[k]!, 12), false);
    else if (t.startsWith("--field=")) add(shifted(args[k]!, 8), true);
    else if (/^-[fF]./.test(t)) add(shifted(args[k]!, 2), t[1] === "F");
  }
  return fields;
}

/** Issue titles in a GraphQL document: only inside createIssue/updateIssue(…), literal or through a variable. */
function graphqlTitles(query: Word, fields: Map<string, Word>): Word[] {
  const q = query.text;
  const found: Word[] = [];
  for (const m of q.matchAll(MUTATION)) {
    const start = m.index + m[0].length;
    const span = q.slice(start, closeParen(q, start) - 1);
    const lit = /\btitle\s*:\s*"((?:[^"\\]|\\.)*)"/.exec(span);
    if (lit) {
      const end = start + lit.index + lit[0].length;
      if (query.dynamicAt >= 0 && end > query.dynamicAt) continue;
      try { found.push({ text: JSON.parse(`"${lit[1]}"`) as string, dynamicAt: -1 }); } catch { /* not decodable: unknown */ }
      continue;
    }
    const v = /\btitle\s*:\s*\$(\w+)/.exec(span);
    const value = v && fields.get(v[1]!);
    if (value) found.push(value);
  }
  return found;
}

/** Index of the gh subcommand after any leading -R/--repo flags, starting at `k`. */
function pastRepo(args: readonly Word[], k: number): number {
  for (let hops = 0; hops < 8; hops++) {
    const t = args[k]?.text ?? "";
    if (t === "-R" || t === "--repo") k += 2;
    else if (t.startsWith("--repo=") || /^-R./.test(t)) k++;
    else return k;
  }
  return k;
}

/** Every literal issue title a shell text would write, as Words (a dynamic title keeps its known prefix). */
export function titlesIn(src: string): Word[] {
  const found: Word[] = [];
  for (const words of commands(src)) {
    const at = executableAt(words);
    if (words[at]?.dynamicAt !== -1 || base(words[at]) !== "gh") continue;
    const args = words.slice(at + 1);
    let k = pastRepo(args, 0);
    const sub = args[k]?.text;
    if (sub === "issue") {
      k = pastRepo(args, k + 1);
      if (!["create", "new", "edit"].includes(args[k]?.text ?? "")) continue;
      for (k++; k < args.length; k++) {
        const t = args[k]!.text;
        if (t === "--") break;
        if ((t === "--title" || t === "-t") && args[k + 1]) { found.push(args[k + 1]!); k++; }
        else if (t.startsWith("--title=")) found.push(shifted(args[k]!, 8));
        else if (t.startsWith("-t=")) found.push(shifted(args[k]!, 3));
        else if (/^-t./.test(t)) found.push(shifted(args[k]!, 2));
        else if ((/^--[\w-]+$/.test(t) || /^-[A-Za-z]$/.test(t)) && !NO_VALUE.has(t)) k++;
      }
      continue;
    }
    if (sub !== "api") continue;
    const rest = args.slice(k + 1);
    const texts = rest.map((w) => w.text);
    const isGet = texts.some((t, n) => ((t === "-X" || t === "--method") && /^get$/i.test(texts[n + 1] ?? "")) || /^--method=get$/i.test(t) || /^-XGET$/i.test(t));
    if (isGet) continue;
    const fields = apiFields(rest);
    if (texts.includes("graphql")) {
      const query = fields.get("query");
      if (query) found.push(...graphqlTitles(query, fields));
      continue;
    }
    if (!texts.some((t) => ISSUE_ENDPOINT.test(t))) continue;
    const title = fields.get("title");
    if (title) found.push(title);
  }
  return found;
}

const NUMBERING = /^(?:\(\s*\d[\d\s·.,/-]*\)|\d+[.)]\s|#\d+\b|[IVXLC]+[.)]\s)/;
const TALLY_SO_FAR = new RegExp(`^[${CELLS}]{0,6} ?$`, "u");

/** What is wrong with one title, or undefined when it passes (or is not known here). */
export function titleProblem(title: Word): string | undefined {
  if (title.dynamicAt === 0) return undefined;
  const known = title.dynamicAt < 0 ? title.text : title.text.slice(0, title.dynamicAt);
  const lead = leadingTally(known);
  if (!lead) {
    // a dynamic title whose known prefix is only tally cells, or cells and a space, may still be fine
    if (title.dynamicAt > 0 && TALLY_SO_FAR.test(known)) return undefined;
    return `${JSON.stringify(title.text)} does not start with a Braille Tally and one space`;
  }
  if (NUMBERING.test(lead.rest)) return `${JSON.stringify(title.text)} puts levels or a number after the tally; the glyph alone, then the title text`;
  if (title.dynamicAt < 0 && !lead.rest.trim()) return `${JSON.stringify(title.text)} has a tally but no title text`;
  return undefined;
}

const SHELL_FILE = /\.(?:sh|bash|zsh)$/;
const SHELL_SHEBANG = /^#!.*\b(?:ba|z|da|k)?sh\b/;
const GITHUB_MCP = /^mcp__.*github.*__(?:create_issue|update_issue|issue_write)$/i;
const MAX_FILE = 2_000_000;

/** The file's current text, or "" when it does not exist, is too large or cannot be read. */
function current(path: string): string {
  try { return statSync(path).size <= MAX_FILE ? readFileSync(path, "utf8") : ""; } catch { return ""; }
}

/** Titles in `after` that `before` does not already have: a change is judged by what it adds. */
function added(before: string, after: string): Word[] {
  const old = new Map<string, number>();
  for (const w of before ? titlesIn(before) : []) old.set(w.text, (old.get(w.text) ?? 0) + 1);
  return titlesIn(after).filter((w) => {
    const n = old.get(w.text) ?? 0;
    if (n > 0) { old.set(w.text, n - 1); return false; }
    return true;
  });
}

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
    const path = typeof o.file_path === "string" ? o.file_path : "";
    const before = path ? current(path) : "";
    let after = "";
    if (toolName === "Write") after = typeof o.content === "string" ? o.content : "";
    else if (typeof o.new_string === "string") {
      const from = typeof o.old_string === "string" ? o.old_string : "";
      after = before && from && before.includes(from)
        ? (o.replace_all === true ? before.split(from).join(o.new_string) : before.replace(from, () => o.new_string as string))
        : o.new_string;
    }
    if (!after || !/\bgh\b/.test(after) || !(SHELL_FILE.test(path) || SHELL_SHEBANG.test(after))) return [];
    titles = added(before, after);
  } else if (GITHUB_MCP.test(toolName)) {
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
    if (raw.includes("gh")) {
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
