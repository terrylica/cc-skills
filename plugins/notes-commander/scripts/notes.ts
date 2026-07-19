#!/usr/bin/env bun
/**
 * notes.ts — the notes-commander organizer CLI (macOS Notes via AppleScript).
 *
 * Read + export wiring for the whole Notes tree (all accounts), plus the reorganization
 * primitives (folderize) — so sporadic folders/tags can be reshaped deliberately, with
 * everything exported to local storage first.
 *
 *   notes.ts inventory [--json]                      # accounts → folder tree with note counts
 *   notes.ts export [--out DIR]                      # full snapshot → markdown + manifest.json
 *   notes.ts mkdir "<name>" [--account A] [--parent "Path / To / Folder"]
 *   notes.ts move-note "<title>" --from "Path" --to "Path" [--account A] [--id NOTEID] [--dry-run]
 *   notes.ts rename-folder "Path" --to "<new name>" [--account A]
 *   notes.ts merge-folder "SrcPath" --into "DstPath" [--account A] [--dry-run]
 *   notes.ts doctor                                  # end-to-end create→read→verify→delete round-trip
 *
 * Folder PATHS use " / " between segments (e.g. "To-Do / Done") because folder NAMES are not
 * unique (this account has two "Done" folders). All writes route through resolveFolder, which
 * walks the path segment-by-segment from the account root — never by bare name.
 *
 * Default export root: ~/.local/share/notes-commander/export/<stamp>/ (XDG-style, outside any
 * git repo, so note content can never be accidentally committed).
 */
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  collapseBlanks,
  contentPresent,
  entityLeaks,
  htmlToText,
  isNoteId,
  parseRecords,
  PATH_SEP,
  runOsaOrDie,
  safeFilename,
} from "./lib/notes-core.ts";

const EXPORT_ROOT = join(homedir(), ".local", "share", "notes-commander", "export");

// ── AppleScript payloads ─────────────────────────────────────────────────────
// All payloads emit FS/RS-delimited records (U+0001 fields, U+0002 records) because
// AppleScript has no JSON. Records are typed by their first field: "F" folder, "N" note.
// `folders of <account>` returns EVERY folder FLATTENED (nested included) — a documented Notes
// quirk — so top-level detection filters on `class of (container of f) is account`, and
// recursion uses `folders of <folder>` (direct children only).

const OSA_COMMON = `
on fs()
  return character id 1
end fs
on rs()
  return character id 2
end rs
on pad2(n)
  set t to n as string
  if length of t < 2 then set t to "0" & t
  return t
end pad2
on isoDate(d)
  if d is missing value then return ""
  return (year of d as string) & "-" & my pad2(month of d as integer) & "-" & my pad2(day of d) & " " & my pad2(hours of d) & ":" & my pad2(minutes of d) & ":" & my pad2(seconds of d)
end isoDate
on resolveFolder(acctName, pathStr)
  set AppleScript's text item delimiters to " / "
  set segs to text items of pathStr
  set AppleScript's text item delimiters to ""
  tell application "Notes"
    set a to account acctName
    set cur to missing value
    repeat with i from 1 to count of segs
      set seg to item i of segs
      if cur is missing value then
        set cands to (every folder of a whose name is seg)
        set found to missing value
        repeat with c in cands
          if class of (container of c) is account then
            set found to c
            exit repeat
          end if
        end repeat
        if found is missing value then error "folder not found at account root: " & seg
        set cur to found
      else
        set cands to (every folder of cur whose name is seg)
        if (count of cands) is 0 then error "subfolder not found: " & seg & " (under " & (name of cur) & ")"
        set cur to item 1 of cands
      end if
    end repeat
    return cur
  end tell
end resolveFolder
`;

const OSA_INVENTORY = `${OSA_COMMON}
global OUTREC
on walkFolder(f, acct, parentPath)
  global OUTREC
  tell application "Notes"
    set fName to name of f
    set cnt to count of notes of f
    set subs to every folder of f
  end tell
  set p to parentPath & fName
  set end of OUTREC to "F" & my fs() & acct & my fs() & p & my fs() & (cnt as string)
  repeat with sf in subs
    my walkFolder(sf, acct, p & " / ")
  end repeat
end walkFolder
on run
  set OUTREC to {}
  tell application "Notes"
    set accts to every account
  end tell
  repeat with a in accts
    tell application "Notes"
      set aName to name of a
      set allFolders to every folder of a
    end tell
    repeat with f in allFolders
      tell application "Notes"
        set isTop to (class of (container of f) is account)
      end tell
      if isTop then my walkFolder(f, aName, "")
    end repeat
  end repeat
  set AppleScript's text item delimiters to my rs()
  set outText to OUTREC as string
  set AppleScript's text item delimiters to ""
  return outText
end run`;

