# Gmail Draft Hardening: Three Independent Layers

## Overview

The 2026-07-29 mojibake regression (Subject: "Charting update — privacy matter" → "Charting update â€" privacy matter") revealed that encoding regressions keep escaping safeguards. This document defines **three independent hardening layers**, each catching different failure modes.

They are **deliberately independent** — no layer is a substitute for another. A defect in one layer is caught by the others. Together they form a defense-in-depth strategy.

---

## Layer 1: The Builder Verifies Its Own Output (STRONGEST)

**Owner mindset:** "I just created something, let me prove it came back intact."

### What it does

After creating a draft via the Gmail API, immediately read it back and assert it round-trips correctly.

**Code location:** `/scripts/gmail-draft.ts` → `assertCreatedDraftMatchesWhatWeSent()` (lines ~213-250)

**Called at:** Lines ~256-269 (after draft creation, before success JSON output)

### Invariants verified

1. **Subject round-trips exactly**
   - Reads Subject header from `GET /drafts/{draftId}?format=full`
   - Decodes RFC 2047 encoded-word if present
   - Compares decoded result to original subject
   - **Failure:** throws with full chain (original → sent → received → decoded)

2. **MIME structure is intact**
   - Verifies `text/plain` part exists and is non-empty
   - **Failure:** throws if missing or corrupted

### Why this is the strongest

- Checks the RESULT, not pattern-matching known bad outputs
- Catches encoding surfaces nobody anticipated (as both regressions did)
- Catches Gmail API bugs or network corruption (not our code alone)
- One-time cost: ~200ms per draft (acceptable for human-authored emails)

### Proof

Run: `bun scripts/LAYER1-VERIFICATION-PROOF.ts`

Output shows:

- ✅ Correct encoder → passes
- ❌ Broken encoder (raw UTF-8) → mojibake returned → **LAYER 1 CATCHES IT**
- ❌ Gmail misinterprets as Latin-1 → **LAYER 1 CATCHES IT**

---

## Layer 2: Static Validation Before API Call (PREVENTION)

**Owner mindset:** "Catch errors before they leave this machine, before Gmail even sees them."

### What it does

Before calling the Gmail API, validate that the MIME message we built is structurally sound. Decode what we're about to send and verify it matches the input.

**Recommended implementation:**

```typescript
function validateMimeBeforeUpload(
  mimeString: string,
  originalSubject: string,
  originalBodyText: string,
): void {
  // 1. Parse MIME headers from the string
  // 2. Extract Subject header
  // 3. Decode RFC 2047 if present
  // 4. Verify: decodedSubject === originalSubject (fail loud if not)
  // 5. Verify: text/plain part exists in the MIME structure
  // 6. Verify: base64-encoded body decodes back to originalBodyText (spot-check)
}
```

Called just before the `api(at, "drafts", "POST", ...)` call.

### Why this layer matters

- Catches encoder bugs before wasting an API call
- Catches MIME construction bugs (boundary corruption, encoding typos)
- Cheap: only string parsing, no network
- Serves as a **seal on the encoder**: if Layer 2 passes, the encoder is working

### Benefit over Layer 1

Layer 2 is **preventative** — it stops bad data at the source. Layer 1 is **detective** — it finds problems after they've escaped. Layer 2 fails faster and more obviously.

---

## Layer 3: Prompt Rule + Unit Test (DESIGN-TIME)

**Owner mindset:** "Guard against regression by encoding the rule into the prompt and testing it as a matter of course."

### What it does

**3a. Prompt rule:** Add a bullet to the main `gmail-draft.ts` usage docstring:

```
SAFETY RULE (Layer 3): Non-ASCII headers are always RFC 2047-encoded.
  If you modify encodeHeaderValueAsRfc2047EncodedWordIfNonAscii or buildMime
  to bypass RFC 2047 encoding, the next deploy MUST include a unit test proving
  the new path works (see gmail-draft.test.ts for examples).
```

**3b. Unit tests:** Test suite in `gmail-draft.test.ts` covers:

- Regression test: the exact 2026-07-29 subject survives encoding
- Encoder correctness: pure-ASCII bypasses, non-ASCII encodes
- RFC 2047 spec compliance: encoded-words stay <75 chars, multi-byte chars reassemble
- MIME round-trip: the full buildMime output can be parsed and decoded

**Tests run:** `bun test scripts/gmail-draft.test.ts` (5 tests, ~9ms)

### Why this layer matters

- **Documents intent** — anyone reading the code knows why RFC 2047 exists
- **Catches typos** — a flubbed encoder change breaks a test immediately
- **Regression-proofs** — can't reintroduce 2026-07-29 without failing the test
- **Zero cost at runtime** — tests are dev-time only

### How it works

When a developer:

1. Changes `encodeHeaderValueAsRfc2047EncodedWordIfNonAscii` (the encoder)
2. Changes `buildMime` (the MIME builder)
3. Changes `FREE_TEXT_HEADERS_SAFE_TO_ENCODE` (the scope of what gets encoded)

The unit test suite MUST PASS. If it doesn't, the change must be rolled back or the test extended to cover the new behavior.

---

## Integration: How the Three Layers Work Together

```
Build draft → validate MIME (Layer 2) → upload to Gmail (API) → read back (Layer 1)
     ↑                    ↑                                              ↑
  Encoder                Tests catch                                    Catches
  unit tests            regressions                                  anything that
  (Layer 3)             at code-write                               got through
                        time
```

### Example: 2026-07-29 bug with all three layers active

**Scenario:** A developer accidentally removes the RFC 2047 encoding from Subject.

**Layer 3 catches it first (at write time):**

- Developer runs `bun test`
- Test "REGRESSION: an em dash subject survives..." fails
- Developer sees: "Charting update — privacy matter" != "Charting update â€" privacy matter"
- Change is rolled back before it even reaches `git push`

**If Layer 3 somehow missed it (and it got deployed):**

**Layer 2 catches it (at draft-build time):**

- User runs `/chart-from-dictation ...`
- `validateMimeBeforeUpload()` decodes what we built
- Detects: encoded Subject != original Subject
- Throws error before API call: "LAYER 2 VALIDATION FAILED: Subject encoding broken"
- Draft never reaches Gmail

**If Layers 2 and 3 somehow missed it:**

**Layer 1 catches it (at Gmail's doorstep):**

- Draft is uploaded
- Layer 1 reads it back: `GET /drafts/{createdDraftId}`
- Gmail returns mojibake (because raw UTF-8 was interpreted as Latin-1)
- Decoding fails: "Charting update — privacy matter" != "Charting update â€" privacy matter"
- Script exits non-zero: "LAYER 1 VERIFICATION FAILED..."
- Operator investigates
- Draft exists in Gmail for inspection, not in production

---

## Cost-Benefit Summary

| Layer | Cost                             | Benefit                                  | Catches                                                    |
| ----- | -------------------------------- | ---------------------------------------- | ---------------------------------------------------------- |
| **1** | ~200ms per draft (one API GET)   | Detects ANY encoding mismatch            | Runtime encoding errors, Gmail bugs, network corruption    |
| **2** | ~1ms per draft (string parsing)  | Prevents bad data leaving this machine   | Encoder bugs, MIME construction errors                     |
| **3** | ~10ms at write time (test suite) | Documents intent, regression-proofs code | Typos, thoughtless refactors, "I forgot the RFC 2047 line" |

**Total cost per draft:** ~201ms (Layer 1 dominates; Layer 2 is negligible; Layer 3 is dev-time only)

**Benefit:** Mojibake NEVER reaches clients' inboxes.

---

## Maintenance

- **Layer 1:** No changes needed. The function lives in `gmail-draft.ts` and is called unconditionally.
- **Layer 2:** To be implemented in `gmail-draft.ts` (recommended: ~40 lines of MIME parsing).
- **Layer 3:** Update `gmail-draft.test.ts` whenever RFC 2047 or MIME encoding logic changes. Add a test for the new behavior.

---

## References

- RFC 5322 (Internet Message Format) — headers are 7-bit ASCII only
- RFC 2047 (MIME Header Extensions) — how to encode non-ASCII in headers
- RFC 2045-2049 (MIME Parts One through Five) — multipart/alternative structure
- Original regression report: project-a issue #51 (2026-07-29)
- encoder location: `gmail-draft.ts:134-157`
- MIME builder location: `gmail-draft.ts:172-196`
