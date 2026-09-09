/**
 * notes-core.ts — shared engine for the notes-commander plugin.
 *
 * One home for everything that talks to macOS Notes via AppleScript, so every skill
 * (draft-park, inventory, export, organize, doctor) inherits the same hardening:
 *   • runOsa() — osascript with BOUNDED RETRY on transient AppleEvent errors
 *     (-600/-609/-1712 "app not running"/"timed out"), which recent macOS throws
 *     intermittently. Permission/syntax errors are NOT retried (retry can't fix them).
 *   • isNoteId() — detect the macOS 26 silent no-op (osascript exits 0, creates nothing).
 *   • entityLeaks()/contentPresent() — read-back integrity checks for the documented
 *     Notes quirks (semicolon-less `&quot` entities; textutil charset mojibake).
 *   • bodyToHtml() — the unit-tested prose-reflow formatter (fences verbatim, lists
 *     per-item, CJK-aware joins) that draft-park (then named draft-hold) pioneered.
 *
 * Everything exported here that doesn't spawn a process is PURE and unit-tested in
 * notes-core.test.ts. AppleScript payloads live in the consumers (notes.ts, draft-park.ts).
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
 * Markdown inline link `[label](url)` — the ONLY markup this formatter turns into real HTML.
 *
 * Notes stores a genuine link attribute when the AppleScript `body` SETTER is handed an `<a
 * href>` (verified 2026-08-05 against the NoteStore.sqlite protobuf: the href lands in the
 * attribute run while the visible text run holds only the label). The `body` GETTER, however,
 * strips every anchor down to `<u>label</u>` — so a read-back can confirm the LABEL survived but
 * can NEVER confirm the URL did. Read-back verification is therefore link-blind by construction;
 * do not "fix" it by asserting hrefs appear in the getter output, they never will.
 *
 * Scheme allow-list is deliberate: an unrecognised scheme (`javascript:`, `data:`, a bare path)
 * renders as literal text rather than becoming a live link in a document a human will click.
 */
const INLINE_LINK_RE = /\[([^\]\n]+)\]\((https?:\/\/[^\s()<>"]+|mailto:[^\s()<>"]+)\)/g;

/**
 * Inline emphasis Notes renders as RICH TEXT rather than as literal characters.
 *
 * Apple Notes is a rich-text editor and its `body` SETTER accepts real HTML, so `<b>`/`<i>`/
 * `<tt>` become genuine bold / italic / monospaced runs. Until 2026-09-09 this formatter
 * escaped every markup character instead, so a draft written in the house markdown style
 * arrived studded with literal syntax — measured at **274 stray `**` and 9 literal heading
 * markers in a single weekly report**. There is no reason to make an author hand-strip markup
 * for a target that can render it.
 *
 * `_underscore_` emphasis is the dangerous one and is deliberately boundary-anchored, because
 * technical prose is full of identifiers: a naive rule turns `analytics.model_predictions and
 * nan_policy` into `analytics.model<i>predictions and nan</i>policy`. Requiring a NON-word
 * character before the opening `_` and NO word character after the closing one makes an
 * identifier structurally unable to open or close emphasis. `*star*` is anchored the same way
 * so arithmetic like `2*3*4` survives, and both forms require a non-space next to the marker so
 * a lone `*` in prose is inert.
 */
const CODE_SPAN_RE = /`([^`\n]+)`/g;
const BOLD_RE = /\*\*(?=\S)([^\n]*?\S)\*\*/g;
const STRIKE_RE = /~~(?=\S)([^\n]*?\S)~~/g;
const EM_STAR_RE = /(^|[^\w*])\*(?=\S)([^*\n]*?\S)\*(?!\w)/g;
const EM_UNDERSCORE_RE = /(^|[^\w_])_(?=\S)([^_\n]*?\S)_(?!\w)/g;

/**
 * PURE, TESTED: promote markdown emphasis to Notes rich text. Input MUST already be
 * HTML-escaped — this only ever ADDS tags, so escaping first is what keeps author `<` safe.
 *
 * Code spans are extracted first and reinstated last, so `` `a ** b` `` keeps its asterisks
 * literal. The placeholder uses U+E000 (Private Use Area) — it carries no meaning of its own,
 * cannot appear in real prose, and unlike a control character does not trip the linter.
 */
export function renderMarkup(escaped: string): string {
	const code: string[] = [];
	let s = escaped.replace(CODE_SPAN_RE, (_m, body: string) => {
		code.push(body);
		return `\uE000${code.length - 1}\uE000`;
	});
	s = s
		.replace(BOLD_RE, "<b>$1</b>")
		.replace(STRIKE_RE, "<s>$1</s>")
		.replace(EM_STAR_RE, "$1<i>$2</i>")
		.replace(EM_UNDERSCORE_RE, "$1<i>$2</i>");
	return s.replace(
		/\uE000(\d+)\uE000/g,
		(_m, i: string) => `<tt>${code[Number(i)]}</tt>`,
	);
}

/**
 * ATX heading. The trailing-space requirement is load-bearing: `#600` is an issue reference,
 * not a heading, and weekly reports are full of them.
 */
