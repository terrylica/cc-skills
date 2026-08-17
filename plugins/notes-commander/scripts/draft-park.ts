#!/usr/bin/env bun
/**
 * draft-park.ts — Bun/TypeScript engine for the draft-park skill (notes-commander plugin).
 *
 * Migrated from the standalone draft-hold plugin (2026-07-18) onto the shared notes-core
 * engine, gaining its hardening (skill + engine renamed draft-hold → draft-park 2026-08-12):
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
 *   draft-park.ts new "<title>" [--session UUID] [--project NAME] [--folder NAME] [--no-verify]
 *   draft-park.ts get "<title>" [--folder NAME] [--body-only]
 *   draft-park.ts list [--folder NAME]
 *   draft-park.ts sticky "<title>" [--folder NAME]
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
	matchNoteIds,
	parseRecords,
	runOsa,
	runOsaOrDie,
} from "./lib/notes-core.ts";

function nowStamp(): string {
	const r = spawnSync("date", ["+%Y-%m-%d %H:%M %Z"], { encoding: "utf8" });
	return (r.stdout ?? "").trim();
}

/**
 * The separator and the first words of the footer line. `bodyOnly()` matches on BOTH, so a lone
 * dash-rule in the author's prose is no longer mistaken for the start of the footer.
 */
export const FOOTER_SEPARATOR_RE = /^------\s*$/;
export const FOOTER_LEAD = "Parked by Claude Code";

function footerHtml(session: string, project: string): string {
	const sess = session ? `session ${escapeHtml(session)} | ` : "";
	return `<div><br></div><div><tt>------</tt></div><div><tt>${FOOTER_LEAD} | ${sess}${escapeHtml(project)} | ${nowStamp()}</tt></div>`;
}

export function buildNoteBody(
	title: string,
	body: string,
	session: string,
	project: string,
): string {
	const titleHtml = `<div><b>${escapeHtml(title)}</b></div><div><br></div>`;
	return titleHtml + bodyToHtml(body) + footerHtml(session, project);
}

/**
 * Where the provenance footer begins, or -1 when the note carries none.
 *
 * ── WHY THIS IS NOT "THE FIRST LINE OF DASHES" ───────────────────────────────────────────────────
 *
 * It used to be, and on 2026-08-17 that truncated a real client message to a real client. The author
 * used a six-dash line as a visual divider mid-message; `bodyOnly` stopped there and returned 1,760 of
 * 4,635 characters. Nothing warned anyone — the Notes UI showed the whole message, and the sendable
 * text is only ever inspected by the human who is about to paste it.
 *
 * The severity is not the typo, it is WHOSE TEXT CAN TRIGGER IT. Drafts routinely quote third-party
 * content verbatim — client review comments, patient transcripts, Drive comments. So a dash rule
 * written by someone outside this machine could silently cut an outbound message at a point they
 * chose. That makes it an injection, not a formatting bug.
 *
 * TWO SIGNALS, NOT ONE. The footer is `------` followed by a line starting `Parked by Claude Code`.
 * Requiring both means prose dashes are ignored, and searching from the END means a quoted copy of a
 * footer earlier in the body cannot pull the cut point upwards either.
 */
export function findFooterStart(lines: string[]): number {
	for (let i = lines.length - 1; i >= 0; i--) {
		if (!FOOTER_SEPARATOR_RE.test(lines[i] ?? "")) continue;
		// The footer line is the next non-blank after the rule. Anything else is the author's own rule.
		for (let j = i + 1; j < lines.length; j++) {
			const next = (lines[j] ?? "").trim();
			if (next === "") continue;
			return next.startsWith(FOOTER_LEAD) ? i : -1;
		}
		// A trailing rule with nothing after it is prose, not a footer.
		return -1;
	}
	return -1;
}

