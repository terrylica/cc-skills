/**
 * Regression tests for RFC 2047 mail-header encoding.
 *
 * Guards against the "â€"" mojibake bug: non-ASCII header values (em-dash,
 * curly quotes, accented names) MUST be emitted as RFC 2047 encoded-words so
 * mail clients decode them as UTF-8 instead of Latin-1.
 *
 * Run: `bun test` inside scripts/gmail-cli/
 */
import { describe, expect, test } from "bun:test";
import { encodeAddressHeader, encodeMimeHeader } from "./gmail-drafts.ts";

// Decode an RFC 2047 header back to its original string (B-encoded words only),
// mirroring what a conforming mail client does on display.
function decodeMimeHeader(encoded: string): string {
  return encoded
    .replace(/\r\n[ \t]+/g, "") // unfold continuation lines (and the join space)
    .replace(/=\?UTF-8\?B\?([^?]*)\?=/gi, (_m, b64) =>
      Buffer.from(b64, "base64").toString("utf-8"),
    );
}

describe("encodeMimeHeader", () => {
  test("passes pure ASCII through untouched", () => {
    const s = "Plain ASCII subject 123 !@#";
    expect(encodeMimeHeader(s)).toBe(s);
  });

  test("encodes an em-dash subject as an RFC 2047 word (no raw bytes)", () => {
    const s = "Danusha — curriculum status ahead of Tue Jun 23 training";
    const out = encodeMimeHeader(s);
    expect(out).toContain("=?UTF-8?B?");
    expect(out).not.toContain("—"); // raw multibyte char must not survive in the header
    expect(decodeMimeHeader(out)).toBe(s);
  });

  test("round-trips curly quotes, accents, and emoji", () => {
    for (const s of [
      "“Smart quotes” and ‘apostrophes’",
      "Wickramachchi — café résumé naïve",
      "Status update ✅ done",
    ]) {
      const out = encodeMimeHeader(s);
      expect(decodeMimeHeader(out)).toBe(s);
    }
  });

  test("keeps each encoded-word within the RFC 2047 75-char cap", () => {
    const s = "— ".repeat(60); // long, forces multiple encoded-words
    for (const word of encodeMimeHeader(s).split("\r\n ")) {
      expect(word.length).toBeLessThanOrEqual(75);
    }
  });

  test("never splits a multibyte codepoint across encoded-words", () => {
    const s = "🎉".repeat(40); // 4-byte codepoints
    expect(decodeMimeHeader(encodeMimeHeader(s))).toBe(s);
  });
});

describe("encodeAddressHeader", () => {
  test("leaves a bare ASCII address alone", () => {
    expect(encodeAddressHeader("a@b.com")).toBe("a@b.com");
  });

  test("encodes only the display name, never the angle-addr", () => {
    const out = encodeAddressHeader("Café Owner <a@b.com>");
    expect(out).toContain("<a@b.com>");
    expect(out).toContain("=?UTF-8?B?");
    expect(decodeMimeHeader(out)).toBe("Café Owner <a@b.com>");
  });

  test("passes an ASCII display name through verbatim", () => {
    expect(encodeAddressHeader('"Dr. Phoebe W. Tsang Inc." <dmd0876@gmail.com>')).toBe(
      '"Dr. Phoebe W. Tsang Inc." <dmd0876@gmail.com>',
    );
  });
});
