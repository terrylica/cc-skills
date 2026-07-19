/**
 * draft-hold.test.ts — unit tests for the PURE formatter (bodyToHtml / escapeHtml).
 * Run: bun test  (from this directory)
 *
 * These lock in the hardening guarantee: hard-wrapped prose can NEVER become a permanent
 * mid-sentence break, while lists and ``` fenced/columnar blocks are preserved.
 */
import { expect, test } from "bun:test";
import { bodyToHtml, escapeHtml } from "./draft-hold.ts";

test("escapeHtml encodes the four HTML-significant characters", () => {
  expect(escapeHtml('a & b < c > d "e"')).toBe("a &amp; b &lt; c &gt; d &quot;e&quot;");
});

test("hard-wrapped prose reflows into ONE paragraph (the core guarantee)", () => {
  const html = bodyToHtml("This is a long sentence\nthat was hard wrapped\nat a fixed column width.");
  expect(html).toContain("<div>This is a long sentence that was hard wrapped at a fixed column width.</div>");
  // exactly one prose div was produced (no mid-sentence fragments)
  expect((html.match(/<div>This is a long/g) ?? []).length).toBe(1);
  expect(html).not.toContain("<div>that was hard wrapped</div>");
});

test("a blank line starts a new paragraph", () => {
  const html = bodyToHtml("Paragraph one.\n\nParagraph two.");
  expect(html).toContain("<div>Paragraph one.</div>");
  expect(html).toContain("<div>Paragraph two.</div>");
});

test("list markers each get their own line; a wrapped continuation joins its item", () => {
  const html = bodyToHtml("- first item\n- second item that is\n  wrapped onto two lines\n- third item");
  expect(html).toContain("<div>- first item</div>");
  expect(html).toContain("<div>- second item that is wrapped onto two lines</div>");
  expect(html).toContain("<div>- third item</div>");
});

test("numbered and lettered list markers are recognized", () => {
  const html = bodyToHtml("1. alpha\n2) beta\na. gamma");
  expect(html).toContain("<div>1. alpha</div>");
  expect(html).toContain("<div>2) beta</div>");
  expect(html).toContain("<div>a. gamma</div>");
});

test("``` fenced block preserves each line verbatim in monospace with aligned columns", () => {
  const html = bodyToHtml("Intro line.\n\n```\nID    AMOUNT\n255   26,170.00\n```\n\nAfter.");
  // space runs become &nbsp; so the columns actually line up (HTML would otherwise collapse them)
  expect(html).toContain("<div><tt>ID&nbsp;&nbsp;&nbsp;&nbsp;AMOUNT</tt></div>");
  expect(html).toContain("<div><tt>255&nbsp;&nbsp;&nbsp;26,170.00</tt></div>");
  // fence markers themselves are not emitted
  expect(html).not.toContain("```");
  // surrounding prose is still reflowed proportional (no <tt>)
  expect(html).toContain("<div>Intro line.</div>");
  expect(html).toContain("<div>After.</div>");
});

test("entities inside prose and fences are escaped", () => {
  expect(bodyToHtml("Ben & Jerry's <tag>")).toContain("Ben &amp; Jerry's &lt;tag&gt;");
  expect(bodyToHtml("```\n<x> & y\n```")).toContain("<div><tt>&lt;x&gt;&nbsp;&amp;&nbsp;y</tt></div>");
});

test("hard-wrapped CJK reflows with NO stray space at the fold", () => {
  const html = bodyToHtml("关于本次电汇诈骗\n的取证结论如下。");
  // two soft-wrapped Chinese lines rejoin seamlessly (CJK doesn't space words)
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
