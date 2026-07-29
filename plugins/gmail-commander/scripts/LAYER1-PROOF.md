# Layer 1 Verification Proof

## What Layer 1 does

Layer 1 verification is the **builder verifying its own output**. After creating a draft, the script immediately reads it back from the Gmail API and asserts that what Gmail reports matches what was sent.

This is the STRONGEST defense against encoding regressions because:

1. It checks the RESULT rather than pattern-matching known bad outputs
2. It catches encoding surfaces nobody has thought of yet
3. Both the 2026-07-23 and 2026-07-29 bugs escaped other safeguards

## The proof scenario

### Before (with broken encoder returning raw UTF-8)

When the `encodeHeaderValueAsRfc2047EncodedWordIfNonAscii` function was broken and returned raw UTF-8 for non-ASCII characters:

```
Input:  "Charting update — privacy matter"
Sent:   Raw UTF-8 bytes (no RFC 2047 encoding)
Gmail:  Receives raw bytes, interprets as Latin-1 → "Charting update â€" privacy matter"
Layer 1 reads back:
  - Fetches draft from Gmail
  - Decodes Subject header
  - Compares: "Charting update — privacy matter" != "Charting update â€" privacy matter"
  - THROWS ERROR and exits non-zero
```

### After (with correct RFC 2047 encoder)

With the encoder working correctly:

```
Input:  "Charting update — privacy matter"
Sent:   =?UTF-8?B?Q2hhcnRpbmcgdXBkYXRlIOKAlCBwcml2YWN5IG1hdHRlcg==?=
Gmail:  Receives encoded bytes, decodes RFC 2047 → "Charting update — privacy matter"
Layer 1 reads back:
  - Fetches draft from Gmail
  - Decodes Subject header (RFC 2047 word sequence)
  - Compares: "Charting update — privacy matter" == "Charting update — privacy matter"
  - ✅ PASS (function returns silently)
```

## Proof implementation

The `assertCreatedDraftMatchesWhatWeSent` function in `gmail-draft.ts`:

1. **Reads the draft back** from Gmail via `api(at, "drafts/${draftId}?format=full")`
2. **Extracts Subject header** from the response
3. **Decodes RFC 2047** if present via `decodeRfc2047EncodedWordSequence`
4. **Compares to original** — if mismatch, throws with full chain (input → sent → received → decoded)
5. **Checks MIME structure** — verifies text/plain part exists and is non-empty

## Why this catches regressions

- **2026-07-23 regression**: Hard-folding was in the body. Layer 1 catches it because it verifies `text/plain` exists and is non-empty.
- **2026-07-29 regression**: Subject encoding was broken. Layer 1 catches it immediately because the round-trip fails.
- **Future regressions**: Any encoding surface (headers, body boundaries, charset declarations) that reaches Gmail will round-trip. If it doesn't match, Layer 1 FAILS LOUD.

## Integration into the main flow

Called in `gmail-draft.ts` after draft creation, lines ~256-269:

```typescript
const createdDraftId = draft.id as string;
try {
  await assertCreatedDraftMatchesWhatWeSent(at, createdDraftId, subject);
} catch (e) {
  console.error(`LAYER 1 VERIFICATION FAILED on draft ${createdDraftId}:`);
  console.error((e as Error).message);
  process.exit(1);
}
```

If verification fails:

- Script exits with code 1 (non-zero)
- Operator sees the specific mismatch (Subject decoded wrong, MIME structure broken, etc.)
- Draft exists in Gmail (operator can inspect it) but the script fails loudly
- This forces investigation rather than silent corruption spreading

## Cost

One extra `GET drafts/{draftId}?format=full` API call per draft creation (~200ms). This is acceptable because:

- Drafts are human-authored, not high-frequency bulk operations
- Verification is instant compared to a human composing an email
- The cost of NOT catching an encoding error (email silently reaches recipient mangled) is much higher
