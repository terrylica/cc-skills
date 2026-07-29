# Gmail Draft Builder Hardening — Five Defense Layers

**Date**: 2026-07-29 | **Regression**: em-dash subjects rendered as mojibake | **Fix commit**: 545ed863

## Context

A draft sent to the client had its Subject rendered as:

```
"Charting update â€" privacy matter, Mallampati fix, word list, ..."
```

**Root cause**: RFC 5322 headers are 7-bit ASCII only. The Subject was interpolated raw, so the UTF-8 bytes of an em dash (U+2014 = `e2 80 94`) travelled unlabeled and Gmail rendered them as Latin-1 (`â`, `€`, `"` — three characters for one).

**Comprehensive defense**: The builder now has **five independent defense layers** that catch encoding regressions at different stages. Each catches a different failure mode; none is a substitute for another:

1. **LAYER 0** (function level): RFC 2047-encode non-ASCII headers in `buildMime()` — prevents raw UTF-8 from leaving the encoder.
2. **LAYER 2** (pre-upload): Validate MIME structure and Subject round-trip before sending — catches encoder bugs locally.
3. **LAYER 1** (post-upload): Read the draft back from Gmail and verify it matches what was sent — catches transmission/API errors.
4. **LAYER 3** (guard level): Test-gate hook blocks drafts when tests fail — prevents shipping broken builder.
5. **LAYER 4** (test level): Unit tests + MIME round-trip smoke test — ensures encoder functions are tested and correct.

---

## LAYER 0 — RFC 2047 Header Encoding

**File**: `scripts/gmail-draft.ts:encodeHeaderValueAsRfc2047EncodedWordIfNonAscii()`

**What it does**: Encodes non-ASCII header values (like a Subject with an em dash) into RFC 2047 base64 encoded-words before building the MIME message.

**Why it matters**: RFC 5322 prohibits non-ASCII bytes in headers. Without this, UTF-8 bytes travel raw and get misinterpreted as Latin-1 by mail clients. This is the root cause of the 2026-07-29 mojibake.

**How it works**:

1. Detects if a header value contains non-ASCII (byte length ≠ string length).
2. If pure ASCII, leaves it untouched (readable in logs/diffs).
3. If non-ASCII, base64-encodes the UTF-8 bytes and wraps them in `=?UTF-8?B?...?=` markers.
4. Chunks long values into multiple encoded-words (RFC 2047 limit: 75 chars each).
5. Adjacent encoded-words are joined with spaces (RFC 2047 specifies whitespace as non-significant).

**Applied to**: `Subject` header only (Address headers like `From` are deliberately excluded; they need a real address parser).

---

## LAYER 2 — Pre-Upload MIME Validation

**File**: `scripts/gmail-draft.ts:validateMimeBeforeUpload()`

**What it does**: Before uploading to Gmail, validates that the MIME message we're about to send can round-trip correctly:

- Subject header round-trips (if non-ASCII, verifies RFC 2047 encoding decodes to the original).
- MIME structure is well-formed (boundary present, multipart/alternative declared).

**Why it matters**: LAYER 0 encodes the Subject, but does the encoding work? This layer catches encoder bugs before they leave the machine (no wasted API call, no stale draft).

**How it works**:

1. Parses the raw MIME string to extract headers and detect MIME structure.
2. Decodes the Subject header (if RFC 2047 encoded) and asserts it matches the original subject.
3. Verifies the MIME boundary is present and correctly formatted.

**Fails-loud**: Exits non-zero with a detailed error if validation fails. The error names the specific header or structure that broke.

---

## LAYER 1 — Post-Upload Round-Trip Verification

**File**: `scripts/gmail-draft.ts:assertCreatedDraftMatchesWhatWeSent()`

**What it does**: After creating the draft on Gmail, immediately reads it back via `GET /drafts/{draftId}?format=full` and asserts that what Gmail returns matches what we sent.

