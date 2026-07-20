/**
 * notes-core.ts — shared engine for the notes-commander plugin.
 *
 * One home for everything that talks to macOS Notes via AppleScript, so every skill
 * (draft-hold, inventory, export, organize, doctor) inherits the same hardening:
 *   • runOsa() — osascript with BOUNDED RETRY on transient AppleEvent errors
 *     (-600/-609/-1712 "app not running"/"timed out"), which recent macOS throws
 *     intermittently. Permission/syntax errors are NOT retried (retry can't fix them).
 *   • isNoteId() — detect the macOS 26 silent no-op (osascript exits 0, creates nothing).
 *   • entityLeaks()/contentPresent() — read-back integrity checks for the documented
 *     Notes quirks (semicolon-less `&quot` entities; textutil charset mojibake).
 *   • bodyToHtml() — the unit-tested prose-reflow formatter (fences verbatim, lists
 *     per-item, CJK-aware joins) that draft-hold pioneered.
 *
 * Everything exported here that doesn't spawn a process is PURE and unit-tested in
 * notes-core.test.ts. AppleScript payloads live in the consumers (notes.ts, draft-hold.ts).
 */
import { spawnSync } from "node:child_process";

export const FOLDER_DEFAULT = "Claude Drafts";
/** Path segment separator for nested folders, e.g. "To-Do / Done". */
export const PATH_SEP = " / ";

// ── pure helpers ─────────────────────────────────────────────────────────────

export function escapeHtml(s: string): string {
	return s
		.replaceAll("&", "&amp;")
		.replaceAll("<", "&lt;")
		.replaceAll(">", "&gt;")
		.replaceAll('"', "&quot;");
}

/**
 * A Notes note id looks like `x-coredata://<store-uuid>/ICNote/p123`. Creation asserts the
 * returned value is one of these — on macOS 26 `osascript` can exit 0 yet not create the note
 * (a silent AppleEvent no-op), returning "" / "missing value" / an error string instead.
 */
export function isNoteId(s: string): boolean {
	return /^x-coredata:\/\/\S+/.test(s.trim());
}

/**
 * True when osascript stderr describes a TRANSIENT AppleEvent condition worth a bounded retry
 * (Notes not up yet, connection invalid, event timed out) — NOT a real script/permission error
 * (syntax, or -1743 "Not authorized", which retrying can never fix).
 */
export function isTransientOsaError(stderr: string): boolean {
	return /\(-600\)|\(-609\)|\(-1712\)|isn.t running|not running|timed out/i.test(
		stderr,
	);
}

/**
 * Semicolon-less legacy HTML entities Notes' `body` getter can leak back (e.g. `&quot` for `"`).
 * If any survive read-back, the textutil decode path drifted — this plugin's documented #1
 * failure. Returns the distinct leaked tokens (properly-terminated `&amp;` and word-boundary
 * cases like `&amplifier` are NOT flagged).
 */
export function entityLeaks(text: string): string[] {
	const m = text.match(/&(?:quot|amp|lt|gt|nbsp)(?![;A-Za-z])/g);
	return m ? [...new Set(m)] : [];
}

const stripWs = (s: string): string => s.replace(/\s+/g, "");

/**
 * Does the read-back plausibly still contain the drafted text? Whitespace-insensitive substring
 * check on the first chunk of visible content — tolerant of reflow/soft-wrapping and CJK (which
 * reflow joins without spaces), so it flags a truncated/empty/mangled save WITHOUT
 * false-positiving on legitimate reflow. An empty/whitespace-only body asserts nothing.
 */
export function contentPresent(inputBody: string, readback: string): boolean {
	let inFence = false;
	let firstLine = "";
	for (const raw of inputBody.split("\n")) {
		const l = raw.trim();
		if (l.startsWith("```")) {
			inFence = !inFence;
			continue;
		}
		if (!inFence && l) {
			firstLine = l;
			break;
		}
	}
	if (!firstLine) return true; // only fenced/blank content — assert nothing
	const needle = stripWs(firstLine).slice(0, 24);
	return needle ? stripWs(readback).includes(needle) : true;
}