// Export writes its record stream to a TEMP FILE (arg 1) instead of returning it: a whole
// library's bodies in one Apple Event return blows the AE size cap (-1741 observed live).
// Each folder's fetch is wrapped in `try` so one unreadable folder (e.g. trash residue)
// degrades to an "E" record instead of killing the run. "Recently Deleted" is skipped
// in-script — deleted notes' bodies can be inaccessible AND shouldn't be backed up anyway.
const OSA_EXPORT = `${OSA_COMMON}
global OUTREC
on walkFolder(f, acct, parentPath)
  global OUTREC
  tell application "Notes"
    set fName to name of f
    set subs to every folder of f
  end tell
  set p to parentPath & fName
  tell application "Notes"
    set cnt to count of notes of f
  end tell
  set end of OUTREC to "F" & my fs() & acct & my fs() & p & my fs() & (cnt as string)
  -- Fetch in CHUNKS of 20: one Apple Event reply carrying a whole big folder's bodies blows
  -- the AE size cap (-1741, observed live at 141 notes). A failed chunk degrades to per-note
  -- fetches; a note that still fails becomes an "E" record instead of killing the export.
  repeat with s from 1 to cnt by 20
    set e to s + 19
    if e > cnt then set e to cnt
    try
      tell application "Notes"
        set ids to id of notes s thru e of f
        set nms to name of notes s thru e of f
        set mds to modification date of notes s thru e of f
        set bds to body of notes s thru e of f
      end tell
      repeat with i from 1 to count of ids
        set end of OUTREC to "N" & my fs() & acct & my fs() & p & my fs() & (item i of ids) & my fs() & (item i of nms) & my fs() & my isoDate(item i of mds) & my fs() & (item i of bds)
      end repeat
    on error
      repeat with j from s to e
        try
          tell application "Notes"
            set n to note j of f
            set end of OUTREC to "N" & my fs() & acct & my fs() & p & my fs() & (id of n) & my fs() & (name of n) & my fs() & my isoDate(modification date of n) & my fs() & (body of n)
          end tell
        on error errMsg
          set end of OUTREC to "E" & my fs() & acct & my fs() & p & my fs() & "note " & (j as string) & ": " & errMsg
        end try
      end repeat
    end try
  end repeat
  repeat with sf in subs
    my walkFolder(sf, acct, p & " / ")
  end repeat
end walkFolder
on run {outPath}
  set OUTREC to {}
  tell application "Notes"
    set accts to every account
  end tell
  repeat with a in accts
    tell application "Notes"
      set aName to name of a
      set allFolders to every folder of a
    end tell
    repeat with f in allFolders
      tell application "Notes"
        set isTop to (class of (container of f) is account)
        set topName to name of f
      end tell
      if isTop and topName is not "Recently Deleted" then my walkFolder(f, aName, "")
    end repeat
  end repeat
  set AppleScript's text item delimiters to my rs()
  set outText to OUTREC as string
  set AppleScript's text item delimiters to ""
  set fRef to open for access POSIX file outPath with write permission
  try
    set eof fRef to 0
    write outText to fRef as «class utf8»
    close access fRef
  on error errMsg
    close access fRef
    error errMsg
  end try
  return "ok"
end run`;

const OSA_MKDIR = `${OSA_COMMON}
on run {acctName, parentPath, newName}
  tell application "Notes"
    if parentPath is "" then
      set a to account acctName
      make new folder at a with properties {name:newName}
    else
      set parentF to my resolveFolder(acctName, parentPath)
      make new folder at parentF with properties {name:newName}
    end if
  end tell
  return "ok"
end run`;

