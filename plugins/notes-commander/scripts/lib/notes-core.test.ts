/**
 * notes-core.test.ts — unit tests for the PURE parts of the shared Notes engine.
 * Run: bun test  (from this directory or repo root)
 *
 * Locks in: the formatter guarantee (hard-wrapped prose can never become a permanent
 * mid-sentence break; fences verbatim), plus the hardening helpers (silent-failure id
 * check, transient-error classification, entity-leak detection, read-back presence,
 * record-stream parsing, filename sanitizing).
 */
import { expect, test } from "bun:test";
import {
	bodyToHtml,
	contentPresent,
	entityLeaks,
	escapeHtml,
	FS,
	isNoteId,
	isTransientOsaError,
	matchNoteIds,
	NOTES_NAME_ELLIPSIS,
	noteNameMatchesTitle,
	parseRecords,
	RS,
	safeFilename,
	terminateLegacyEntities,
} from "./notes-core.ts";

// ── formatter (migrated from draft-hold, byte-identical behavior) ────────────

test("escapeHtml encodes the four HTML-significant characters", () => {
	expect(escapeHtml('a & b < c > d "e"')).toBe(
		"a &amp; b &lt; c &gt; d &quot;e&quot;",
	);
});

// ── truncation-tolerant note-name matching (macOS truncates long names with U+2026) ──

test("noteNameMatchesTitle: exact stored name matches its title", () => {
	expect(noteNameMatchesTitle("Short note", "Short note")).toBe(true);
});

test("noteNameMatchesTitle: a name truncated with a trailing ellipsis matches the full title", () => {
	const title =
		"CPC Scanners — Procurement Intelligence & Deliverables (2026-07-20)";
	const stored = `CPC Scanners — Procurement Intelligence & Deliverables (2026-07-20${NOTES_NAME_ELLIPSIS}`;
	expect(noteNameMatchesTitle(stored, title)).toBe(true);
});

test("noteNameMatchesTitle: a truncated name does NOT match a different title", () => {
	const stored = `Weekly report — north region sales and margin bre${NOTES_NAME_ELLIPSIS}`;
	expect(noteNameMatchesTitle(stored, "Completely unrelated title")).toBe(
		false,
	);
});

test("noteNameMatchesTitle: a bare ellipsis (no prefix) never matches", () => {
	expect(noteNameMatchesTitle(NOTES_NAME_ELLIPSIS, "anything")).toBe(false);
});

test("noteNameMatchesTitle: a non-truncated name that merely differs does not match", () => {
	expect(noteNameMatchesTitle("Draft A", "Draft B")).toBe(false);
});

// ── matchNoteIds: the single home for title→note-id resolution (draft-hold + move-note) ──

test("matchNoteIds: exact name resolves to its id", () => {
	const index = [
		{ id: "p1", name: "Alpha" },
		{ id: "p2", name: "Beta" },
	];
	expect(matchNoteIds(index, "Beta")).toEqual(["p2"]);
});

test("matchNoteIds: an exact match is preferred over a truncated collision", () => {
	// A short note literally named "Report" AND a long note truncated to "Report…" both exist;
	// the exact one must win so a title never accidentally resolves to a longer note.
	const index = [
		{ id: "pShort", name: "Report" },
		{ id: "pLong", name: `Report${NOTES_NAME_ELLIPSIS}` },
	];
	expect(matchNoteIds(index, "Report")).toEqual(["pShort"]);
});

test("matchNoteIds: falls back to a truncated match when no exact name matches", () => {
	const title =
		"CPC Scanners — Procurement Intelligence & Deliverables (2026-07-20)";
	const index = [
		{ id: "pX", name: "Unrelated" },
		{ id: "pHit", name: `CPC Scanners — Procurement Intelligence${NOTES_NAME_ELLIPSIS}` },
	];
	expect(matchNoteIds(index, title)).toEqual(["pHit"]);
});

test("matchNoteIds: no match yields an empty array", () => {
	expect(matchNoteIds([{ id: "p1", name: "Alpha" }], "Zeta")).toEqual([]);
	expect(matchNoteIds([], "anything")).toEqual([]);
});

test("matchNoteIds: duplicate exact titles surface every id (ambiguity for the caller)", () => {
	const index = [
		{ id: "p1", name: "Done" },
		{ id: "p2", name: "Done" },
	];
	expect(matchNoteIds(index, "Done")).toEqual(["p1", "p2"]);
});