/**
 * macOS Notes derives a note's `name` from its first line but TRUNCATES a long first line, storing a
 * name that ends with this ellipsis (U+2026) and is NOT equal to the intended title. Exact
 * `whose name is <title>` / `note <title> of folder` lookups therefore MISS long-titled notes — a real
 * failure hit 2026-07-20: a 66-char draft-hold title stored as `…(2026-07-20…`, so the read-back verify
 * (false CONTENT-MISMATCH) and `move-note` (false "note not found") both failed on a note that existed.
 */
export const NOTES_NAME_ELLIPSIS = "…";

/**
 * Truncation-tolerant match of a stored Notes `name` against an intended title: exact match, OR the
 * stored name is the title truncated with a trailing ellipsis (its leading text is a prefix of the
 * title). Exact should be preferred by callers; this only needs to be true for a legitimate match.
 */
export function noteNameMatchesTitle(
	storedName: string,
	title: string,
): boolean {
	if (storedName === title) return true;
	if (storedName.endsWith(NOTES_NAME_ELLIPSIS)) {
		const prefix = storedName.slice(0, -NOTES_NAME_ELLIPSIS.length);
		return prefix.length > 0 && title.startsWith(prefix);
	}
	return false;
}

// ── the Notes-HTML formatter (prose reflows; lists per-item; fences verbatim) ─

// A list item: optional indent, then a bullet (-, *, +, •, ·) or "1." / "1)" / "a." / "a)",
// then a space + content.
const LIST_RE = /^\s*([-*+•·]|\d+[.)]|[A-Za-z][.)])\s+\S/;

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
		(c >= 0x2e80 && c <= 0x9fff) || // CJK radicals … Unified Ideographs (incl. kana)
		(c >= 0xa960 && c <= 0xa97f) || // Hangul Jamo Extended-A
		(c >= 0xac00 && c <= 0xd7ff) || // Hangul syllables
		(c >= 0xf900 && c <= 0xfaff) || // CJK compatibility ideographs
		(c >= 0xff00 && c <= 0xffef) // halfwidth/fullwidth forms
	);
}

/**
 * Join hard-wrapped lines back into one logical line. A single space is inserted at each fold
 * EXCEPT where both sides are CJK wide characters (CJK doesn't space words), so a pre-wrapped
 * Chinese paragraph reflows seamlessly.
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
			for (const it of items)
				html.push(`<div>${escapeHtml(reflowJoin(it))}</div>`);
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
		const encoded = escapeHtml(l)
			.replaceAll("\t", "    ")
			.replaceAll(" ", "&nbsp;");
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
		out.push(
			...(b.kind === "fence"
				? renderFenceBlock(b.lines)
				: renderTextBlock(b.lines)),
		);
	}
	return out.join("");
}

// ── process wrappers (thin, hardened) ────────────────────────────────────────

export interface OsaResult {
	ok: boolean;
	stdout: string;
	stderr: string;
	attempts: number;
}

/**
 * Run an AppleScript via `osascript -` with args, retrying TRANSIENT AppleEvent failures with a
 * short backoff (Notes cold-launch, -600/-1712 races on recent macOS). Non-transient failures
 * return immediately — retrying a permission or syntax error only wastes time.
 */
export function runOsa(
	script: string,
	args: string[],
	maxAttempts = 3,
): OsaResult {
	let last: OsaResult = {
		ok: false,
		stdout: "",
		stderr: "osascript did not run",
		attempts: 0,
	};
	for (let attempt = 1; attempt <= maxAttempts; attempt++) {
		const r = spawnSync("osascript", ["-", ...args], {
			input: script,
			encoding: "utf8",
		});
		last = {
			ok: r.status === 0,
			stdout: (r.stdout ?? "").replace(/\n$/, ""),
			stderr: r.stderr ?? "",
			attempts: attempt,
		};
		if (last.ok) return last;
		if (!isTransientOsaError(last.stderr)) return last;
		if (attempt < maxAttempts) Bun.sleepSync(attempt * 400);
	}
	return last;
}

