# LAYER 2 — Mojibake Pattern Detector Hook

## Overview

**File:** `hooks/gmail-mojibake-detector.sh`  
**Registration:** `hooks.json` (PreToolUse Bash)  
**Regression:** 2026-07-29 (Subject line rendered as "â€"" instead of "—" in client inbox)  
**Purpose:** Detect and block Gmail draft writes whose Subject or body contains UTF-8-read-as-Latin-1 mojibake signatures before they ship to the client.

---

## What This Layer Catches

Mojibake appears when UTF-8 byte sequences appear in text that should be properly encoded. The characteristic signatures from the 2026-07-29 incident:

- **Em dash (—)**: UTF-8 bytes `E2 80 94` that misinterpret as Latin-1 → rendered as "â€""
- **Curly quotes (" ")**: UTF-8 `E2 80 9C`/`E2 80 9D` → rendered as "â€œ" / "â€""

This hook specifically detects the presence of **raw UTF-8 byte sequences** (`E2 80 XX`) that should never appear in legitimate UTF-8 text.

---

## What This Layer Cannot Catch

- **Root cause (Layer 1 responsibility):** The builder's RFC 2047 header encoding prevents mojibake from being created by the builder itself.
- **Source validation (Layer 3 responsibility):** Canonical text sources (Typeless, approved message templates) prevent garbage from entering the pipeline.
- **False positives:** Any message that legitimately quotes mojibake while discussing this bug (e.g., this doc) will trigger the detector. Escape hatch provides an override.
- **Unknown mojibake patterns:** The detector only recognizes byte sequences already seen. Future mojibake types must be added manually.

---

## How It Works

### Detection Strategy

The hook uses `od` to convert file/subject contents to hex and matches specific byte sequences:

```bash
# Detect E2 80 XX (the key em dash/quote mojibake signature)
printf '%s' "$SUBJECT" | od -An -tx1 2>/dev/null | grep 'e2\s\+80'
```

This avoids false positives from legitimate UTF-8 (e.g., "café" which is `C3 A9`, not `E2 80 XX`).

### Scope

- **When:** PreToolUse hook triggers on Bash commands
- **Where:** Filters drafts-API calls (same scope as Layer 1 guard)
- **What:** Checks Subject line (extracted from `--subject` flag) and body file (first 50KB via `--body` flag)

### Fail-Open Policy

Parse errors, file-reading failures, and large files pass through; advisory infrastructure never wedges the session.

---

## Escape Hatch

For legitimate use cases (quoting mojibake in documentation, testing, etc.):

```bash
GMAIL_MOJIBAKE_OK=1 bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts ...
```

The escape hatch is auditable in git history and logs.

---

## Proofs

### Proof 1: Mojibake em dash BLOCKED

```
File: E2 80 94 20 70 72 69 76 61 63 79  (em dash bytes)
Result: ✓ BLOCKED (exit 2)
```

### Proof 2: Clean UTF-8 PASSED

```
File: 43 61 66 C3 A9  (café in UTF-8, no E2 80 sequence)
Result: ✓ PASSED (exit 0)
```

### Proof 3: Escape hatch works

```
Command: GMAIL_MOJIBAKE_OK=1 bun ...
File: E2 80 94 (mojibake em dash)
Result: ✓ PASSED (hatch honored, exit 0)
```

### Proof 4: Non-drafts pass through

```
Command: curl https://example.com
Result: ✓ PASSED (no drafts-API, exit 0)
```

---

## Layer Hierarchy

This is the **second of three defense layers:**

| Layer       | Owner-Mindset     | Implementation                                | Signal                                 |
| ----------- | ----------------- | --------------------------------------------- | -------------------------------------- |
| **Layer 1** | Builder           | RFC 2047 encoding in `scripts/gmail-draft.ts` | PREVENT mojibake at creation time      |
| **Layer 2** | Guard (this file) | Byte-sequence pattern matching                | DETECT mojibake before send            |
| **Layer 3** | Source            | Canonical text inputs (Typeless, templates)   | PREVENT garbage from entering pipeline |

Each layer is independent; none is a substitute for the others.

---

## Maintenance

### Adding New Mojibake Patterns

If a new corruption pattern is discovered:

1. Document it in the "WHAT THIS CATCHES" section with UTF-8 bytes and Latin-1 rendering
2. Add the byte pattern to the grep regex: `'e2\s\+80|...'`
3. Add a test to `../scripts/gmail-draft.test.ts` (if applicable)
4. Update this doc with the new proof

### Monitoring

- Check hook logs if mojibake unexpectedly passes through
- Review escape-hatch usage (`git log --grep="GMAIL_MOJIBAKE_OK=1"`)
- Track false positives from legitimate messages quoting mojibake

---

## Related

- **Layer 1 (RFC 2047 encoding):** `scripts/gmail-draft.ts:encodeHeaderValueAsRfc2047EncodedWordIfNonAscii()`
- **Test suite:** `scripts/gmail-draft.test.ts` (header encoding regression tests)
- **Incident report:** 2026-07-29, subject shipped as "Charting update â€" privacy matter..."
- **No-adhoc-fix doctrine:** `docs/three-layer-defense.md`
