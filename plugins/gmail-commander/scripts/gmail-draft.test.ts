// Unit tests for the Gmail draft builder's header encoding.
//
// These exist because of the 2026-07-29 mojibake report: a draft subject containing an em dash
// reached the client's inbox as "Charting update mojibake privacy matter". Until now this file's
// functions could not be imported at all — the script ran its main block at import time and exited
// with a usage error — so the encoder had no test. A script whose functions cannot be imported
// cannot be proven correct.
//
// Run: bun test plugins/gmail-commander/scripts/gmail-draft.test.ts
import { test, expect, describe } from "bun:test";
import { escapeAndLinkify, renderInlineEmphasis, stripInlineEmphasis } from "./gmail-draft.ts";
import { encodeHeaderValueAsRfc2047EncodedWordIfNonAscii } from "./gmail-draft.ts";

/** Decode an RFC 2047 base64 encoded-word sequence back to the original string. */
function decodeRfc2047EncodedWordSequence(encoded: string): string {
  if (!encoded.includes("=?UTF-8?B?")) return encoded;
  const decodedChunks = encoded
    .split(" ")
    .map((word) => Buffer.from(word.replace(/^=\?UTF-8\?B\?/, "").replace(/\?=$/, ""), "base64"));
  return Buffer.concat(decodedChunks).toString("utf8");
}

test("REGRESSION: an em dash subject survives instead of becoming mojibake", () => {
  // The exact subject that shipped broken on 2026-07-29.
  // Use a Unicode escape for the em dash to avoid editor auto-conversion.
  const subject = "Charting update — privacy matter, Mallampati fix, word list, and clarifications on four recordings";
  const encoded = encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(subject);
  expect(encoded).not.toBe(subject); // must actually encode
  expect(decodeRfc2047EncodedWordSequence(encoded)).toBe(subject);
});

test("pure-ASCII headers are left untouched, not needlessly encoded", () => {
  // Encoding everything would make ordinary subjects unreadable in logs and diffs for no benefit.
  const subject = "Charting update - privacy matter";
  expect(encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(subject)).toBe(subject);
});

test("every emitted encoded-word stays within the RFC 2047 75-character limit", () => {
  // A single over-long encoded-word is silently mangled or rejected by strict parsers, which would
  // reproduce the original bug in a harder-to-spot form.
  const longSubject = `${"Charting update — privacy matter ".repeat(6)}end`;
  for (const word of encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(longSubject).split(" ")) {
    expect(word.length).toBeLessThanOrEqual(75);
  }
});

test("a multi-byte character split across two encoded-words still reassembles", () => {
  // Chunking operates on BYTES, so a character can straddle the boundary. Decoders concatenate the
  // decoded bytes of adjacent words before interpreting UTF-8, so this must round-trip exactly.
  for (const subject of [
    "日本語の件名をとても長くしたときの折り返し確認テストです".repeat(3),
    "café ".repeat(30),
    '"curly" — mixed \'quotes\' '.repeat(8),
  ]) {
    const encoded = encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(subject);
    expect(decodeRfc2047EncodedWordSequence(encoded)).toBe(subject);
  }
});

// LAYER 4: MIME round-trip smoke test
//
// Catch encoding errors before they reach Gmail. This test builds a realistic message with a
// non-ASCII Subject, serializes it to MIME format (as buildMime does), then verifies the Subject
// header survives the RFC 2047 encoding -> decoding round-trip. If the encoder breaks, the test
// catches it before ANY draft reaches the API.
//
test("LAYER 4: a MIME message with non-ASCII Subject round-trips correctly", () => {
  // Simulate the exact headers buildMime would create with a non-ASCII subject.
  const testSubject = "Charting update — privacy matter, Mallampati fix";
  const headers: Record<string, string> = {
    From: "Jane Doe <alias@example.com>",
    To: "alex@example.com",
    Subject: testSubject,
  };

  // This is what buildMime does: encode free-text headers.
  const FREE_TEXT_HEADERS_SAFE_TO_ENCODE = new Set(["Subject"]);
  const mimeHeaderBlock = Object.entries(headers)
    .filter(([, v]) => v)
    .map(([k, v]) => {
      const encoded = FREE_TEXT_HEADERS_SAFE_TO_ENCODE.has(k) ? encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(v) : v;
      return `${k}: ${encoded}`;
    })
    .join("\r\n");

  // Extract the Subject header from the MIME block and decode it back.
  const subjectHeaderMatch = mimeHeaderBlock.match(/^Subject: (.+)$/m);
  expect(subjectHeaderMatch).toBeTruthy();
  if (!subjectHeaderMatch?.[1]) throw new Error("Subject header not found");

  const encodedSubject = subjectHeaderMatch[1];
  const decodedSubject = decodeRfc2047EncodedWordSequence(encodedSubject);

  // The round-trip must preserve the original subject exactly.
  expect(decodedSubject).toBe(testSubject);
});

// ── list preservation (regression 2026-07-29) ──
//
// A nine-item question checklist, written one item per line, arrived in a client inbox as a single
// run-on paragraph because every internal newline was unwrapped to a space. Prose MUST unwrap (that
// is the hard-fold immunity this builder exists for) and lists MUST NOT. Both directions asserted.
import { blocksToHtml, blocksToPlainText, splitBodyIntoBlocks } from "./gmail-draft.ts";