test("hard-wrapped prose reflows into ONE paragraph (the core guarantee)", () => {
	const html = bodyToHtml(
		"This is a long sentence\nthat was hard wrapped\nat a fixed column width.",
	);
	expect(html).toContain(
		"<div>This is a long sentence that was hard wrapped at a fixed column width.</div>",
	);
	expect((html.match(/<div>This is a long/g) ?? []).length).toBe(1);
	expect(html).not.toContain("<div>that was hard wrapped</div>");
});

test("a blank line starts a new paragraph", () => {
	const html = bodyToHtml("Paragraph one.\n\nParagraph two.");
	expect(html).toContain("<div>Paragraph one.</div>");
	expect(html).toContain("<div>Paragraph two.</div>");
});

test("list markers each get their own line; a wrapped continuation joins its item", () => {
	const html = bodyToHtml(
		"- first item\n- second item that is\n  wrapped onto two lines\n- third item",
	);
	expect(html).toContain("<div>- first item</div>");
	expect(html).toContain(
		"<div>- second item that is wrapped onto two lines</div>",
	);
	expect(html).toContain("<div>- third item</div>");
});

test("numbered and lettered list markers are recognized", () => {
	const html = bodyToHtml("1. alpha\n2) beta\na. gamma");
	expect(html).toContain("<div>1. alpha</div>");
	expect(html).toContain("<div>2) beta</div>");
	expect(html).toContain("<div>a. gamma</div>");
});

test("``` fenced block preserves each line verbatim in monospace with aligned columns", () => {
	const html = bodyToHtml(
		"Intro line.\n\n```\nID    AMOUNT\n255   26,170.00\n```\n\nAfter.",
	);
	expect(html).toContain(
		"<div><tt>ID&nbsp;&nbsp;&nbsp;&nbsp;AMOUNT</tt></div>",
	);
	expect(html).toContain("<div><tt>255&nbsp;&nbsp;&nbsp;26,170.00</tt></div>");
	expect(html).not.toContain("```");
	expect(html).toContain("<div>Intro line.</div>");
	expect(html).toContain("<div>After.</div>");
});

test("entities inside prose and fences are escaped", () => {
	expect(bodyToHtml("Ben & Jerry's <tag>")).toContain(
		"Ben &amp; Jerry's &lt;tag&gt;",
	);
	expect(bodyToHtml("```\n<x> & y\n```")).toContain(
		"<div><tt>&lt;x&gt;&nbsp;&amp;&nbsp;y</tt></div>",
	);
});

test("hard-wrapped CJK reflows with NO stray space at the fold", () => {
	const html = bodyToHtml("关于本次电汇诈骗\n的取证结论如下。");
	expect(html).toContain("<div>关于本次电汇诈骗的取证结论如下。</div>");
});

test("mixed CJK↔Latin fold keeps a single space (conventional)", () => {
	const html = bodyToHtml("金额为\nUSD 26,170");
	expect(html).toContain("<div>金额为 USD 26,170</div>");
});

test("empty fence line renders a non-collapsing monospace row", () => {
	const html = bodyToHtml("```\na\n\nb\n```");
	expect(html).toContain("<div><tt>&nbsp;</tt></div>");
});

// ── hardening helpers ────────────────────────────────────────────────────────

test("isNoteId accepts a real Notes core-data id and rejects silent-failure outputs", () => {
	expect(isNoteId("x-coredata://ABC-123/ICNote/p2748")).toBe(true);
	expect(isNoteId("  x-coredata://ABC/ICNote/p1\n")).toBe(true);
	expect(isNoteId("")).toBe(false);
	expect(isNoteId("missing value")).toBe(false);
	expect(isNoteId("execution error: Notes got an error (-1712)")).toBe(false);
});

test("isTransientOsaError matches retry-worthy AppleEvent failures only", () => {
	expect(
		isTransientOsaError(
			"execution error: Notes got an error: AppleEvent timed out. (-1712)",
		),
	).toBe(true);
	expect(
		isTransientOsaError("execution error: application isn’t running. (-600)"),
	).toBe(true);
	expect(isTransientOsaError("connection is invalid (-609)")).toBe(true);
	// NOT transient: permission + syntax errors — retrying can never fix these
	expect(
		isTransientOsaError(
			"execution error: Not authorized to send Apple events to Notes. (-1743)",
		),
	).toBe(false);
	expect(
		isTransientOsaError("syntax error: Expected end of line (-2741)"),
	).toBe(false);
	expect(isTransientOsaError("")).toBe(false);
});

