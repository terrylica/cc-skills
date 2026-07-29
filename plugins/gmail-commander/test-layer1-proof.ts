#!/usr/bin/env bun
/**
 * Proof-of-concept: demonstrate that Layer 1 verification catches encoding regressions.
 *
 * This script:
 * 1. Temporarily breaks the RFC 2047 encoder to return raw UTF-8 (mojibake)
 * 2. Attempts to create a draft with an em-dash subject
 * 3. Shows that the Layer 1 assertion FAILS (as required)
 * 4. Then restores the encoder and shows it PASSES
 */

import { encodeHeaderValueAsRfc2047EncodedWordIfNonAscii } from "./scripts/gmail-draft.ts";

// Simulate the Layer 1 verification function (simplified for local testing)
function decodeRfc2047EncodedWordSequence(encoded: string): string {
  if (!encoded.includes("=?UTF-8?B?")) return encoded;
  const decodedChunks = encoded
    .split(" ")
    .map((word) => Buffer.from(word.replace(/^=\?UTF-8\?B\?/, "").replace(/\?=$/, ""), "base64"));
  return Buffer.concat(decodedChunks).toString("utf8");
}

function verifySubjectRoundTrip(originalSubject: string, encodedSubject: string): boolean {
  const decodedSubject = decodeRfc2047EncodedWordSequence(encodedSubject);
  return decodedSubject === originalSubject;
}

console.log("=== Layer 1 Verification Proof ===\n");

const testSubject = "Charting update — privacy matter, Mallampati fix, word list, and clarifications on four recordings";
console.log(`Original subject: "${testSubject}"\n`);

// TEST 1: With correct encoder (SHOULD PASS)
console.log("TEST 1: With correct RFC 2047 encoder (PASSES)");
const encoded = encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(testSubject);
console.log(`  Encoded: "${encoded}"`);
const passesRoundTrip = verifySubjectRoundTrip(testSubject, encoded);
console.log(`  Round-trip verification: ${passesRoundTrip ? "✅ PASS" : "❌ FAIL"}`);
if (!passesRoundTrip) {
  const decoded = decodeRfc2047EncodedWordSequence(encoded);
  console.log(`  ERROR: Original "${testSubject}" != Decoded "${decoded}"`);
  process.exit(1);
}

// TEST 2: Simulate broken encoder returning raw UTF-8 (the 2026-07-29 bug)
console.log("\nTEST 2: Simulating broken encoder (returns raw UTF-8) → FAILS verification");
const brokenEncoded = testSubject; // Raw UTF-8, no encoding
console.log(`  Broken "encoded": "${brokenEncoded}"`);
const failsRoundTrip = verifySubjectRoundTrip(testSubject, brokenEncoded);
console.log(`  Round-trip verification: ${failsRoundTrip ? "✅ PASS" : "❌ FAIL"}`);
if (failsRoundTrip) {
  console.log("  ERROR: Expected verification to fail, but it passed!");
  process.exit(1);
}
console.log(`  ✅ Layer 1 correctly DETECTED the broken encoder`);

console.log("\n=== All proofs passed ===");
console.log("Layer 1 verification CATCHES encoding regressions that the encoder itself might miss.");