const OSA_MOVE = `${OSA_COMMON}
on run {acctName, fromPath, toPath, titleOrId, byId}
  set src to my resolveFolder(acctName, fromPath)
  set dst to my resolveFolder(acctName, toPath)
  tell application "Notes"
    if byId is "yes" then
      set matches to (every note of src whose id is titleOrId)
    else
      set matches to (every note of src whose name is titleOrId)
    end if
    if (count of matches) is 0 then error "note not found in source folder: " & titleOrId
    if (count of matches) > 1 then
      set idList to ""
      repeat with m in matches
        set idList to idList & (id of m) & linefeed
      end repeat
      error "AMBIGUOUS: " & (count of matches) & " notes share that title. Re-run with --id one of:" & linefeed & idList
    end if
    move (item 1 of matches) to dst
  end tell
  return "ok"
end run`;

const OSA_RENAME = `${OSA_COMMON}
on run {acctName, folderPath, newName}
  set f to my resolveFolder(acctName, folderPath)
  tell application "Notes"
    set name of f to newName
  end tell
  return "ok"
end run`;

const OSA_MERGE = `${OSA_COMMON}
on run {acctName, srcPath, dstPath}
  set src to my resolveFolder(acctName, srcPath)
  set dst to my resolveFolder(acctName, dstPath)
  tell application "Notes"
    set moved to 0
    repeat while (count of notes of src) > 0
      move (item 1 of (notes of src)) to dst
      set moved to moved + 1
    end repeat
    set leftFolders to count of folders of src
  end tell
  return (moved as string) & " moved; " & (leftFolders as string) & " subfolders remain in source (not touched)"
end run`;

const OSA_DOCTOR_NEW = `on run {folderName, noteTitle, bodyHTML}
  tell application "Notes"
    if not (exists folder folderName) then make new folder with properties {name:folderName}
    set n to make new note at folder folderName with properties {body:bodyHTML}
    return id of n
  end tell
end run`;

const OSA_DOCTOR_GET_DELETE = `on run {noteId}
  tell application "Notes"
    set n to note id noteId
    set b to body of n
    delete n
    return b
  end tell
end run`;

// ── verbs ────────────────────────────────────────────────────────────────────

interface Flags {
  positional: string[];
  opts: Record<string, string | boolean>;
}

function parseArgs(argv: string[]): Flags {
  const positional: string[] = [];
  const opts: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith("--")) {
        opts[key] = next;
        i++;
      } else {
        opts[key] = true;
      }
    } else {
      positional.push(a);
    }
  }
  return { positional, opts };
}

function die(msg: string): never {
  process.stderr.write(`${msg}\n`);
  process.exit(2);
}

interface FolderRow {
  account: string;
  path: string;
  count: number;
}

function fetchInventory(): FolderRow[] {
  const raw = runOsaOrDie(OSA_INVENTORY, []);
  return parseRecords(raw)
    .filter((r) => r[0] === "F")
    .map((r) => ({ account: r[1], path: r[2], count: Number(r[3]) }));
}

/** Notes DOES expose the trash as a folder (verified live 2026-07-18). English-UI name. */
const TRASH_FOLDER = "Recently Deleted";
const isTrash = (path: string): boolean => path === TRASH_FOLDER || path.startsWith(TRASH_FOLDER + PATH_SEP);

function cmdInventory(flags: Flags): void {
  const rows = fetchInventory();
  if (flags.opts.json) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }
  let account = "";
  let total = 0;
  let trashed = 0;
  for (const r of rows) {
    if (r.account !== account) {
      account = r.account;
      console.log(`\n${account}`);
    }
    const depth = r.path.split(PATH_SEP).length - 1;
    const name = r.path.split(PATH_SEP).at(-1) ?? r.path;
    console.log(`${"  ".repeat(depth + 1)}${name}  (${r.count})`);
    if (isTrash(r.path)) trashed += r.count;
    else total += r.count;
  }
  console.log(
    `\n${rows.length} folders, ${total} live notes (direct counts)${trashed ? ` + ${trashed} in ${TRASH_FOLDER}` : ""}`,
  );
}