/** runOsa or die: print stderr and exit non-zero (CLI convenience). */
export function runOsaOrDie(
	script: string,
	args: string[],
	maxAttempts = 3,
): string {
	const r = runOsa(script, args, maxAttempts);
	if (!r.ok) {
		process.stderr.write(r.stderr || "osascript failed\n");
		process.exit(1);
	}
	return r.stdout;
}

/**
 * Terminate Notes' semicolon-less legacy entities BEFORE handing HTML to a real
 * parser, so an author's literal `;` is not swallowed as an entity terminator.
 *
 * Notes' AppleScript `body` getter emits the semicolon-LESS form (`&quot`, `&amp`,
 * `&lt`, …) — verified 2026-06-29, and again 2026-07-20 where a note storing
 * `Write-Host "x"; $y` came back raw as `Write-Host &quotx&quot; $y`. That is
 * ambiguous to any real HTML parser: textutil reads the closing `&quot` plus the
 * author's `;` as ONE entity and silently drops the semicolon, so the text
 * round-trips as `Write-Host "x" $y`. Any staged code containing `";` — most
 * PowerShell, C, Java, JavaScript — is corrupted with no error and no warning,
 * which is fatal for this plugin's whole purpose (staging text a human will SEND).
 *
 * Appending `;` to every bare entity is unconditionally correct here, because
 * Notes escapes every `&` it stores: a literal `&amp;` typed by the author comes
 * back as `&ampamp;`, never as `&amp;`. So a terminated entity in Notes output can
 * only ever be bare-entity + the author's own semicolon.
 *
 * The `/g` replace scans the SOURCE left-to-right and never rescans what it just
 * wrote, so `&ampquot` → `&amp;quot` (one substitution), not a runaway.
 */
export function terminateLegacyEntities(bodyHtml: string): string {
	return bodyHtml.replace(/&(quot|amp|lt|gt|apos|nbsp)/g, "&$1;");
}

/** Decode Notes body HTML to plain text with a real HTML parser (never sed). */
export function htmlToText(bodyHtml: string): string {
	// textutil misreads UTF-8 as Latin-1 without a charset declaration → prepend one.
	const r = spawnSync(
		"textutil",
		["-stdin", "-stdout", "-convert", "txt", "-format", "html"],
		{
			input: `<meta charset="utf-8">${terminateLegacyEntities(bodyHtml)}`,
			encoding: "utf8",
		},
	);
	return r.stdout ?? "";
}

/** Collapse runs of blank lines to single blanks (read-back cosmetics). */
export function collapseBlanks(s: string): string {
	const out: string[] = [];
	let prevNonEmpty = true;
	for (const l of s.split("\n")) {
		const nonEmpty = l.trim() !== "";
		if (nonEmpty || prevNonEmpty) out.push(l);
		prevNonEmpty = nonEmpty;
	}
	return out.join("\n");
}

// ── record-stream parsing (inventory/export AppleScript output) ──────────────

/** Field separator (U+0001) and record separator (U+0002) used by the AppleScript payloads. */
export const FS = "\u0001";
export const RS = "\u0002";

/** Split an FS/RS-delimited osascript payload into records of fields. Pure. */
export function parseRecords(raw: string): string[][] {
	if (!raw) return [];
	return raw
		.split(RS)
		.filter((rec) => rec.length > 0)
		.map((rec) => rec.split(FS));
}

/** Make a note/folder name safe as a filename (export). Pure. */
export function safeFilename(name: string, fallback: string): string {
	const cleaned = name
		.replace(/[/\\:*?"<>|]/g, "_")
		.trim()
		.slice(0, 120);
	return cleaned || fallback;
}
