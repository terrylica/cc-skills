# Gmail Draft Builder Hardening — Three Defense Layers

**Date**: 2026-07-29 | **Regression**: em-dash subjects rendered as mojibake | **Fix commit**: 545ed863

## Context

A draft sent to the client had its Subject rendered as:

```
"Charting update â€" privacy matter, Mallampati fix, word list, ..."
```

**Root cause**: RFC 5322 headers are 7-bit ASCII only. The Subject was interpolated raw, so the UTF-8 bytes of an em dash (U+2014 = `e2 80 94`) travelled unlabeled and Gmail rendered them as Latin-1 (`â`, `€`, `"` — three characters for one).

**Immediate fix** (commit 545ed863): RFC 2047-encode non-ASCII header values in `buildMime()` and guard the module with `import.meta.main` so functions can be imported for testing.

**This adds three ADDITIONAL independent defense layers** — each catches a different failure mode, none is a substitute for another, and all three prevent shipping the same bug again:

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

## Why Three Layers?

Each layer catches different failure modes:

| Layer | Catches              | Example Failure                                                                                          |
| ----- | -------------------- | -------------------------------------------------------------------------------------------------------- |
| 2     | Function unreachable | `export function encodeHeaderValueAsRfc2047EncodedWordIfNonAscii() { ... }` cannot be imported or tested |
| 3     | Broken test suite    | Test file syntax error, test deleted, test logic wrong; guard rejects all drafts                         |
| 4     | Encoding logic error | RFC 2047 encoder produces invalid output; smoke test catches it before any draft ships                   |

**Together**: If encoder breaks → Layer 4 test catches it → Layer 3 guard prevents draft → Layer 2 makes Layer 4 possible.

**None is a substitute for another**: All three are defense-in-depth.

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
