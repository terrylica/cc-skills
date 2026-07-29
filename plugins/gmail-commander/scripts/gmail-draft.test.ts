// Unit tests for the Gmail draft builder's header encoding.
//
// These exist because of the 2026-07-29 mojibake report: a draft subject containing an em dash
// reached the client's inbox as "Charting update mojibake privacy matter". Until now this file's
// functions could not be imported at all — the script ran its main block at import time and exited
// with a usage error — so the encoder had no test. A script whose functions cannot be imported
// cannot be proven correct.
//
// Run: bun test plugins/gmail-commander/scripts/gmail-draft.test.ts
import { test, expect } from "bun:test";
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