export const HEADING_RE = /^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$/;

/** PURE, TESTED: escape a line for Notes HTML, promoting `[label](url)` to a real anchor. */
export function renderInline(s: string): string {
	let out = "";
	let last = 0;
	for (const m of s.matchAll(INLINE_LINK_RE)) {
		const at = m.index ?? 0;
		out += renderMarkup(escapeHtml(s.slice(last, at)));
		out += `<a href="${escapeHtml(m[2])}">${renderMarkup(escapeHtml(m[1]))}</a>`;
		last = at + m[0].length;
	}
	return out + renderMarkup(escapeHtml(s.slice(last)));
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
 * Drop the markup CHARACTERS the formatter legitimately consumes, so the read-back check
 * compares like with like.
 *
 * Regression found 2026-09-09 by an end-to-end probe, not by a unit test: once the formatter
 * started rendering `**bold**` as a real bold run, `contentPresent()` was still comparing the
 * RAW input against the read-back, so any draft whose first visible line contained markup
 * failed with `✗ CONTENT-MISMATCH` and exit 2 — the note saved correctly and the tool called
 * it corrupt. It stayed hidden all session because every scrum park passed
 * `--allow-lossy-links`, which relaxes this very check for an unrelated reason. A verifier
 * that has not been run against the thing it verifies is not a verifier.
 */
const stripMarkup = (s: string): string =>
	s
		.replace(/^\s{0,3}#{1,6}\s+/, "")
		.replace(/^\s*([-*+•·]|\d+[.)]|[A-Za-z][.)])\s+/, "")
		.replace(/\*\*|~~|`/g, "")
		.replace(/(^|[^\w*])\*(?=\S)/g, "$1")
		.replace(/(^|[^\w_])_(?=\S)/g, "$1")
		.replace(/\*(?!\w)/g, "")
		.replace(/_(?!\w)/g, "")
		.replace(/\[([^\]\n]+)\]\((?:https?|mailto):[^\s)]+\)/g, "$1");

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
	// Compare against the input with markup consumed: the formatter renders it as styling,
	// so the characters are GONE from the read-back by design, not by corruption.
	const needle = stripWs(stripMarkup(firstLine)).slice(0, 24);
	return needle ? stripWs(readback).includes(needle) : true;
}

/**
 * macOS Notes derives a note's `name` from its first line but TRUNCATES a long first line, storing a
 * name that ends with this ellipsis (U+2026) and is NOT equal to the intended title. Exact
 * `whose name is <title>` / `note <title> of folder` lookups therefore MISS long-titled notes — a real
 * failure hit 2026-07-20: a 66-char draft-park title stored as `…(2026-07-20…`, so the read-back verify
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

/**
 * Ids of the notes in a folder's `(id, name)` index whose stored name resolves to `title`.
 * Prefers EXACT-name matches; only when there are none does it fall back to truncation-tolerant
 * matches (macOS truncates a long name with a trailing ellipsis — see `noteNameMatchesTitle`).
 * Returns `[]` (nothing matched) or, when several notes share the title, every matching id so the
 * caller can decide how to treat the ambiguity.
 *
 * This is the SINGLE home for title→note-id resolution. Both `draft-park` (get/sticky/dedup) and
 * `notes move-note` route through it, so the exact-then-truncated rule can never drift between two
 * hand-maintained copies (it previously lived once here in TS and once inline in AppleScript).
 */
export function matchNoteIds(
	index: ReadonlyArray<{ id: string; name: string }>,
	title: string,
): string[] {
	const exact = index.filter((n) => n.name === title);
	if (exact.length > 0) return exact.map((n) => n.id);
	return index
		.filter((n) => noteNameMatchesTitle(n.name, title))
		.map((n) => n.id);
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
		} else if (HEADING_RE.test(l)) {
			// A heading is its own paragraph even with no blank line around it. Without this it
			// would be reflowJoin()ed into the prose beneath and rendered as one run-on line.
			if (para.length) {
				paras.push(para);
				para = [];
			}
			paras.push([l]);
		} else {
			para.push(l);
		}
	}
	if (para.length) paras.push(para);

	const html: string[] = [];
	for (const p of paras) {
		// A paragraph may be all prose, all list, or a lead-in line IMMEDIATELY followed by
		// list items with no blank line between ("Pick one:\n- a\n- b"). Deciding on p[0]
		// alone classified that last shape as prose and reflowJoin()ed the markers into the
		// lead-in, silently destroying the list — authors then had to know the undocumented
		// "leave a blank line before a list" rule. Split at the FIRST marker instead.
		const heading = p.length === 1 ? HEADING_RE.exec(p[0]) : null;
		if (heading) {
			// Notes has no reliable AppleScript path to its own heading STYLES, but bold is a
			// real rich-text run and reads as a heading. The `#` markers are consumed either
			// way — leaving them visible is the defect this branch exists to prevent.
			html.push(`<div><b>${renderInline(heading[2])}</b></div>`);
			html.push("<div><br></div>");
			continue;
		}

		const firstMarker = p.findIndex((l) => LIST_RE.test(l));
		if (firstMarker > 0) {
			// lead-in prose, then the list
			html.push(`<div>${renderInline(reflowJoin(p.slice(0, firstMarker)))}</div>`);
			html.push(...renderListItems(p.slice(firstMarker)));
		} else if (firstMarker === 0) {
			html.push(...renderListItems(p));
		} else {
			// prose: reflow the whole paragraph into ONE line — Notes wraps it naturally
			html.push(`<div>${renderInline(reflowJoin(p))}</div>`);
		}
		html.push("<div><br></div>");
	}
	return html;
}

