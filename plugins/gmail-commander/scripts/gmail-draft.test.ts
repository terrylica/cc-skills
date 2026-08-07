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
import { escapeAndLinkify } from "./gmail-draft.ts";
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
    From: "Ricky Chan <rickychanbc@gmail.com>",
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
  "Hi Alex — three things from this morning, all checked before writing.",
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
