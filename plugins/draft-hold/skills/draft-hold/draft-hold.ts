#!/usr/bin/env bun
/**
 * draft-hold.ts — Bun/TypeScript engine for the draft-hold skill.
 *
 * HARDENING (why this exists): the previous per-line bash formatter turned EVERY input line into
 * its own Notes paragraph, so accidentally hard-wrapped prose rendered as permanent mid-sentence
 * line breaks that never reflowed. This engine makes that impossible by construction:
 *   • prose blocks REFLOW — consecutive non-blank lines join into one paragraph; a blank line
 *     starts a new paragraph (CommonMark-style). Notes then soft-wraps to the reader's screen.
 *   • Markdown list markers (-, *, +, •, "1.", "a)") each become their own line; a wrapped
 *     continuation line joins back to its item.
 *   • ``` fenced blocks are preserved VERBATIM in monospace (for columns / IDs / ASCII tables).
 * The pure formatter (bodyToHtml) is unit-tested in draft-hold.test.ts. No external deps.
 *
 * Commands mirror the old bash CLI:
 *   draft-hold.ts new "<title>" [--session UUID] [--project NAME] [--folder NAME]   # body on STDIN
 *   draft-hold.ts get "<title>" [--folder NAME] [--body-only]
 *   draft-hold.ts list [--folder NAME]
 *   draft-hold.ts sticky "<title>" [--folder NAME]
 */
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const FOLDER_DEFAULT = "Claude Drafts";
// A list item: optional indent, then a bullet (-, *, +, •, ·) or "1." / "1)" / "a." / "a)", then a space + content.
const LIST_RE = /^\s*([-*+•·]|\d+[.)]|[A-Za-z][.)])\s+\S/;

export function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

interface Block {
  kind: "fence" | "text";
  lines: string[];
}

/** East-Asian wide char? Used so reflowing hard-wrapped CJK prose doesn't inject stray spaces. */
function isCjk(ch: string): boolean {
  const c = ch.codePointAt(0);
  if (c === undefined) return false;
  return (
    (c >= 0x1100 && c <= 0x11ff) || // Hangul Jamo
    (c >= 0x2e80 && c <= 0x9fff) || // CJK radicals … CJK Unified Ideographs (incl. Hiragana/Katakana)
    (c >= 0xa960 && c <= 0xa97f) || // Hangul Jamo Extended-A
    (c >= 0xac00 && c <= 0xd7ff) || // Hangul syllables
    (c >= 0xf900 && c <= 0xfaff) || // CJK compatibility ideographs
    (c >= 0xff00 && c <= 0xffef) // halfwidth/fullwidth forms (incl. fullwidth punctuation)
  );
}

/**
 * Join hard-wrapped lines back into one logical line. A single space is inserted at each fold
 * EXCEPT where both sides are CJK wide characters (Chinese/Japanese/Korean don't space words),
 * so a pre-wrapped Chinese paragraph reflows seamlessly — the bilingual case this skill serves.
 */
function reflowJoin(lines: string[]): string {
  let out = "";
  for (const raw of lines) {
    const l = raw.trim();
    if (!l) continue;
    if (!out) {
      out = l;
      continue;
    }
    const prev = out[out.length - 1];
    const next = l[0];
    out += isCjk(prev) && isCjk(next) ? l : ` ${l}`;
  }
  return out;
}