function cmdExport(flags: Flags): void {
  const stamp = new Date()
    .toISOString()
    .replace(/[:T]/g, "-")
    .replace(/\..+/, "");
  const outDir = typeof flags.opts.out === "string" ? flags.opts.out : join(EXPORT_ROOT, stamp);
  mkdirSync(outDir, { recursive: true });

  console.log("Reading every account/folder/note from Notes (one AppleScript pass)…");
  const tmp = join(outDir, ".export-stream.tmp");
  runOsaOrDie(OSA_EXPORT, [tmp], 2);
  const records = parseRecords(readFileSync(tmp, "utf8"));
  rmSync(tmp, { force: true });

  interface ManifestNote {
    account: string;
    folder: string;
    id: string;
    name: string;
    modified: string;
    file: string;
    chars: number;
  }
  const manifest: { exportedAt: string; folders: FolderRow[]; notes: ManifestNote[] } = {
    exportedAt: new Date().toISOString(),
    folders: [],
    notes: [],
  };

  const folderErrors: string[] = [];
  for (const r of records) {
    if (isTrash(r[2] ?? "")) continue; // belt-and-braces: the AppleScript already skips trash
    if (r[0] === "E") {
      folderErrors.push(`${r[2]}: ${r[3]}`);
      continue;
    }
    if (r[0] === "F") {
      manifest.folders.push({ account: r[1], path: r[2], count: Number(r[3]) });
      continue;
    }
    if (r[0] !== "N") continue;
    const [, account, folderPath, id, name, modified, bodyHtml] = r;
    const dir = join(outDir, safeFilename(account, "account"), ...folderPath.split(PATH_SEP).map((s, i) => safeFilename(s, `folder-${i}`)));
    mkdirSync(dir, { recursive: true });
    const idSuffix = id.split("/").at(-1) ?? "p0";
    const file = join(dir, `${safeFilename(name, "untitled")}.${idSuffix}.md`);
    const text = collapseBlanks(htmlToText(bodyHtml ?? ""));
    const front = `---\naccount: ${account}\nfolder: ${folderPath}\nid: ${id}\nmodified: ${modified}\n---\n\n`;
    writeFileSync(file, front + text);
    manifest.notes.push({
      account,
      folder: folderPath,
      id,
      name,
      modified,
      file: file.slice(outDir.length + 1),
      chars: text.length,
    });
  }

  writeFileSync(join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2));
  console.log(`✓ exported ${manifest.notes.length} notes across ${manifest.folders.length} folders`);
  console.log(`  snapshot: ${outDir}`);
  console.log(`  manifest: ${join(outDir, "manifest.json")}`);
  for (const e of folderErrors) console.log(`  ⚠ folder skipped (unreadable): ${e}`);
  if (folderErrors.length) process.exitCode = 3; // partial export — loud, not silent
}

function requireAccount(flags: Flags): string {
  const a = flags.opts.account;
  if (typeof a === "string" && a) return a;
  return "iCloud";
}

function cmdMkdir(flags: Flags): void {
  const name = flags.positional[0];
  if (!name) die('usage: notes.ts mkdir "<name>" [--account A] [--parent "Path / To / Folder"]');
  const parent = typeof flags.opts.parent === "string" ? flags.opts.parent : "";
  runOsaOrDie(OSA_MKDIR, [requireAccount(flags), parent, name]);
  console.log(`✓ created folder "${name}"${parent ? ` under "${parent}"` : " at account root"}`);
}

function cmdMoveNote(flags: Flags): void {
  const title = flags.positional[0];
  const from = flags.opts.from;
  const to = flags.opts.to;
  if (!title || typeof from !== "string" || typeof to !== "string")
    die('usage: notes.ts move-note "<title>" --from "Path" --to "Path" [--account A] [--id NOTEID] [--dry-run]');
  const byId = typeof flags.opts.id === "string";
  const needle = byId ? (flags.opts.id as string) : title;
  if (flags.opts["dry-run"]) {
    console.log(`DRY-RUN: would move ${byId ? `note id ${needle}` : `"${title}"`} from "${from}" to "${to}"`);
    return;
  }
  runOsaOrDie(OSA_MOVE, [requireAccount(flags), from, to, needle, byId ? "yes" : "no"]);
  console.log(`✓ moved ${byId ? `note id ${needle}` : `"${title}"`}: "${from}" → "${to}"`);
}

function cmdRenameFolder(flags: Flags): void {
  const path = flags.positional[0];
  const to = flags.opts.to;
  if (!path || typeof to !== "string")
    die('usage: notes.ts rename-folder "Path / To / Folder" --to "<new name>" [--account A]');
  runOsaOrDie(OSA_RENAME, [requireAccount(flags), path, to]);
  console.log(`✓ renamed "${path}" → "${to}"`);
}