/** Leading whitespace of a list line, in 2-space indent units. A tab counts as one unit. */
export function listDepth(line: string): number {
	const lead = /^[ \t]*/.exec(line)?.[0] ?? "";
	return Math.floor(lead.replace(/\t/g, "  ").length / 2);
}

/**
 * Render list lines one <div> per item; a non-marker continuation line reflows into its item.
 *
 * INDENTATION IS PRESERVED (2026-09-09). Before this, every marker line became a flat `<div>`
 * regardless of leading whitespace, so a two-level outline arrived in Notes as one
 * undifferentiated column of `-` lines — reported from a real parked report as "without the
 * indentation, they can't be separated enough". Depth is rendered with `&nbsp;` runs rather
 * than nested `<ul>` deliberately: the author's own marker is kept as visible text (that is
 * the long-standing behaviour every other test pins), and `&nbsp;` is the one indent Notes
 * cannot collapse — an ordinary leading space in HTML is whitespace and disappears.
 */
function renderListItems(lines: string[]): string[] {
	const items: string[][] = [];
	let item: string[] = [];
	for (const l of lines) {
		if (LIST_RE.test(l)) {
			if (item.length) items.push(item);
			item = [l];
		} else {
			item.push(l);
		}
	}
	if (item.length) items.push(item);

	// Depth is taken from the MARKER line only; a continuation line's own indentation is
	// incidental (it is wrapped prose) and must not change where its item sits.
	const base = Math.min(...items.map((it) => listDepth(it[0])));
	const parsed = items.map((it) => {
		const m = BULLET_RE.exec(it[0]);
		return {
			bullet: m !== null,
			depth: listDepth(it[0]) - base,
			html: renderInline(reflowJoin(m ? [m[3], ...it.slice(1)] : it)),
		};
	});

	// A pure BULLET block becomes a real Notes list: <ul>/<li>, marker stripped, so Notes
	// draws its own glyph and indents nested levels natively. Rendering `- ` as literal text
	// inside a <div> (what this did until 2026-09-09) produced neither — the operator's own
	// screenshot showed hyphens where bullets belonged and inline sub-items where indented
	// ones belonged. NUMBERED/LETTERED blocks keep the literal-marker <div> path on purpose:
	// Notes' <ol> renumbers from 1 and would silently rewrite an author's "2)" as "1.".
	if (parsed.every((p) => p.bullet)) return [buildBulletList(parsed, 0, 0)[0]];

	return parsed.map(
		(p) => `<div>${"&nbsp;".repeat(4 * p.depth)}${p.html}</div>`,
	);
}

/** Bullet marker with its indent and content. Kept separate from LIST_RE, which also matches
 *  numbered and lettered markers that must NOT be renumbered by Notes. */
const BULLET_RE = /^([ \t]*)([-*+•·])[ \t]+(.*)$/;

type ListNode = { depth: number; html: string };

/** Build nested <ul> from a flat depth-annotated list. Returns [html, nextIndex]. */
function buildBulletList(
	items: ListNode[],
	start: number,
	depth: number,
): [string, number] {
	let out = "";
	let i = start;
	while (i < items.length && items[i].depth >= depth) {
		if (items[i].depth > depth) {
			const [sub, next] = buildBulletList(items, i, items[i].depth);
			out += sub;
			i = next;
		} else {
			out += `<li>${items[i].html}</li>`;
			i++;
		}
	}
	return [`<ul>${out}</ul>`, i];
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