**Why it matters**: LAYER 2 validates what we're about to send, but transmission or Gmail's own re-encoding can corrupt it. This layer checks the final result.

**How it works**:

1. Fetches the newly created draft with full MIME details (format=full).
2. Extracts the Subject header from Gmail's response.
3. Decodes it (RFC 2047 decoding is idempotent on raw ASCII).
4. Asserts it matches the original subject exactly.
5. Checks that the multipart structure is intact (text/plain part is present and non-empty).

**Fails-loud**: Exits non-zero and reports the full chain (input → sent → received → decoded) so you can see exactly where the corruption happened.

---

## LAYER 3 — Test-Gate Guard Hook

**File**: `hooks/gmail-draft-guard.sh`

**What it does**: Before permitting a draft write via the canonical builder (`scripts/gmail-draft.ts`), runs the builder's test suite (`scripts/gmail-draft.test.ts`) and REJECTS if tests fail.

**Why it matters**: The 2026-07-29 bug shipped because the RFC 2047 encoding function had **zero test coverage**. The function could not even be imported (the module exited at import time), so nobody could test it. The guard detects when the builder is unhealthy.

**How it works**:

1. **Parses incoming Claude Code command** (JSON hook input) and extracts the `command` field.
2. **Detects canonical tool** (pattern match on `scripts/gmail-draft.ts`).
3. **Calls `verify_builder_health()`** to gate the draft write:
   - Checks if test file and bun runner exist.
   - Runs `bun test scripts/gmail-draft.test.ts`.
   - **Fails-closed** if tests fail or runner is missing (blocking all mail is better than shipping broken code).
4. **Caches the result** keyed on builder file mtime:
   - **Performance**: batch operations don't re-run tests per draft.
   - **Freshness**: if the builder changes, cache invalidates automatically.
5. **Escape hatch**: `GMAIL_DRAFT_TEST_GATE_SKIP=1` for debugging (use only when you know the builder is healthy).

**Test scenario (PROOF OF CONCEPT)**:

```bash
# Healthy state: guard allows draft
echo '{"tool_input":{"command":"bun ~/.../scripts/gmail-draft.ts ..."}}' \
  | bash hooks/gmail-draft-guard.sh && echo "PASS" || echo "FAIL"

# Break the test file
sed -i.bak 's/expect(encoded).not.toBe/expect(false).toBe/' scripts/gmail-draft.test.ts

# Guard rejects the draft
echo '{"tool_input":{"command":"bun ~/.../scripts/gmail-draft.ts ..."}}' \
  | bash hooks/gmail-draft-guard.sh 2>&1 | grep "LAYER 3 GATE FAILED"

# Restore and guard allows again
mv scripts/gmail-draft.test.ts.bak scripts/gmail-draft.test.ts
echo '{"tool_input":{"command":"bun ~/.../scripts/gmail-draft.ts ..."}}' \
  | bash hooks/gmail-draft-guard.sh && echo "PASS" || echo "FAIL"
```

**Cache location**: `~/.claude/.cache/gmail-draft-builder-test.cache` (JSON: `{mtime, result}`).

---

## LAYER 4 — MIME Round-Trip Smoke Test

**File**: `scripts/gmail-draft.test.ts`

**What it does**: Adds a test (`LAYER 4: a MIME message with non-ASCII Subject round-trips correctly`) that simulates the exact MIME-building flow with a non-ASCII Subject, then verifies the Subject header survives RFC 2047 encoding → decoding.

**Why it matters**: LAYER 3 catches a broken test suite. LAYER 4 catches encoding logic errors even if tests run. The test is a smoke check of the exact headers + encoding path the builder uses in production.

**What it tests**:

1. Builds a realistic message headers block with a non-ASCII Subject (em dash).
2. Encodes the Subject using `encodeHeaderValueAsRfc2047EncodedWordIfNonAscii()`.
3. Extracts the encoded Subject from the MIME header block.
4. Decodes it back to the original.
5. **Asserts**: decoded Subject equals the original (bit-exact).