test("entityLeaks flags semicolon-less legacy entities, not well-formed ones", () => {
	expect(entityLeaks("he said &quot hello &quot")).toEqual(["&quot"]);
	expect(entityLeaks("a &amp b &lt c")).toEqual(["&amp", "&lt"]);
	// properly terminated or word-boundary → clean
	expect(entityLeaks("a &amp; b &quot; c")).toEqual([]);
	expect(entityLeaks("the &amplifier works")).toEqual([]);
	expect(entityLeaks("no entities at all")).toEqual([]);
});

test("contentPresent tolerates reflow and CJK joins but catches missing content", () => {
	expect(
		contentPresent(
			"Hello world this is a draft",
			"Hello world this is a draft and footer",
		),
	).toBe(true);
	// reflowed with different whitespace → still present
	expect(
		contentPresent(
			"Hello world\nthis is a draft",
			"Hello   world this\nis a draft",
		),
	).toBe(true);
	// CJK reflow (no spaces) → still present
	expect(
		contentPresent(
			"关于本次电汇诈骗\n的取证结论",
			"关于本次电汇诈骗的取证结论如下",
		),
	).toBe(true);
	// truncated/empty read-back → caught
	expect(contentPresent("Hello world this is a draft", "")).toBe(false);
	expect(contentPresent("Hello world this is a draft", "(no such draft)")).toBe(
		false,
	);
	// empty input asserts nothing
	expect(contentPresent("", "anything")).toBe(true);
	// fence-only input asserts nothing (fences may legitimately transform)
	expect(contentPresent("```\ncol1  col2\n```", "whatever")).toBe(true);
});

test("parseRecords splits FS/RS streams and drops empty records", () => {
	const raw =
		["F", "iCloud", "Notes", "141"].join(FS) +
		RS +
		["F", "iCloud", "To-Do / Done", "11"].join(FS);
	expect(parseRecords(raw)).toEqual([
		["F", "iCloud", "Notes", "141"],
		["F", "iCloud", "To-Do / Done", "11"],
	]);
	expect(parseRecords("")).toEqual([]);
	expect(parseRecords(RS)).toEqual([]);
});

test("safeFilename strips path-hostile characters and bounds length", () => {
	expect(safeFilename('a/b\\c:d*e?f"g<h>i|j', "x")).toBe("a_b_c_d_e_f_g_h_i_j");
	expect(safeFilename("", "fallback")).toBe("fallback");
	expect(safeFilename("正常中文名", "x")).toBe("正常中文名");
	expect(safeFilename("x".repeat(300), "f").length).toBeLessThanOrEqual(120);
});

// Regression: a note storing `Write-Host "x"; $y` comes back from Notes raw as
// `Write-Host &quotx&quot; $y`. Without terminating the bare entities first,
// textutil consumes the author's `;` as the closing `&quot;` and the semicolon
// vanishes — silently corrupting any staged PowerShell/C/Java/JS. Verified live
// against macOS Notes 2026-07-20.
test("terminateLegacyEntities preserves an author semicolon that follows a quote", () => {
	expect(terminateLegacyEntities("Write-Host &quotx&quot; $y.Remove()")).toBe(
		"Write-Host &quot;x&quot;; $y.Remove()",
	);
});

test("terminateLegacyEntities terminates bare entities so a parser decodes them", () => {
	expect(terminateLegacyEntities("a &amp b &lt c &gt d")).toBe(
		"a &amp; b &lt; c &gt; d",
	);
	expect(terminateLegacyEntities("&quot")).toBe("&quot;");
});

test("terminateLegacyEntities does not rescan its own replacements", () => {
	// A literal `&amp;` typed by the author is stored by Notes as `&ampamp;`
	// (Notes escapes the `&`). One substitution must yield `&amp;amp;`, which a
	// parser decodes back to the literal `&amp;` — not a runaway rewrite.
	expect(terminateLegacyEntities("&ampampquot")).toBe("&amp;ampquot");
	expect(terminateLegacyEntities("the &amplifier works")).toBe(
		"the &amp;lifier works",
	);
});

test("terminateLegacyEntities leaves entity-free text untouched", () => {
	expect(terminateLegacyEntities("plain; text with no entities")).toBe(
		"plain; text with no entities",
	);
});
