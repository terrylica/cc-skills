#!/usr/bin/env bun
/**
 * draft-hold.ts — Bun/TypeScript engine for the draft-hold skill (notes-commander plugin).
 *
 * Migrated from the standalone draft-hold plugin (2026-07-18) onto the shared notes-core
 * engine, gaining its hardening:
 *   • SILENT-FAILURE DETECTION — `new` asserts Notes returned a real note id
 *     (x-coredata://…); on macOS 26 osascript can exit 0 yet create nothing.
 *   • BOUNDED RETRY — transient AppleEvent errors (-600/-1712/"not running") retry with
 *     backoff via runOsa; permission/syntax errors fail fast.
 *   • READ-BACK VERIFY — after `new`, the note is read back and checked for entity leaks
 *     (`&quot` without semicolon) and content presence. `--no-verify` skips.
 *   • The prose-reflow formatter (bodyToHtml) lives in notes-core and is unit-tested there:
 *     prose reflows (blank line = paragraph), lists stay per-item, ``` fences verbatim.
 *
 * Commands (unchanged surface):
 *   draft-hold.ts new "<title>" [--session UUID] [--project NAME] [--folder NAME] [--no-verify]
 *   draft-hold.ts get "<title>" [--folder NAME] [--body-only]
 *   draft-hold.ts list [--folder NAME]
 *   draft-hold.ts sticky "<title>" [--folder NAME]
 */
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import {
  bodyToHtml,
  collapseBlanks,
  contentPresent,
  entityLeaks,
  escapeHtml,
  FOLDER_DEFAULT,
  htmlToText,
  isNoteId,
  runOsaOrDie,
} from "./lib/notes-core.ts";

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
  let verify = true;
  for (let i = idx; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--session") session = argv[++i] ?? "";
    else if (a === "--project") project = argv[++i] ?? "";
    else if (a === "--folder") folder = argv[++i] ?? "";
    else if (a === "--body-only") bodyOnlyFlag = true;
    else if (a === "--no-verify") verify = false;
  }

  switch (cmd) {
    case "new": {
      if (!title) die("usage: draft-hold.ts new <title>  (body on stdin)");
      const raw = readFileSync(0, "utf8");
      const body = buildNoteBody(title, raw, session, project);
      const id = runOsaOrDie(OSA_NEW, [folder, title, body]);
      if (!isNoteId(id))
        die(
          `✗ SILENT-FAILURE: Notes returned no note id (got: "${id}"). The draft was NOT saved — open Notes once and re-grant Automation permission, then retry.`,
        );
      if (verify) {
        const back = htmlToText(runOsaOrDie(OSA_GET, [folder, title]));
        const leaks = entityLeaks(back);
        if (leaks.length)
          die(`✗ ENTITY-LEAK on read-back (${leaks.join(", ")}): the draft saved but decoding drifted — do not trust get output until fixed.`);
        if (!contentPresent(raw, back))
          die("✗ CONTENT-MISMATCH: the saved note does not contain the drafted text. Check the note in Notes before trusting it.");
      }
      console.log(id);
      break;
    }
    case "get": {
      if (!title) die("usage: draft-hold.ts get <title> [--body-only]");
      const full = htmlToText(runOsaOrDie(OSA_GET, [folder, title]));
      console.log(bodyOnlyFlag ? bodyOnly(full) : collapseBlanks(full));
      break;
    }
    case "list": {
      console.log(runOsaOrDie(OSA_LIST, [folder]));
      break;
    }
    case "sticky": {
      if (!title) die("usage: draft-hold.ts sticky <title>");
      const plain = `Draft (edit in Notes -> ${folder} -> ${title})\n\n${htmlToText(runOsaOrDie(OSA_GET, [folder, title]))}`;
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
      die(
        "usage: draft-hold.ts {new <title>|get <title>|list|sticky <title>} [--session UUID] [--project NAME] [--folder NAME] [--no-verify]",
      );
  }
}

// Only run the CLI when executed directly (bun draft-hold.ts …), not when imported by tests.
if (import.meta.main) main();