export function bodyOnly(full: string): string {
	const lines = full.split("\n");
	const footerAt = findFooterStart(lines);
	const body = footerAt === -1 ? lines : lines.slice(0, footerAt);
	const out: string[] = [];
	let state: "pre" | "title" | "body" = "pre";
	for (const line of body) {
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
	// Trailing blank lines are an artefact of cutting the footer off, never authored content.
	while (out.length > 0 && (out.at(-1) ?? "").trim() === "") out.pop();
	return out.join("\n");
}

// ── CHANNEL RENDERING ────────────────────────────────────────────────────────────────────────────
//
// A parked draft is written in markdown, and every channel it gets pasted into speaks something else.
// On 2026-08-17 a message to a client reviewer arrived with TWENTY literal `**` in it, because
// WhatsApp bold is a SINGLE asterisk. She read a wall of punctuation and asked whether she was even
// looking at the right thing.
//
// The intervention is deliberately CONVERT-AND-WARN rather than refuse. Refusing to park a draft
// containing a heading would make the tool obstructive for the email and iMessage cases, which have
// different rules again; converting silently would hide from the author that their `[label](url)` no
// longer exists as a link. So: rewrite what maps cleanly, and say on stderr what did not — stdout
// stays exactly the sendable text so `--copy` and shell pipelines are unaffected.

export interface ChannelRenderResult {
  text: string;
  warnings: string[];
}

/**
 * Markdown → WhatsApp. WhatsApp understands `*bold*`, `_italic_`, `~strike~` and ```` ``` ```` blocks,
 * and nothing else — it has no headings, no inline code, and no link syntax at all.
 */
export function renderForWhatsApp(markdown: string): ChannelRenderResult {
  const warnings: string[] = [];
  const lines = markdown.split("\n");
  let inFence = false;
  const out = lines.map((line) => {
    if (/^\s*```/.test(line)) {
      inFence = !inFence;
      return line;
    }
    // Inside a fence the text is verbatim by contract — rewriting it would corrupt the very thing the
    // author fenced to protect.
    if (inFence) return line;

    let l = line;
    // `**bold**` → `*bold*`. Done before any single-asterisk handling so the pair is consumed first.
    if (l.includes("**")) l = l.replace(/\*\*(.+?)\*\*/g, "*$1*");
    // A markdown heading has no WhatsApp equivalent; bold is the closest honest rendering.
    const heading = /^(#{1,6})\s+(.*)$/.exec(l);
    if (heading) l = `*${heading[2]}*`;
    // `[label](url)` — WhatsApp would show the literal brackets and the URL would not be clickable,
    // so the URL is promoted to visible text. Losing it silently is the failure worth preventing.
    if (/\[[^\]]*\]\([^)]*\)/.test(l)) {
      l = l.replace(/\[([^\]]*)\]\(([^)]*)\)/g, (_m, label: string, url: string) => (label.trim() === "" ? url : `${label}: ${url}`));
      warnings.push("markdown links were flattened to 'label: url' — WhatsApp has no link syntax");
    }
    if (/`[^`]+`/.test(l)) warnings.push("inline `code` has no WhatsApp equivalent; the backticks will show literally");
    if (/^\s*\|.*\|\s*$/.test(l)) warnings.push("a markdown TABLE will render as raw pipes in WhatsApp");
    return l;
  });
  return { text: out.join("\n"), warnings: [...new Set(warnings)] };
}

export const CHANNEL_RENDERERS: Record<string, (s: string) => ChannelRenderResult> = {
  whatsapp: renderForWhatsApp,
  // `plain` strips nothing and warns about nothing — the explicit "I know what I am doing" choice, so
  // that omitting --for is not silently equivalent to asserting the channel is markdown-aware.
  plain: (s: string) => ({ text: s, warnings: [] }),
};

/**
 * Refuse to hand over text still carrying the provenance footer.
 *
 * The footer reached a client group on 2026-08-17 because the human copied the note out of the Notes
 * UI, where `Parked by Claude Code | session <uuid> | <repo>` is just more selectable text. This is the
 * backstop for that: any path that produces sendable text asserts the footer is gone, so a future
 * change to the stripping logic cannot quietly start leaking it again.
 */
/**
 * Markdown links whose URL provably cannot reach the recipient.
 *
 * ── THE MEASUREMENT ──────────────────────────────────────────────────────────────────────────────
 *
 * Parking `Please review [the rules portal](https://…/rules-portal-…/) today.` and reading it back
 * with --body-only returns, verbatim: `Please review the rules portal today.` The URL is GONE — not
 * mangled, absent. `renderInline` turns the markdown into a real `<a href>` (Notes genuinely stores
 * the href, confirmed in the 2026-08-05 evolution log against NoteStore.sqlite), but AppleScript's
 * body GETTER returns `<u>label</u>` with no href. The markdown is consumed on the way in and the URL
 * is dropped on the way out.
 *
 * ── WHY THIS IS A REFUSAL AND NOT A WARNING ──────────────────────────────────────────────────────
 *
 * The Notes UI shows a working, clickable link, so the author has every reason to believe the message
 * is fine. The recipient gets an instruction to go and look at something, with nothing to click. This
 * tool exists to stage text a human will SEND; a message that silently loses the thing it is asking
 * someone to open is not a formatting nit.
 *
 * It is caught at `new`, because by `get` the URL no longer exists to recover. The fix for the author
 * is one keystroke — write the URL inline — so refusing costs nothing and removes the failure mode
 * rather than announcing it. `--allow-lossy-links` keeps the door open for a note meant to be READ in
 * Notes rather than sent.
 */
export function findLossyMarkdownLinks(body: string): { label: string; url: string }[] {
  const found: { label: string; url: string }[] = [];
  let inFence = false;
  for (const line of body.split("\n")) {
    if (/^\s*```/.test(line)) {
      inFence = !inFence;
      continue;
    }
    // A fenced link is literal text by contract and is never turned into an anchor, so its URL
    // survives read-back intact. Flagging it would be a false positive.
    if (inFence) continue;
    for (const m of line.matchAll(/\[([^\]]*)\]\((https?:\/\/[^)]+|mailto:[^)]+)\)/g)) {
      found.push({ label: m[1] ?? "", url: m[2] ?? "" });
    }
  }
  return found;
}

export class ProvenanceLeakError extends Error {}

export function assertNoProvenanceLeak(sendable: string): void {
  if (sendable.includes(FOOTER_LEAD)) {
    // THROWS rather than calling die(). A guard that exits the process is a guard no test can assert
    // on in both directions, which is the exact failure class this hardening pass exists to remove.
    // The CLI catches it and dies there, so the operator-facing behaviour is unchanged.
    throw new ProvenanceLeakError(
      `the sendable text still contains "${FOOTER_LEAD}" — that is internal provenance and must never reach a recipient`,
    );
  }
}

// ---- AppleScript payloads ----
// Create-only: make the note and return its id. Dedup of any older same-title note now happens in TS
// (folderNoteIndex + noteNameMatchesTitle) so it is TRUNCATION-TOLERANT — a long title whose derived
// NAME Notes stored truncated-with-ellipsis is still matched. The new note is created FIRST, so a
// transient failure can never orphan the draft; the old copy is removed only after the new one exists.
const OSA_NEW = `on run {folderName, bodyHTML}
  tell application "Notes"
    if not (exists folder folderName) then make new folder with properties {name:folderName}
    set n to make new note at folder folderName with properties {body:bodyHTML}
    return id of n
  end tell
end run`;

// Read a note's body by its stable id — truncation of the derived NAME cannot affect an id lookup.
const OSA_GET_BY_ID = `on run {noteId}
  tell application "Notes"
    if not (exists note id noteId) then return "(no such draft)"
    return body of note id noteId
  end tell
end run`;

// Delete a note by id (best-effort self-heal of an older duplicate).
const OSA_DELETE_BY_ID = `on run {noteId}
  tell application "Notes"
    if (exists note id noteId) then delete note id noteId
  end tell
end run`;

// (id, name) index of a folder's notes — FS (U+0001) between fields, RS (U+0002) after each note — so
// title->id resolution (exact, else truncation-tolerant) happens in JS via parseRecords + noteNameMatchesTitle.
const OSA_FOLDER_NOTE_INDEX = `on run {folderName}
  tell application "Notes"
    if not (exists folder folderName) then return ""
    set out to ""
    repeat with n in notes of folder folderName
      set out to out & (id of n) & (ASCII character 1) & (name of n) & (ASCII character 2)
    end repeat
    return out
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

/** All (id, name) pairs for a folder's notes (empty if the folder is missing). */
function folderNoteIndex(folder: string): Array<{ id: string; name: string }> {
	return parseRecords(runOsaOrDie(OSA_FOLDER_NOTE_INDEX, [folder])).map(
		([id, name]) => ({
			id: id ?? "",
			name: name ?? "",
		}),
	);
}

/** Resolve a title to a note id within a folder (exact-then-truncation-tolerant; first match). */
function resolveNoteIdInFolder(folder: string, title: string): string | null {
	return matchNoteIds(folderNoteIndex(folder), title)[0] ?? null;
}

/** Body HTML of the note whose (possibly truncated) name matches `title`, or the sentinel if none. */
function getBodyByTitle(folder: string, title: string): string {
	const id = resolveNoteIdInFolder(folder, title);
	return id ? runOsaOrDie(OSA_GET_BY_ID, [id]) : "(no such draft)";
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
	let project = spawnSync("basename", [process.cwd()], {
		encoding: "utf8",
	}).stdout.trim();
	let bodyOnlyFlag = false;
	let verify = true;
	let channel = "";
	let copyToClipboard = false;
	let allowLossyLinks = false;
	for (let i = idx; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--session") session = argv[++i] ?? "";
		else if (a === "--project") project = argv[++i] ?? "";
		else if (a === "--folder") folder = argv[++i] ?? "";
		else if (a === "--body-only") bodyOnlyFlag = true;
		else if (a === "--for") channel = argv[++i] ?? "";
		else if (a === "--copy") copyToClipboard = true;
		else if (a === "--allow-lossy-links") allowLossyLinks = true;
		else if (a === "--no-verify") verify = false;
	}

	switch (cmd) {
		case "new": {
			if (!title) die("usage: draft-park.ts new <title>  (body on stdin)");
			const raw = readFileSync(0, "utf8");
			const lossy = findLossyMarkdownLinks(raw);
			if (lossy.length > 0 && !allowLossyLinks) {
				die(
					`✗ REFUSING: ${lossy.length} markdown link(s) whose URL CANNOT survive read-back.\n` +
						lossy.map((l) => `    [${l.label}](${l.url})`).join("\n") +
						`\n\n  Notes stores the href but its AppleScript getter strips it, so \`get --body-only\` would\n` +
						`  return "${lossy[0]?.label}" with no URL — and the Notes UI would still show a working link,\n` +
						`  so nothing would look wrong. Write the URL inline instead:\n` +
						`    ${lossy[0]?.label}: ${lossy[0]?.url}\n` +
						`  Or pass --allow-lossy-links if this note is meant to be READ in Notes, not sent.`,
				);
			}
			const body = buildNoteBody(title, raw, session, project);
			const id = runOsaOrDie(OSA_NEW, [folder, body]);
			if (!isNoteId(id))
				die(
					`✗ SILENT-FAILURE: Notes returned no note id (got: "${id}"). The draft was NOT saved — open Notes once and re-grant Automation permission, then retry.`,
				);
			if (verify) {
				// Read back BY ID (not by title): macOS truncates a long note's derived NAME, so a title
				// lookup would spuriously miss it and report a false CONTENT-MISMATCH.
				const back = htmlToText(runOsaOrDie(OSA_GET_BY_ID, [id]));
				const leaks = entityLeaks(back);
				if (leaks.length)
					die(
						`✗ ENTITY-LEAK on read-back (${leaks.join(", ")}): the draft saved but decoding drifted — do not trust get output until fixed.`,
					);
				// `--allow-lossy-links` is an explicit statement that the author accepts the link text not
				// round-tripping, so the content check must not then fail for that very reason. It is
				// relaxed only for that flag, and said out loud — a silently skipped verify is how the
				// original defect stayed hidden.
				if (allowLossyLinks) console.error("⚠ content-presence check relaxed: --allow-lossy-links was passed, so the read-back is expected to differ");
				else if (!contentPresent(raw, back))
					die(
						"✗ CONTENT-MISMATCH: the saved note does not contain the drafted text. Check the note in Notes before trusting it.",
					);
			}
			// Self-heal: remove any OLDER note in this folder sharing the (possibly truncated) title.
			for (const otherId of matchNoteIds(folderNoteIndex(folder), title)) {
				if (otherId !== id) runOsa(OSA_DELETE_BY_ID, [otherId]);
			}
			console.log(id);
			break;
		}
		case "get": {
			if (!title) die("usage: draft-park.ts get <title> [--body-only] [--for whatsapp|plain] [--copy]");
			const full = htmlToText(getBodyByTitle(folder, title));
			// --for and --copy both imply the SENDABLE text: rendering the title heading and the
			// provenance footer for a channel, or onto the clipboard, is never what anyone wants.
			const wantsSendable = bodyOnlyFlag || channel !== "" || copyToClipboard;
			let text = wantsSendable ? bodyOnly(full) : collapseBlanks(full);
			if (channel !== "") {
				const render = CHANNEL_RENDERERS[channel];
				if (!render) die(`✗ unknown --for channel '${channel}'; known: ${Object.keys(CHANNEL_RENDERERS).join(", ")}`);
				const rendered = render(text);
				text = rendered.text;
				// stderr, so stdout stays exactly the sendable bytes for piping and --copy.
				for (const w of rendered.warnings) console.error(`⚠ ${w}`);
			}
			if (wantsSendable) {
				try {
					assertNoProvenanceLeak(text);
				} catch (e) {
					die(`✗ REFUSING: ${(e as Error).message}`);
				}
			}
			if (copyToClipboard) {
				// Removes the hand-copy step that leaked the footer into a client group. Announced on
				// stderr rather than done quietly: the clipboard is global state, and silently replacing
				// whatever the human had copied is its own small betrayal.
				const p = spawnSync("pbcopy", { input: text });
				if (p.status !== 0) die("✗ pbcopy failed — the text was NOT copied; paste manually from the printed output");
				console.error(`✓ ${text.length} chars copied to the clipboard — your previous clipboard contents were replaced`);
			}
			console.log(text);
			break;
		}
		case "list": {
			console.log(runOsaOrDie(OSA_LIST, [folder]));
			break;
		}
		case "sticky": {
			if (!title) die("usage: draft-park.ts sticky <title>");
			const plain = `Draft (edit in Notes -> ${folder} -> ${title})\n\n${htmlToText(getBodyByTitle(folder, title))}`;
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
				console.log(
					"Stickies mirror failed (grant Accessibility). Notes copy is authoritative.",
				);
			} else {
				console.log(
					`Mirrored to Stickies (view-only). Edit the real draft in Notes -> ${folder} -> ${title}.`,
				);
			}
			break;
		}
		default:
			die(
				"usage: draft-park.ts {new <title>|get <title>|list|sticky <title>} [--session UUID] [--project NAME] [--folder NAME] [--no-verify]",
			);
	}
}

// Only run the CLI when executed directly (bun draft-park.ts …), not when imported by tests.
if (import.meta.main) main();