**Related tests**:

- "REGRESSION: an em dash subject survives instead of becoming mojibake" — the exact subject that broke on 2026-07-29.
- "every emitted encoded-word stays within the RFC 2047 75-character limit" — prevents silent mangling by strict parsers.
- "a multi-byte character split across two encoded-words still reassembles" — validates chunking boundary handling.

**Run locally**:

```bash
bun test scripts/gmail-draft.test.ts
# All 5 tests must pass; expected: 13 expect() calls, 0 failures
```

---

## LAYER 2 (Prerequisite) — Module Import Guard

**File**: `scripts/gmail-draft.ts`

**What it does**: Wraps the main execution logic in `if (import.meta.main)` so the module can be imported for testing without running `parseArgs()` and exiting.

**Why it matters**: Before this, importing the module to test `encodeHeaderValueAsRfc2047EncodedWordIfNonAscii()` would fail. The function had **zero** test coverage because it was unreachable. This gate enables testing of individual functions.

**Status**: Already fixed in commit 545ed863.

---

## Why Five Layers?

Each layer catches different failure modes; together they prevent the same bug from shipping:

| Layer | Mechanism                | Catches                 | Example Failure                                                     |
| ----- | ------------------------ | ----------------------- | ------------------------------------------------------------------- |
| 0     | Function                 | Raw UTF-8 in headers    | Subject header not encoded → Gmail mojibake                         |
| 2     | Pre-upload validation    | Encoder bugs (local)    | RFC 2047 encoder produces invalid output → detected before API call |
| 1     | Post-upload verification | Transmission/API errors | Gmail corrupts the message in transit → detected before using draft |
| 3     | Guard hook               | Broken builder          | Test file broken or deleted → guard rejects all drafts              |
| 4     | Test coverage            | Uncovered code paths    | Encoder function unreachable → test suite catches changes           |

**Defense-in-depth**: Each layer is independent. A failure in one doesn't weaken the others.

**The seal**: LAYER 0 encodes the Subject → LAYER 2 validates it locally → LAYER 1 verifies it survived → LAYER 3 prevents broken code shipping → LAYER 4 keeps encoder tested.

---

## Escape Hatches

| Layer | Escape                         | When to Use                                              | Risk                                           |
| ----- | ------------------------------ | -------------------------------------------------------- | ---------------------------------------------- |
| 3     | `GMAIL_DRAFT_TEST_GATE_SKIP=1` | Bun is broken, tests won't run but builder is known-good | **High** — silently allows broken code         |
| 1     | `GMAIL_DRAFT_ADHOC_OK=1`       | You're intentionally testing ad-hoc drafts               | **High** — reproduces the hard-fold regression |

**Use neither except for debugging.** Most uses indicate a real bug.

---

## Operational Notes

- **Performance**: First draft write runs tests (~10–15 ms). Subsequent writes use cache until builder file changes (mtime). Batch operations scale.
- **Fail-closed policy**: If bun is missing or test file is missing, LAYER 3 blocks all drafts. This is intentional — a misconfiguration is better caught than silently worked around.
- **No logging of personal data**: Guard output never prints message bodies, tokens, or email addresses. Cache is machine-readable JSON only.

---

## Files Modified

- `hooks/gmail-draft-guard.sh`: Added LAYER 3 test-gate + caching.
- `scripts/gmail-draft.test.ts`: Added LAYER 4 MIME round-trip smoke test.
- `scripts/gmail-draft.ts`: Already guarded with `import.meta.main` (commit 545ed863).

---

## Verification

Run the proofs:

```bash
# All tests pass
bun test plugins/gmail-commander/scripts/gmail-draft.test.ts

# Guard allows healthy builder
echo '{"tool_input":{"command":"bun ~/.../gmail-draft.ts ..."}}' \
  | bash plugins/gmail-commander/hooks/gmail-draft-guard.sh && echo PASS

# (See LAYER 3 section above for break/restore proof)
```