/** Split raw lines into fenced (verbatim) vs text segments on ``` markers. */
function segmentByFence(lines: string[]): Block[] {
  const blocks: Block[] = [];
  let cur: string[] = [];
  let inFence = false;
  const flush = (kind: Block["kind"]) => {
    if (cur.length) blocks.push({ kind, lines: cur });
    cur = [];
  };
  for (const line of lines) {
    if (/^\s*```/.test(line)) {
      flush(inFence ? "fence" : "text");
      inFence = !inFence;
      continue;
    }
    cur.push(line);
  }
  flush(inFence ? "fence" : "text");
  return blocks;
}

/** Render a normal text segment: blank lines separate paragraphs; prose reflows; lists per-item. */
function renderTextBlock(lines: string[]): string[] {
  const paras: string[][] = [];
  let para: string[] = [];
  for (const l of lines) {
    if (l.trim() === "") {
      if (para.length) {
        paras.push(para);
        para = [];
      }
    } else {
      para.push(l);
    }
  }
  if (para.length) paras.push(para);

  const html: string[] = [];
  for (const p of paras) {
    if (LIST_RE.test(p[0])) {
      // group into items; a non-marker continuation line reflows into the current item
      const items: string[][] = [];
      let item: string[] = [];
      for (const l of p) {
        if (LIST_RE.test(l)) {
          if (item.length) items.push(item);
          item = [l];
        } else {
          item.push(l);
        }
      }
      if (item.length) items.push(item);
      for (const it of items) html.push(`<div>${escapeHtml(reflowJoin(it))}</div>`);
    } else {
      // prose: reflow the whole paragraph into ONE line — Notes wraps it naturally
      html.push(`<div>${escapeHtml(reflowJoin(p))}</div>`);
    }
    html.push("<div><br></div>");
  }
  return html;
}

/**
 * Render a ``` fenced block: each line preserved verbatim, monospace, for column/ID alignment.
 * Spaces/tabs become &nbsp; because HTML collapses runs of whitespace — without this the columns
 * a fenced block exists to align would silently close up (both in Notes and on read-back).
 */
function renderFenceBlock(lines: string[]): string[] {
  const html = lines.map((l) => {
    const encoded = escapeHtml(l).replaceAll("\t", "    ").replaceAll(" ", "&nbsp;");
    return `<div><tt>${encoded || "&nbsp;"}</tt></div>`;
  });
  html.push("<div><br></div>");
  return html;
}

/** PURE, TESTED: turn a plain-text body into Notes HTML that reflows prose and preserves fences. */
export function bodyToHtml(body: string): string {
  const lines = body.replace(/\r\n?/g, "\n").split("\n");
  const out: string[] = [];
  for (const b of segmentByFence(lines)) {
    out.push(...(b.kind === "fence" ? renderFenceBlock(b.lines) : renderTextBlock(b.lines)));
  }
  return out.join("");
}

function nowStamp(): string {
  const r = spawnSync("date", ["+%Y-%m-%d %H:%M %Z"], { encoding: "utf8" });
  return (r.stdout ?? "").trim();
}

function footerHtml(session: string, project: string): string {
  const sess = session ? `session ${escapeHtml(session)} | ` : "";
  return `<div><br></div><div><tt>------</tt></div><div><tt>Held by Claude Code | ${sess}${escapeHtml(project)} | ${nowStamp()}</tt></div>`;
}

export function buildNoteBody(title: string, body: string, session: string, project: string): string {
  const titleHtml = `<div><b>${escapeHtml(title)}</b></div><div><br></div>`;
  return titleHtml + bodyToHtml(body) + footerHtml(session, project);
}

// ---- read-back helpers (mirror the old bash awk behaviour) ----
function htmlToText(bodyHtml: string): string {
  // textutil misreads UTF-8 as Latin-1 without a charset declaration → prepend one.
  const r = spawnSync("textutil", ["-stdin", "-stdout", "-convert", "txt", "-format", "html"], {
    input: `<meta charset="utf-8">${bodyHtml}`,
    encoding: "utf8",
  });
  return r.stdout ?? "";
}

function collapseBlanks(s: string): string {
  const out: string[] = [];
  let prevNonEmpty = true;
  for (const l of s.split("\n")) {
    const nonEmpty = l.trim() !== "";
    if (nonEmpty || prevNonEmpty) out.push(l);
    prevNonEmpty = nonEmpty;
  }
  return out.join("\n");
}

function bodyOnly(full: string): string {
  const out: string[] = [];
  let state: "pre" | "title" | "body" = "pre";
  for (const line of full.split("\n")) {
    if (/^------\s*$/.test(line)) break;
    const blank = line.trim() === "";
    if (state === "pre") {
      if (blank) continue;
      state = "title";
      continue;
    }
    if (state === "title") {
      if (blank) continue;
      state = "body";
    }
    out.push(line);
  }
  return out.join("\n");
}

// ---- AppleScript payloads ----
// Create-then-swap: make the NEW note FIRST, then delete any OTHER notes sharing this title.
// A transient Notes AppleEvent failure can therefore never orphan the draft (the old copy
// survives until the new one exists), and a leftover duplicate from a past failure self-heals
// on the next run. Notes names a note by its first line, so the new note's name == noteTitle;
// we keep it by id and delete the rest.
const OSA_NEW = `on run {folderName, noteTitle, bodyHTML}
  tell application "Notes"
    if not (exists folder folderName) then make new folder with properties {name:folderName}
    set n to make new note at folder folderName with properties {body:bodyHTML}
    set newId to id of n
    set dupes to (notes of folder folderName whose name is noteTitle)
    repeat with x in dupes
      if (id of x) is not newId then delete x
    end repeat
    return newId
  end tell
end run`;

const OSA_GET = `on run {folderName, noteTitle}
  tell application "Notes"
    if not (exists note noteTitle of folder folderName) then return "(no such draft)"
    return body of note noteTitle of folder folderName
  end tell
end run`;

const OSA_LIST = `on run {folderName}
  tell application "Notes"
    if not (exists folder folderName) then return "(folder not found: " & folderName & ")"
    set out to ""
    repeat with n in notes of folder folderName
      set out to out & (name of n) & linefeed
    end repeat
    return out
  end tell
end run`;

function osascript(script: string, args: string[]): string {
  const r = spawnSync("osascript", ["-", ...args], { input: script, encoding: "utf8" });
  if (r.status !== 0) {
    process.stderr.write(r.stderr ?? "osascript failed\n");
    process.exit(r.status ?? 1);
  }
  return (r.stdout ?? "").replace(/\n$/, "");
}

function die(msg: string): never {
  process.stderr.write(`${msg}\n`);
  process.exit(2);
}

function main(): void {
  const argv = process.argv.slice(2);
  const cmd = argv[0] ?? "";
  let title = "";
  let idx = 1;
  if (["new", "get", "sticky"].includes(cmd)) {
    title = argv[1] ?? "";
    idx = 2;
  }
  let folder = FOLDER_DEFAULT;
  let session = process.env.CLAUDE_SESSION_ID ?? "";
  let project = spawnSync("basename", [process.cwd()], { encoding: "utf8" }).stdout.trim();
  let bodyOnlyFlag = false;
  for (let i = idx; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--session") session = argv[++i] ?? "";
    else if (a === "--project") project = argv[++i] ?? "";
    else if (a === "--folder") folder = argv[++i] ?? "";
    else if (a === "--body-only") bodyOnlyFlag = true;
  }

  switch (cmd) {
    case "new": {
      if (!title) die("usage: draft-hold.ts new <title>  (body on stdin)");
      const raw = readFileSync(0, "utf8");
      const body = buildNoteBody(title, raw, session, project);
      console.log(osascript(OSA_NEW, [folder, title, body]));
      break;
    }
    case "get": {
      if (!title) die("usage: draft-hold.ts get <title> [--body-only]");
      const full = htmlToText(osascript(OSA_GET, [folder, title]));
      console.log(bodyOnlyFlag ? bodyOnly(full) : collapseBlanks(full));
      break;
    }
    case "list": {
      console.log(osascript(OSA_LIST, [folder]));
      break;
    }
    case "sticky": {
      if (!title) die("usage: draft-hold.ts sticky <title>");
      const plain = `Draft (edit in Notes -> ${folder} -> ${title})\n\n${htmlToText(osascript(OSA_GET, [folder, title]))}`;
      spawnSync("pbcopy", [], { input: plain });
      const gui = `tell application "Stickies" to activate
delay 0.6
tell application "System Events" to tell process "Stickies"
  keystroke "n" using command down
  delay 0.4
  keystroke "v" using command down
end tell`;
      const r = spawnSync("osascript", ["-"], { input: gui, encoding: "utf8" });
      if (r.status !== 0) {
        console.log("Stickies mirror failed (grant Accessibility). Notes copy is authoritative.");
      } else {
        console.log(`Mirrored to Stickies (view-only). Edit the real draft in Notes -> ${folder} -> ${title}.`);
      }
      break;
    }
    default:
      die("usage: draft-hold.ts {new <title>|get <title>|list|sticky <title>} [--session UUID] [--project NAME] [--folder NAME]");
  }
}

// Only run the CLI when executed directly (bun draft-hold.ts …), not when imported by tests.
if (import.meta.main) main();