test("prose still unwraps — a formatter-wrapped paragraph becomes one line", () => {
  const blocks = splitBodyIntoBlocks("This sentence was\nhard-wrapped by a\nformatter hook.");
  expect(blocks).toEqual([{ kind: "prose", text: "This sentence was hard-wrapped by a formatter hook." }]);
  expect(blocksToPlainText(blocks)).toBe("This sentence was hard-wrapped by a formatter hook.\n");
});

test("REGRESSION: a list keeps one item per line instead of collapsing into a paragraph", () => {
  const blocks = splitBodyIntoBlocks("- Q1 — first\n- Q2 — second\n- Q3 — third");
  expect(blocks).toEqual([{ kind: "list", leadIn: null, items: ["- Q1 — first", "- Q2 — second", "- Q3 — third"] }]);
  expect(blocksToPlainText(blocks)).toBe("- Q1 — first\n- Q2 — second\n- Q3 — third\n");
});

test("a lead-in sentence before a list reflows as prose WITHOUT eating the list", () => {
  // Classifying the block by its first line alone would fold the items into the sentence.
  const blocks = splitBodyIntoBlocks("The options as we\nsee them:\n- (a) wait\n- (b) warn now");
  expect(blocks).toEqual([
    { kind: "list", leadIn: "The options as we see them:", items: ["- (a) wait", "- (b) warn now"] },
  ]);
});

test("a wrapped continuation line rejoins its own item rather than becoming a new one", () => {
  const blocks = splitBodyIntoBlocks("- Q9 — a long question that a formatter\n  wrapped across two lines\n- Q8 — short");
  expect(blocks[0]).toEqual({
    kind: "list",
    leadIn: null,
    items: ["- Q9 — a long question that a formatter wrapped across two lines", "- Q8 — short"],
  });
});

test("ordered and lettered markers count as list items too", () => {
  for (const marker of ["1.", "2)", "a.", "iv."]) {
    const blocks = splitBodyIntoBlocks(`${marker} one\n${marker} two`);
    expect(blocks[0]?.kind).toBe("list");
  }
});

test("prose containing an em-dash aside is NOT mistaken for a list", () => {
  const blocks = splitBodyIntoBlocks("We found — while checking something else — a problem.");
  expect(blocks[0]?.kind).toBe("prose");
});

test("HTML renders a real <ul>, strips the bullet char, and keeps authored numbering", () => {
  const html = blocksToHtml(splitBodyIntoBlocks("Pick one:\n- (a) wait\n- (b) warn"));
  expect(html).toContain("<p>Pick one:</p>");
  expect(html).toContain("<ul>");
  expect(html).toContain("<li>(a) wait</li>"); // leading "- " removed, "(a)" preserved
  expect(html).not.toContain("<li>- (a) wait</li>");
});

test("URLs inside list items are still linkified and text still escaped", () => {
  const html = blocksToHtml(splitBodyIntoBlocks("- see https://example.com/x\n- and <b>not html</b>"));
  expect(html).toContain('<a href="https://example.com/x">https://example.com/x</a>');
  expect(html).toContain("&lt;b&gt;not html&lt;/b&gt;");
});

test("blank lines still separate blocks, and empty input yields nothing", () => {
  expect(splitBodyIntoBlocks("one\n\ntwo")).toHaveLength(2);
  expect(splitBodyIntoBlocks("\n\n   \n")).toHaveLength(0);
});

// ── 2026-07-30: findings from an adversarial audit of this builder ────────────────────────────────
// Context worth keeping: the list and RFC 2047 fixes above already existed and were already correct,
// but they lived ONLY in the installed marketplace clone — nine commits that were never pushed. A
// draft staged by invoking the copy in ~/eon/cc-skills therefore hit both bugs again on 2026-07-30.
// The code was never the whole problem; see docs/draft-integrity-guards.md.