function cmdMergeFolder(flags: Flags): void {
  const src = flags.positional[0];
  const into = flags.opts.into;
  if (!src || typeof into !== "string")
    die('usage: notes.ts merge-folder "SrcPath" --into "DstPath" [--account A] [--dry-run]');
  if (flags.opts["dry-run"]) {
    const rows = fetchInventory();
    const s = rows.find((r) => r.path === src);
    console.log(
      `DRY-RUN: would move ${s ? s.count : "?"} notes from "${src}" into "${into}". Source folder is NOT deleted (delete it manually in Notes once verified empty).`,
    );
    return;
  }
  const result = runOsaOrDie(OSA_MERGE, [requireAccount(flags), src, into]);
  console.log(`✓ merge "${src}" → "${into}": ${result}`);
  console.log("  (source folder left in place — delete it in Notes once you confirm it's empty)");
}

function cmdDoctor(): void {
  const folder = "Claude Drafts";
  const title = `notes-commander doctor ${Date.now()}`;
  const probe = 'Doctor probe — "quotes" & <angles> and 中文往返 must round-trip.';
  const html = `<div><b>${title}</b></div><div><br></div><div>${probe.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;")}</div>`;

  console.log("1/3 create — making a probe note…");
  const id = runOsaOrDie(OSA_DOCTOR_NEW, [folder, title, html]);
  if (!isNoteId(id)) die(`✗ SILENT-FAILURE: Notes returned no note id (got: "${id}"). The macOS 26 osascript no-op — Notes may need to be opened once, or Automation permission re-granted.`);
  console.log(`    ✓ note created (${id.slice(0, 60)}…)`);

  console.log("2/3 read-back — fetching + deleting the probe…");
  const bodyHtml = runOsaOrDie(OSA_DOCTOR_GET_DELETE, [id]);
  const text = htmlToText(bodyHtml);
  const leaks = entityLeaks(text);
  if (leaks.length) die(`✗ ENTITY-LEAK: read-back contains raw ${leaks.join(", ")} — the textutil decode path drifted.`);
  if (!contentPresent(probe, text)) die("✗ CONTENT-MISMATCH: read-back does not contain the probe text — encoding or save path broken.");
  console.log("    ✓ round-trip intact (quotes, angles, CJK, entities all clean)");

  console.log("3/3 inventory — counting folders…");
  const rows = fetchInventory();
  console.log(`    ✓ ${rows.length} folders visible across ${new Set(rows.map((r) => r.account)).size} account(s)`);
  console.log("\ndoctor: ALL CHECKS PASSED");
}

function printHelp(): void {
  console.log(`notes-commander — macOS Notes organizer (AppleScript engine)

  inventory [--json]                        list accounts → folders with note counts
  export [--out DIR]                        snapshot ALL notes → markdown + manifest.json
                                            (default: ~/.local/share/notes-commander/export/<stamp>/)
  mkdir "<name>" [--parent "Path"]          create a folder (at account root, or nested)
  move-note "<title>" --from "P" --to "P"   move one note between folders ([--id NOTEID] to disambiguate)
  rename-folder "Path" --to "<name>"        rename a folder
  merge-folder "Src" --into "Dst"           move every note out of Src into Dst (Src kept, emptied)
  doctor                                    create→read→verify→delete round-trip health check

  Common flags: --account A (default iCloud) · --dry-run (move-note, merge-folder)
  Folder paths use " / " between segments, e.g. "To-Do / Done".`);
}

function main(): void {
  const [cmd, ...rest] = process.argv.slice(2);
  const flags = parseArgs(rest);
  switch (cmd) {
    case "inventory":
      cmdInventory(flags);
      break;
    case "export":
      cmdExport(flags);
      break;
    case "mkdir":
      cmdMkdir(flags);
      break;
    case "move-note":
      cmdMoveNote(flags);
      break;
    case "rename-folder":
      cmdRenameFolder(flags);
      break;
    case "merge-folder":
      cmdMergeFolder(flags);
      break;
    case "doctor":
      cmdDoctor();
      break;
    default:
      printHelp();
      if (cmd && cmd !== "help" && cmd !== "--help") process.exit(2);
  }
}

if (import.meta.main) main();
