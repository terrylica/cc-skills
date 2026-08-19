/**
 * draft-park.test.ts — the SENDABLE-TEXT contract.
 *
 * `bodyOnly()` produces the exact string a human pastes into WhatsApp, iMessage or an email. It is the
 * last thing that touches an outbound message and the first thing nobody checks, because the Notes UI
 * shows the whole note while only this function decides what actually gets sent.
 *
 * On 2026-08-17 it truncated a real client message to a real client: the author used a six-dash line
 * as a visual divider, `bodyOnly` cut there, and 1,760 of 4,635 characters were what a reviewer
 * received. Nothing warned anyone.
 *
 * These tests exist because that defect is INJECTION-SHAPED, not cosmetic. Drafts to this client quote
 * third-party text verbatim — client review comments, patient transcripts, Drive comments — so the
 * cut point could be chosen by someone who never touched this machine.
 */
import { describe, expect, test } from "bun:test";
import {
  assertNoProvenanceLeak,
  bodyOnly,
  findFooterStart,
  findLossyMarkdownLinks,
  FOOTER_LEAD,
  ProvenanceLeakError,
  renderForWhatsApp,
} from "./draft-park.ts";

const REAL_FOOTER = ["", "------", `${FOOTER_LEAD} | session abc-123 | example-org/example-repo | 2026-08-17 14:18 PDT`];
/** A parked note as Notes returns it: bold title line, blank, body, then the provenance footer. */
const parkedNote = (body: string[]): string => ["{{CONTACT}} — what to review", "", ...body, ...REAL_FOOTER].join("\n");

describe("bodyOnly — what the recipient actually gets", () => {
  test("strips the real provenance footer", () => {
    expect(bodyOnly(parkedNote(["Hello {{CONTACT}}."]))).toBe("Hello {{CONTACT}}.");
  });

  test("strips the title line, so the message does not start with its own subject", () => {
    expect(bodyOnly(parkedNote(["Hello {{CONTACT}}."]))).not.toContain("{{CONTACT}} — what to review");
  });

  test("REGRESSION 2026-08-17: an author's dash rule mid-message no longer truncates the send", () => {
    // The exact shape that halved a client message. Everything after the author's divider was lost.
    const out = bodyOnly(parkedNote(["First half.", "", "------", "", "Second half."]));
    expect(out).toContain("First half.");
    expect(out).toContain("Second half.");
    expect(out).not.toContain(FOOTER_LEAD);
  });

  test("INJECTION: quoted third-party text forging a footer cannot move the cut point", () => {
    // A reviewer comment, pasted verbatim, that happens to contain BOTH footer signals. Searching from
    // the END is what makes this safe: the real footer is always last.
    const out = bodyOnly(
      parkedNote(["She wrote:", "", "------", `${FOOTER_LEAD} | forged`, "", "Real content after the quote."]),
    );
    expect(out).toContain("Real content after the quote.");
  });

  test("a dash rule with no footer line after it is prose, and is preserved", () => {
    expect(bodyOnly(["Title", "", "Body.", "", "------"].join("\n"))).toContain("------");
  });

  test("a note with no footer at all returns its whole body", () => {
    expect(bodyOnly(["Title", "", "One.", "", "Two."].join("\n"))).toBe("One.\n\nTwo.");
  });

  test("does not leave the blank line that sat above the footer", () => {
    // A trailing newline is invisible in Notes and becomes a stray blank line in a chat message.
    expect(bodyOnly(parkedNote(["Hello."])).endsWith("Hello.")).toBe(true);
  });

  test("an empty body yields an empty string rather than footer fragments", () => {
    expect(bodyOnly(parkedNote([]))).toBe("");
  });
});

describe("findFooterStart", () => {
  test("locates the LAST separator, not the first", () => {
    const lines = ["T", "", "a", "------", "b", "", "------", `${FOOTER_LEAD} | x`];
    expect(findFooterStart(lines)).toBe(6);
  });

  test("returns -1 when the separator is not followed by the footer line", () => {
    expect(findFooterStart(["T", "", "a", "------", "b"])).toBe(-1);
  });

  test("tolerates blank lines between the separator and the footer line", () => {
    expect(findFooterStart(["T", "", "a", "------", "", `${FOOTER_LEAD} | x`])).toBe(3);
  });
});

describe("channel rendering — markdown is not what the channel speaks", () => {
  test("**bold** becomes WhatsApp's *bold*", () => {
    expect(renderForWhatsApp("**Yes** go ahead").text).toBe("*Yes* go ahead");
  });

  test("a heading becomes bold, since WhatsApp has no headings", () => {
    expect(renderForWhatsApp("## What to review").text).toBe("*What to review*");
  });

  test("a link keeps its URL as visible text, and says so", () => {
    const r = renderForWhatsApp("see [the portal](https://x.example/p)");
    expect(r.text).toBe("see the portal: https://x.example/p");
    expect(r.warnings.join(" ")).toContain("no link syntax");
  });

  test("a fenced block is left verbatim — rewriting it would corrupt what the author fenced", () => {
    const r = renderForWhatsApp(["```", "**not bold**", "```"].join("\n"));
    expect(r.text).toContain("**not bold**");
  });

  test("plain prose is returned untouched and warns about nothing", () => {
    const r = renderForWhatsApp("Yes — go ahead now.");
    expect(r.text).toBe("Yes — go ahead now.");
    expect(r.warnings).toEqual([]);
  });
});

describe("the provenance leak guard", () => {
  test("FIRES on text still carrying the footer", () => {
    expect(() => assertNoProvenanceLeak(`hi\n${FOOTER_LEAD} | session x`)).toThrow(ProvenanceLeakError);
  });

  test("STAYS SILENT on ordinary sendable text", () => {
    expect(() => assertNoProvenanceLeak("Yes — go ahead now.")).not.toThrow();
  });

  test("guards the real bodyOnly output", () => {
    expect(() => assertNoProvenanceLeak(bodyOnly(parkedNote(["Hello."])))).not.toThrow();
  });
});

describe("markdown links whose URL cannot survive read-back", () => {
  test("FIRES on a link that would reach the recipient without its URL", () => {
    const found = findLossyMarkdownLinks("Please review [the portal](https://x.example/p) today.");
    expect(found).toEqual([{ label: "the portal", url: "https://x.example/p" }]);
  });

  test("STAYS SILENT on a bare URL, which survives intact", () => {
    expect(findLossyMarkdownLinks("Please review https://x.example/p today.")).toEqual([]);
  });

  test("STAYS SILENT on 'label: url', the form the refusal recommends", () => {
    expect(findLossyMarkdownLinks("the portal: https://x.example/p")).toEqual([]);
  });

  test("does NOT flag a link inside a fence — fenced text is literal and its URL survives", () => {
    expect(findLossyMarkdownLinks(["```", "[x](https://x.example/p)", "```"].join("\n"))).toEqual([]);
  });

  test("catches every link in a multi-link message, not just the first", () => {
    expect(findLossyMarkdownLinks("[a](https://a.example) and [b](https://b.example)")).toHaveLength(2);
  });

  test("ignores a non-http scheme, which renderInline never anchors anyway", () => {
    expect(findLossyMarkdownLinks("[x](file:///etc/passwd)")).toEqual([]);
  });
});