describe("URL parentheses — a reference link must survive its own path", () => {
  test("a paren inside the path stays inside the link", () => {
    const out = escapeAndLinkify("see https://en.wikipedia.org/wiki/Parser_(software) for more");
    expect(out).toContain('href="https://en.wikipedia.org/wiki/Parser_(software)"');
    expect(out).not.toContain("_(software) for");
  });

  test("a paren the PROSE opened is not swallowed by the link", () => {
    // The counter-case that makes the fix non-trivial: same character, opposite meaning.
    const out = escapeAndLinkify("(see https://x.dev/a)");
    expect(out).toContain('href="https://x.dev/a"');
    expect(out).toContain("</a>)");
  });

  test("a full stop after a parenthesised path is prose; the paren is not", () => {
    const out = escapeAndLinkify("https://en.wikipedia.org/wiki/Foo_(bar).");
    expect(out).toContain('href="https://en.wikipedia.org/wiki/Foo_(bar)"');
    expect(out).toContain("</a>.");
  });

  test("a query string with & produces a valid href", () => {
    expect(escapeAndLinkify("https://x.dev/a?p=1&q=2")).toBe('<a href="https://x.dev/a?p=1&amp;q=2">https://x.dev/a?p=1&amp;q=2</a>');
  });

  test("a URL in angle brackets does not absorb the closing bracket", () => {
    // Escape-then-linkify produced href="…&gt" here; the raw-split order is what fixes it.
    const out = escapeAndLinkify("<https://x.dev/a>");
    expect(out).toContain('href="https://x.dev/a"');
    expect(out).not.toContain('&gt;"');
  });

  test("ordinary prose with no URL is escaped and otherwise untouched", () => {
    // An apostrophe is deliberately NOT escaped: it is harmless in text content, and every attribute
    // this builder emits is delimited with double quotes (which ARE escaped). Escaping it would only
    // make a client's surname render as "O&#39;Sullivan" in any client that mishandles entities.
    expect(escapeAndLinkify("Austin O'Sullivan & Co <client>")).toBe("Austin O'Sullivan &amp; Co &lt;client&gt;");
  });

  test("a double quote adjacent to a link cannot break out of the href attribute", () => {
    const out = escapeAndLinkify('he said "go to https://x.dev/a" today');
    expect(out).toContain("&quot;");
    expect(out.match(/href="/g)).toHaveLength(1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// END-TO-END MIME ASSEMBLY (added 2026-07-30)
//
// Everything above tests a PIECE. Nothing above assembled a whole message, and that is precisely
// where both real defects lived: the welded-bullet body and the mojibake em-dash Subject each
// survived a green suite and were caught by a human opening Gmail. These tests take a realistic
// markdown body all the way to the bytes that would be uploaded, then decode those bytes back.
//
// Decoding the base64 parts is the point. Asserting on the markdown, or on the intermediate
// blocks, would re-assert the assumption instead of testing the artifact — the same vacuous shape
// as the read-back that "matched: True" because it collapsed the whitespace it was meant to check.
// ─────────────────────────────────────────────────────────────────────────────
import { buildMime, validateMimeBeforeUpload, splitBodyIntoBlocks, blocksToPlainText, blocksToHtml } from "./gmail-draft.ts";

/** Pull one decoded MIME part out of an assembled message, by its Content-Type. */
function decodePart(mime: string, contentType: string): string {
  const parts = mime.split(/--b[0-9a-f]{32}/);
  const part = parts.find((p) => p.includes(`Content-Type: ${contentType}`));
  if (!part) throw new Error(`no ${contentType} part in the assembled message`);
  const body = part.split("\r\n\r\n").slice(1).join("\r\n\r\n").trim();
  return Buffer.from(body.replaceAll("\r\n", ""), "base64").toString("utf8");
}

/** A body shaped like the real client drafts: lead-in prose, then a list, then a closing line. */
const CLINIC_BODY = [
  "Hi {{CONTACT}} — three things from this morning, all checked before writing.",
  "",
  "- Brianna's caveat is withdrawn; her recording was fine.",
  "- Three page defects, not two — I miscounted the first time.",
  "- Tonsil values now print one way instead of eight.",
  "",
  "Nothing here needs action from you today.",
].join("\n");

const assemble = (subject: string, md: string): string => {
  const blocks = splitBodyIntoBlocks(md);
  return buildMime(
    { From: "a@b.co", To: "c@d.co", Cc: "", Subject: subject, "In-Reply-To": "", References: "" },
    blocksToPlainText(blocks),
    blocksToHtml(blocks),
  );
};

describe("end-to-end MIME assembly", () => {
  test("list bullets survive assembly as SEPARATE lines — the welded-paragraph defect", () => {
    const plain = decodePart(assemble("Three things", CLINIC_BODY), 'text/plain; charset="UTF-8"');
    // The defect welded these into one run-on paragraph containing '. - '.
    expect(plain).not.toContain(". - ");
    for (const bullet of ["Brianna's caveat", "Three page defects", "Tonsil values"]) {
      const line = plain.split("\n").find((l) => l.includes(bullet));
      expect(line).toBeDefined();
      // each bullet is alone on its line, not carrying a sibling
      expect(line!.includes("Three page defects") && line!.includes("Tonsil values")).toBe(false);
    }
  });

  test("the HTML part carries a real list, not paragraphs pretending to be one", () => {
    const html = decodePart(assemble("Three things", CLINIC_BODY), 'text/html; charset="UTF-8"');
    expect(html).toContain("<ul>");
    expect(html.match(/<li>/g)).toHaveLength(3);
  });

  test("both alternatives carry the same three bullets — a fix to one part must not skip the other", () => {
    const mime = assemble("Three things", CLINIC_BODY);
    const plain = decodePart(mime, 'text/plain; charset="UTF-8"');
    const html = decodePart(mime, 'text/html; charset="UTF-8"');
    for (const bullet of ["Brianna", "Three page defects", "Tonsil values"]) {
      expect(plain).toContain(bullet);
      expect(html).toContain(bullet);
    }
  });

  test("an em-dash Subject is RFC 2047 encoded in the header and decodes back intact", () => {
    const subject = "Correction — three things, one of them mine";
    const mime = assemble(subject, CLINIC_BODY);
    expect(mime).toContain("Subject: =?UTF-8?B?");
    expect(mime).not.toContain("â€”"); // the mojibake that actually shipped
    // The builder's own validator is the round-trip proof.
    expect(() => validateMimeBeforeUpload(mime, subject)).not.toThrow();
  });

  test("an ASCII Subject is left alone rather than needlessly encoded", () => {
    const mime = assemble("Plain ascii subject", CLINIC_BODY);
    expect(mime).toContain("Subject: Plain ascii subject");
    expect(mime).not.toContain("=?UTF-8?B?");
  });

  test("the structure is a well-formed multipart/alternative with a closing boundary", () => {
    const mime = assemble("Three things", CLINIC_BODY);
    const boundary = /boundary="(b[0-9a-f]{32})"/.exec(mime)?.[1];
    expect(boundary).toBeDefined();
    expect(mime.split(`--${boundary}`).length - 1).toBe(3); // two openers + the closer
    expect(mime.trimEnd().endsWith(`--${boundary}--`)).toBe(true);
  });

  test("empty headers are dropped — which is how a reply once addressed NOBODY", () => {
    // buildMime filters falsy values, so To:"" vanishes silently. The caller now refuses a
    // recipient-less draft; this pins the builder behaviour that made that refusal necessary.
    const mime = buildMime({ From: "a@b.co", To: "", Subject: "s" }, "p", "<p>h</p>");
    expect(mime).not.toContain("To:");
    expect(mime).toContain("From: a@b.co");
  });
});

describe("validateMimeBeforeUpload — proven in BOTH directions", () => {
  test("it PASSES a correctly assembled message", () => {
    const subject = "Correction — with an em dash";
    expect(() => validateMimeBeforeUpload(assemble(subject, CLINIC_BODY), subject)).not.toThrow();
  });

  test("it THROWS when the Subject header is mojibake", () => {
    // Exactly the 2026-07-29 regression: UTF-8 bytes read as Latin-1 in a raw header.
    const broken = assemble("x", CLINIC_BODY).replace("Subject: x", "Subject: Correction â€” three things");
    expect(() => validateMimeBeforeUpload(broken, "Correction — three things")).toThrow(/LAYER 2 VALIDATION FAILED/);
  });

  test("it THROWS when the multipart boundary declaration is missing", () => {
    const broken = assemble("x", CLINIC_BODY).replace('Content-Type: multipart/alternative; boundary=', "Content-Type: text/plain; x=");
    expect(() => validateMimeBeforeUpload(broken, "x")).toThrow(/missing multipart\/alternative boundary/);
  });
});

// ───────────────────────────────────────────────────────────────────────────────────────────────
// findForcedLineBreaksInRenderedHtml — the DETECTIVE half of the wrap guarantee (2026-08-07).
//
// Every other control here is preventive and checks the INPUT. This one reads the draft that was
// actually produced. It exists because three client emails shipped with forced mid-sentence breaks
// while every preventive layer reported green — the failure the tool is named for had no detector.
// ───────────────────────────────────────────────────────────────────────────────────────────────
import { findForcedLineBreaksInRenderedHtml } from "./gmail-draft.ts";

describe("findForcedLineBreaksInRenderedHtml", () => {
  // MUST PASS: exactly what blocksToHtml emits. Newlines separate TAGS and that is legal.
  test("clean render from blocksToHtml reports no violations", () => {
    const html = blocksToHtml(
      splitBodyIntoBlocks("First paragraph that a formatter\nwrapped across two lines.\n\n- item one\n- item two\n"),
    );
    expect(findForcedLineBreaksInRenderedHtml(html)).toEqual([]);
  });

  test("newlines between tags are legal, not violations", () => {
    const html = '<div dir="ltr">\n<p>one</p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</div>';
    expect(findForcedLineBreaksInRenderedHtml(html)).toEqual([]);
  });

  test("a genuinely long single-line paragraph is fine (that is the point of reflowing)", () => {
    const html = `<div dir="ltr">\n<p>${"word ".repeat(400).trim()}</p>\n</div>`;
    expect(findForcedLineBreaksInRenderedHtml(html)).toEqual([]);
  });

  // MUST FAIL: the real defect, in each shape it has actually taken.
  test("DETECTS a newline inside <p> — source hard-wrapping that survived", () => {
    const html = '<div dir="ltr">\n<p>I had a note drafted this morning saying the transcripts\nwere still waiting on you.</p>\n</div>';
    const v = findForcedLineBreaksInRenderedHtml(html);
    expect(v).toHaveLength(1);
    expect(v[0]).toMatch(/newline inside <p>/);
  });

  test("DETECTS a newline inside <li>", () => {
    const html = '<div dir="ltr">\n<ul>\n<li>a real fault, with a\nclinical consequence</li>\n</ul>\n</div>';
    expect(findForcedLineBreaksInRenderedHtml(html)[0]).toMatch(/newline inside <li>/);
  });

  test("DETECTS an explicit <br>, including <br/> and <BR>", () => {
    for (const br of ["<br>", "<br/>", "<br />", "<BR>"]) {
      const v = findForcedLineBreaksInRenderedHtml(`<div dir="ltr">\n<p>a${br}b</p>\n</div>`);
      expect(v.length).toBeGreaterThan(0);
      expect(v[0]).toMatch(/explicit <br>/);
    }
  });

  test("reports EVERY offending paragraph, not just the first", () => {
    const html = '<div dir="ltr">\n<p>one\ntwo</p>\n<p>fine</p>\n<p>three\nfour</p>\n</div>';
    expect(findForcedLineBreaksInRenderedHtml(html)).toHaveLength(2);
  });

  // The regression that actually shipped: a ~100-col formatter-wrapped body passed through as-is.
  test("DETECTS the 2026-08-07 shape — a formatter-wrapped body rendered without reflowing", () => {
    const hardWrapped = [
      "I had a note drafted this morning saying the transcripts were still waiting on you. It was",
      "wrong. You have left 64 comments across five of the seven documents, and you finished number",
      "3 at 12:08.",
    ].join("\n");
    const naive = `<div dir="ltr">\n<p>${hardWrapped}</p>\n</div>`;
    expect(findForcedLineBreaksInRenderedHtml(naive).length).toBeGreaterThan(0);

    // …and the builder's own path on the SAME source is clean. Both directions, one test.
    const viaBuilder = blocksToHtml(splitBodyIntoBlocks(hardWrapped));
    expect(findForcedLineBreaksInRenderedHtml(viaBuilder)).toEqual([]);
  });
});

describe("inline emphasis (bold arrives as rich text, never as asterisks)", () => {
  test("**bold**, *italic*, _italic_ and `code` render as tags in the HTML part", () => {
    const html = blocksToHtml(splitBodyIntoBlocks("**Office staff** (managing) can *view* the _records_ via `drive-office`."));
    expect(html).toContain("<b>Office staff</b>");
    expect(html).toContain("<i>view</i>");
    expect(html).toContain("<i>records</i>");
    expect(html).toContain("<code>drive-office</code>");
    expect(html).not.toContain("**");
  });
  test("bold inside a list item renders, and the bullet marker is still stripped", () => {
    const html = blocksToHtml(splitBodyIntoBlocks("Roles:\n- **Front desk**: view only\n- **Nobody** gets the archive"));
    expect(html).toContain("<li><b>Front desk</b>: view only</li>");
    expect(html).toContain("<li><b>Nobody</b> gets the archive</li>");
  });
  test("identifiers and arithmetic stay literal", () => {
    const html = blocksToHtml(splitBodyIntoBlocks("Keep snake_case_name and file_id_v2, 2*3*4 and a * b as written."));
    expect(html).toContain("snake_case_name");
    expect(html).toContain("file_id_v2");
    expect(html).toContain("2*3*4");
    expect(html).toContain("a * b");
    expect(html).not.toContain("<i>");
  });
  test("an underscore inside a word never OPENS emphasis, even when a later underscore could close it", () => {
    expect(renderInlineEmphasis("the file_name field and the dir_ prefix")).toBe("the file_name field and the dir_ prefix");
  });
  test("markers inside a code span stay verbatim", () => {
    expect(renderInlineEmphasis("`a **b** c`")).toBe("<code>a **b** c</code>");
  });
  test("emphasis does not break escaping or URL linking", () => {
    const html = blocksToHtml(splitBodyIntoBlocks("**Link:** https://example.com/a_b_c and <tag> & more"));
    expect(html).toContain("<b>Link:</b>");
    expect(html).toContain('<a href="https://example.com/a_b_c">');
    expect(html).toContain("&lt;tag&gt; &amp; more");
  });
  test("the text/plain part drops the markers and keeps the words", () => {
    const plain = blocksToPlainText(splitBodyIntoBlocks("**One decision:** see `x` and *this*.\n\n- **Front desk**: view"));
    expect(plain).toContain("One decision: see x and this.");
    expect(plain).toContain("- Front desk: view");
    expect(plain).not.toContain("**");
    expect(stripInlineEmphasis("snake_case_name 2*3*4")).toBe("snake_case_name 2*3*4");
  });
  test("the rendered HTML still has no forced line breaks", () => {
    expect(findForcedLineBreaksInRenderedHtml(blocksToHtml(splitBodyIntoBlocks("**A** b\nc d")))).toEqual([]);
  });
});

describe("Markdown autolinks", () => {
  test("<https://…> renders as a plain link with no visible angle brackets, in both parts", () => {
    const blocks = splitBodyIntoBlocks("Open <https://example.com/page/?review=a@b.example> to start.");
    const html = blocksToHtml(blocks);
    expect(html).toContain('<a href="https://example.com/page/?review=a@b.example">');
    expect(html).not.toContain("&lt;");
    expect(blocksToPlainText(blocks)).toContain("Open https://example.com/page/?review=a@b.example to start.");
  });
  test("a literal angle-bracketed word that is not a URL is still escaped", () => {
    expect(escapeAndLinkify("<tag>")).toBe("&lt;tag&gt;");
  });
});

import { renderPlainInline } from "./gmail-draft.ts";

describe("named links [text](url) — the reader sees words, not a 270-character address", () => {
  // A realistic long link: query string with every character class the task names.
  const longUrl = `https://accounts.example.com/signup/continue?flowName=GlifWebSignIn&continue=${"a%2Fb%3Dc+d".repeat(22)}&hl=en#section-2&user=a@b.example`;

  test("HTML part: the text is the anchor, the URL lives only in href", () => {
    expect(longUrl.length).toBeGreaterThan(270);
    const html = escapeAndLinkify(`Please [create your account](${longUrl}) today.`);
    const href = longUrl.replaceAll("&", "&amp;");
    expect(html).toBe(`Please <a href="${href}">create your account</a> today.`);
  });

  test("the URL inside a named link is never linked a second time", () => {
    const html = escapeAndLinkify("[docs](https://x.dev/a?p=1&q=2)");
    expect(html.match(/<a /g)?.length).toBe(1);
    expect(html).toBe('<a href="https://x.dev/a?p=1&amp;q=2">docs</a>');
  });

  test("bare URLs beside a named link still autolink", () => {
    const html = escapeAndLinkify("[one](https://a.dev/1) and https://b.dev/2.");
    expect(html).toBe('<a href="https://a.dev/1">one</a> and <a href="https://b.dev/2">https://b.dev/2</a>.');
  });

  test("text and attribute are escaped; emphasis inside the text renders", () => {
    const html = escapeAndLinkify('[**Tom & "Jerry"** <b>](https://x.dev/?a="b"&c=<d>)');
    expect(html).toBe('<a href="https://x.dev/?a=&quot;b&quot;&amp;c=&lt;d&gt;"><b>Tom &amp; &quot;Jerry&quot;</b> &lt;b&gt;</a>');
  });

  test("mailto: is accepted", () => {
    expect(escapeAndLinkify("[write to us](mailto:help@example.com)")).toBe('<a href="mailto:help@example.com">write to us</a>');
  });

  test("any other scheme stays literal text, escaped, never an anchor", () => {
    for (const target of ["javascript:alert(1)", "data:text/html,hi", "file:///etc/passwd", "/relative/path", "ftp://x.dev/a"]) {
      const html = escapeAndLinkify(`[click](${target})`);
      expect(html).not.toContain("<a ");
      expect(html).toBe(`[click](${target})`);
    }
  });

  test("one level of balanced parentheses in the target is kept", () => {
    expect(escapeAndLinkify("[parser](https://en.wikipedia.org/wiki/Parser_(software)).")).toBe(
      '<a href="https://en.wikipedia.org/wiki/Parser_(software)">parser</a>.',
    );
  });

  test("an unbalanced ) ends the target (documented limitation; use %29)", () => {
    const html = escapeAndLinkify("[x](https://x.dev/a)b)");
    expect(html).toBe('<a href="https://x.dev/a">x</a>b)');
  });

  test("whitespace in the target means it is not a named link", () => {
    expect(escapeAndLinkify("[x](https://x.dev/a b)")).toBe('[x](<a href="https://x.dev/a">https://x.dev/a</a> b)');
  });

  test("the CommonMark <…> target form works", () => {
    expect(escapeAndLinkify("[x](<https://x.dev/a>)")).toBe('<a href="https://x.dev/a">x</a>');
  });

  test("a URL written in angle brackets after a named link does not absorb &gt (the old fix holds)", () => {
    expect(escapeAndLinkify("[x](https://x.dev/a) <https://y.dev/b>")).toBe(
      '<a href="https://x.dev/a">x</a> <a href="https://y.dev/b">https://y.dev/b</a>',
    );
  });

  test("text/plain part: `link text (URL)`, markers dropped", () => {
    expect(renderPlainInline(`Please [**create** your account](${longUrl}) today.`)).toBe(`Please create your account (${longUrl}) today.`);
    expect(renderPlainInline("[https://x.dev/a](https://x.dev/a)")).toBe("https://x.dev/a");
    expect(renderPlainInline("[help@example.com](mailto:help@example.com)")).toBe("help@example.com");
    expect(renderPlainInline("[click](javascript:alert(1))")).toBe("[click](javascript:alert(1))");
  });

  test("text/plain part: underscores inside a URL survive the emphasis stripper", () => {
    expect(renderPlainInline("see https://x.dev/_draft_/a and _this_")).toBe("see https://x.dev/_draft_/a and this");
    expect(renderPlainInline("[doc](https://x.dev/_draft_/a)")).toBe("doc (https://x.dev/_draft_/a)");
  });

  test("end to end through the block renderers, with no forced line breaks", () => {
    const blocks = splitBodyIntoBlocks(`Steps:\n- [Open the form](${longUrl})\n- Reply here`);
    const html = blocksToHtml(blocks);
    expect(html).toContain(">Open the form</a></li>");
    expect(findForcedLineBreaksInRenderedHtml(html)).toEqual([]);
    expect(blocksToPlainText(blocks)).toContain(`- Open the form (${longUrl})`);
  });
});

describe("--html: an authored html part is refused unless it is safe and says what the plain part says", () => {
  const load = () => import("./gmail-draft.ts");
  const plain = "Hello Alex,\n\nThe report is ready. See the quote below.\n\n- Call, 1 Jan 10:00:00, me: \"It is done.\"\n";
  const good =
    '<!doctype html><html lang="en"><body><table role="presentation"><tr><td style="font-family:Arial">' +
    "<p>Hello Alex,</p><p>The report is ready. See the quote below.</p>" +
    '<blockquote style="border-left:3px solid #456">Call &middot; 1 Jan &middot; 10:00:00 &middot; me<br>"It is done."</blockquote>' +
    "</td></tr></table></body></html>";

  test("a clean designed part passes, even with separators and a <br> the converter would never emit", async () => {
    const { findAuthoredHtmlProblems } = await load();
    expect(findAuthoredHtmlProblems(good, plain)).toEqual([]);
  });

  test("a dropped word is refused and named", async () => {
    const { findAuthoredHtmlProblems } = await load();
    const p = findAuthoredHtmlProblems(good.replace("is ready", "ready"), plain);
    expect(p.length).toBe(1);
    expect(p[0]).toContain('"is"');
  });

  test("reordered words are refused, not just missing ones", async () => {
    const { findAuthoredHtmlProblems } = await load();
    const swapped = good.replace("<p>Hello Alex,</p><p>The report is ready. See the quote below.</p>", "<p>The report is ready. See the quote below.</p><p>Hello Alex,</p>");
    expect(findAuthoredHtmlProblems(swapped, plain).some((x) => x.includes("out of order"))).toBe(true);
  });

  test("script, event handlers and external resources are each refused", async () => {
    const { findAuthoredHtmlProblems } = await load();
    expect(findAuthoredHtmlProblems(good.replace("</body>", "<script>x()</script></body>"), plain).join()).toContain("<script>");
    expect(findAuthoredHtmlProblems(good.replace("<p>Hello", '<p onclick="x()">Hello'), plain).join()).toContain("event handler");
    expect(findAuthoredHtmlProblems(good.replace("<p>Hello", '<img src="https://example.com/p.gif"><p>Hello'), plain).join()).toContain("external resource");
    expect(findAuthoredHtmlProblems(good.replace('style="font-family:Arial"', 'style="background:url(//example.com/b.png)"'), plain).join()).toContain("external resource");
  });

  test("the word 'online' in prose is not mistaken for an event handler", async () => {
    const { findAuthoredHtmlProblems } = await load();
    const p2 = "We met online today.";
    expect(findAuthoredHtmlProblems("<p>We met online today.</p>", p2)).toEqual([]);
  });

  test("a part past Gmail's clipping size is refused", async () => {
    const { findAuthoredHtmlProblems, GMAIL_CLIP_SAFE_BYTES } = await load();
    const big = good.replace("</td>", `<p>${"x ".repeat(GMAIL_CLIP_SAFE_BYTES)}</p></td>`);
    expect(findAuthoredHtmlProblems(big, plain).join()).toContain("clips");
  });

  test("visible text drops head/style, decodes entities and numeric references", async () => {
    const { visibleTextOfHtml } = await load();
    expect(visibleTextOfHtml("<head><title>T</title><style>p{}</style></head><p>a&nbsp;&amp;&#8217;b &#x2014; c</p>")).toBe("a &’b — c");
  });

  test("an out-of-range numeric reference is kept as written instead of crashing", async () => {
    const { visibleTextOfHtml } = await load();
    expect(visibleTextOfHtml("<p>a &#99999999; b &#x110000; c</p>")).toBe("a &#99999999; b &#x110000; c");
  });
});

import { findAuthoredHtmlProblems, linkAwareTextOfHtml, loadDraftParts, parseArgs, USAGE } from "./gmail-draft.ts";

describe("--html with named links: the href counts where the plain part writes (URL)", () => {
  const url = "https://x.dev/a?p=1&q=2";
  const body = `Please [create your account](${url}) today.`;
  const plainOf = (md: string): string => blocksToPlainText(splitBodyIntoBlocks(md));
  const anchor = '<a href="https://x.dev/a?p=1&amp;q=2">create your account</a>';

  test("the plain part really does carry the URL (the premise of this suite)", () => {
    expect(plainOf(body)).toContain(`create your account (${url})`);
  });

  test("an html part with the named link as an anchor passes", () => {
    expect(findAuthoredHtmlProblems(`<p>Please ${anchor} today.</p>`, plainOf(body))).toEqual([]);
  });

  test("the anchor reads as `words (URL)`, entities in href decoded", () => {
    expect(linkAwareTextOfHtml(`<p>Please ${anchor} today.</p>`)).toBe(`Please create your account (${url}) today.`);
  });

  test("an html part that genuinely drops a word is still refused, and names the word", () => {
    const p = findAuthoredHtmlProblems(`<p>Please ${anchor.replace("your ", "")} today.</p>`, plainOf(body));
    expect(p.length).toBe(1);
    expect(p[0]).toContain('"your"');
  });

  test("an html part that drops the link, or points it elsewhere, is refused", () => {
    expect(findAuthoredHtmlProblems("<p>Please create your account today.</p>", plainOf(body)).join()).toContain("missing");
    expect(findAuthoredHtmlProblems(`<p>Please ${anchor.replace("x.dev", "evil.example")} today.</p>`, plainOf(body)).join()).toContain("missing");
  });

  test("a bare URL in the body may be an anchor whose words are the URL, sentence punctuation intact", () => {
    expect(linkAwareTextOfHtml('<p>See <a href="https://b.dev/2">https://b.dev/2</a>.</p>')).toBe("See https://b.dev/2.");
    expect(findAuthoredHtmlProblems('<p>See <a href="https://b.dev/2">https://b.dev/2</a>.</p>', plainOf("See https://b.dev/2."))).toEqual([]);
  });

  test("mailto: and single-quoted hrefs pass", () => {
    const md = "Write to [help@example.com](mailto:help@example.com) or [the desk](https://d.dev/x).";
    const html = "<p>Write to <a href=\"mailto:help@example.com\">help@example.com</a> or <a href='https://d.dev/x'><b>the desk</b></a>.</p>";
    expect(findAuthoredHtmlProblems(html, plainOf(md))).toEqual([]);
  });
});

describe("--html blocklist (defence in depth; Gmail strips most of this anyway)", () => {
  const plain = "Hello there.";
  const wrap = (inner: string): string => `<p>Hello there.</p>${inner}`;
  const problemsOf = (inner: string): string => findAuthoredHtmlProblems(wrap(inner), plain).join(" | ");

  test("the bare wrapper is clean (control)", () => {
    expect(findAuthoredHtmlProblems(wrap(""), plain)).toEqual([]);
  });

  test("javascript: in href is refused, however it is spelled", () => {
    for (const href of ["javascript:alert(1)", " JavaScript:alert(1)", "java&#x09;script:alert(1)", "javascript&colon;alert(1)", "&#106;avascript:x"]) {
      expect(problemsOf(`<a href="${href}">x</a>`)).toContain("javascript:");
    }
  });

  test("vbscript: and data: in href or src are refused", () => {
    expect(problemsOf('<a href="vbscript:msgbox(1)">x</a>')).toContain("vbscript:");
    expect(problemsOf('<a href="data:text/html,hi">x</a>')).toContain("data:");
    expect(problemsOf('<img src="data:image/png;base64,AAAA">')).toContain("data:");
    expect(problemsOf("<p style=\"background:url('javascript:x')\"></p>")).toContain("javascript:");
  });

  test("iframe, object, embed and form are each refused", () => {
    expect(problemsOf('<iframe src="cid:x"></iframe>')).toContain("<iframe>");
    expect(problemsOf('<object data="cid:x"></object>')).toContain("<object>");
    expect(problemsOf('<embed src="cid:x">')).toContain("<embed>");
    expect(problemsOf('<form action="cid:x"><input></form>')).toContain("<form>");
  });

  test("<meta http-equiv> is refused; <meta charset> is not", () => {
    expect(problemsOf('<meta http-equiv="refresh" content="0;url=https://evil.example">')).toContain("http-equiv");
    expect(findAuthoredHtmlProblems(`<meta charset="utf-8">${wrap("")}`, plain)).toEqual([]);
  });

  test("srcset pointing outside is refused; a cid: srcset is not", () => {
    expect(problemsOf('<img src="cid:a" srcset="cid:a 1x, https://t.example/p.gif 2x">')).toContain("external resource");
    expect(problemsOf('<img src="cid:a" srcset="//t.example/p.gif 1x">')).toContain("external resource");
    expect(findAuthoredHtmlProblems(wrap('<img src="cid:a" srcset="cid:a 1x, cid:b 2x">'), plain)).toEqual([]);
  });

  test("an ordinary https link is allowed: href navigates on a click, it loads nothing", () => {
    expect(findAuthoredHtmlProblems(wrap('<a href="https://x.dev/">x</a>'), plain)).toEqual([]);
  });

  test("event handlers are found in attribute position, including after a slash", () => {
    expect(problemsOf("<svg/onload=x()></svg>")).toContain("onload");
    expect(problemsOf('<div title="a>b" onmouseover="x()">y</div>')).toContain("onmouseover");
  });

  test("'online=' in prose or inside an attribute value is not an event handler", () => {
    const md = "Set online=true, then go online= now.";
    expect(findAuthoredHtmlProblems("<p>Set online=true, then go online= now.</p>", md)).toEqual([]);
    expect(findAuthoredHtmlProblems(wrap('<img src="cid:x" alt="go online=now">'), plain)).toEqual([]);
  });
});

describe("CLI path: --html <file> through argument parsing to the assembled MIME (no network)", () => {
  const { mkdtempSync, writeFileSync } = require("node:fs") as typeof import("node:fs");
  const { tmpdir } = require("node:os") as typeof import("node:os");
  const { join } = require("node:path") as typeof import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "gmail-draft-cli-"));
  const bodyPath = join(dir, "body.md");
  const htmlPath = join(dir, "body.html");
  const badPath = join(dir, "bad.html");
  writeFileSync(bodyPath, "Hello Alex,\n\nPlease [open the form](https://x.dev/f?a=1&b=2) by Friday.\n");
  const authored =
    '<table role="presentation"><tr><td><p>Hello Alex,</p><p>Please <a href="https://x.dev/f?a=1&amp;b=2">open the form</a> by Friday.</p></td></tr></table>';
  writeFileSync(htmlPath, authored);
  writeFileSync(badPath, authored.replace("by Friday", "Friday").replace("<td>", '<td onclick="x()">'));
  const argv = (html: string): string[] => [
    "bun", "gmail-draft.ts", "--account", "test", "--body", bodyPath, "--from", "A <a@b.co>", "--to", "c@d.co", "--subject", "S", "--html", html,
  ];

  test("parseArgs reads --html; a missing required flag throws the usage line", () => {
    expect(parseArgs(argv(htmlPath)).html).toBe(htmlPath);
    expect(parseArgs(["bun", "gmail-draft.ts", "--account", "t", "--body", bodyPath, "--from", "x"]).html).toBeUndefined();
    expect(() => parseArgs(["bun", "gmail-draft.ts", "--body", bodyPath])).toThrow(USAGE);
  });

  test("the html file becomes the text/html part verbatim; --body still supplies text/plain", async () => {
    const args = parseArgs(argv(htmlPath));
    const parts = await loadDraftParts(args);
    expect(parts.authoredHtml).toBe(authored);
    const mime = buildMime({ From: args.from, To: args.to ?? "", Subject: "S" }, parts.plain, parts.html);
    validateMimeBeforeUpload(mime, "S");
    expect(decodePart(mime, "text/html")).toBe(authored);
    expect(decodePart(mime, "text/plain")).toContain("open the form (https://x.dev/f?a=1&b=2) by Friday.");
  });

  test("a refused --html names every problem", async () => {
    await expect(loadDraftParts(parseArgs(argv(badPath)))).rejects.toThrow(/REFUSED --html[\s\S]*event handler[\s\S]*"by"/);
  });

  test("the script refuses a bad --html before any token read (HOME is an empty dir, so no network is possible)", () => {
    const run = Bun.spawnSync(["bun", join(import.meta.dir, "gmail-draft.ts"), ...argv(badPath).slice(2)], {
      env: { ...process.env, HOME: dir, GMAIL_DRAFT_ACCOUNT: "" },
      stdout: "pipe",
      stderr: "pipe",
    });
    const err = run.stderr.toString();
    expect(run.exitCode).toBe(1);
    expect(err).toContain(`REFUSED --html ${badPath}`);
    expect(err).not.toMatch(/ENOENT|refresh_token|oauth2/);
    expect(run.stdout.toString()).toBe("");
  });
});
