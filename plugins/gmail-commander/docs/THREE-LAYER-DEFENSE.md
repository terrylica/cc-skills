# Gmail Draft Builder Hardening — Three-Layer Defense

## Executive Summary

This document describes the three independent hardening layers added to the Gmail draft builder after the 2026-07-29 mojibake regression (Subject line rendered as "Charting update â€" privacy matter" instead of the proper em dash).

**Status:**

- ✅ **LAYER 2** — Mojibake Pattern Detector (COMPLETE, tested, deployed)
- 🔲 **LAYER 3** — Subject-Canonical Validator (designed, pending implementation)
- 🔲 **LAYER 4** — Round-Trip Verification (designed, pending implementation)

---

## Why Three Layers?

The 2026-07-23 hard-fold bug and 2026-07-29 mojibake bug revealed that **fixing one message surface proves nothing about its siblings**. A message has multiple independently-encoded parts (Subject/body, plain/HTML, headers/body), and a fix in one part may leave others unprotected.

The three layers are:

1. **LAYER 2 (Symptom Detection):** Catch mojibake that arrived pre-corrupted
2. **LAYER 3 (Input Validation):** Ensure Subject comes from canonical, vetted sources
3. **LAYER 4 (Output Verification):** Round-trip the saved draft to prove it renders correctly

None is a substitute for the others. Each catches different failure modes.

---

## LAYER 2 — Mojibake Pattern Detector ✅

**File:** `hooks/gmail-mojibake-detector.sh`  
**Type:** PreToolUse Bash hook (runs on every drafts-API command)  
**Signal:** Byte-sequence detection (E2 80 XX patterns)  
**Escape Hatch:** `GMAIL_MOJIBAKE_OK=1`

### What It Catches

- UTF-8 byte sequences (E2 80 94, etc.) that appear where they shouldn't
- Corruptions that happened BEFORE the builder (file encoding, paste, transit)

### What It Cannot Catch

- Root cause (Layer 1 builder encoding prevents creation)
- Garbage input (Layer 3 canonical sources prevent injection)
- Silent rendering errors (Layer 4 round-trip verification proves correctness)

### Proofs (Tested ✓)

- ✓ Mojibake em dash in body file → BLOCKED
- ✓ Clean UTF-8 body (café, naïve) → PASSED
- ✓ Escape hatch bypasses check → PASSED
- ✓ Non-drafts commands pass through → PASSED

### Documentation

- `hooks/LAYER2-MOJIBAKE-DETECTOR.md` — full guide
- `hooks/gmail-mojibake-detector.sh` — implementation

---

## LAYER 3 — Subject-Canonical Validator 🔲

**Proposed File:** `hooks/gmail-subject-canonical-validator.sh`  
**Type:** PreToolUse Bash hook  
**Signal:** Whitelist-based (Subject must come from explicitly-blessed sources)

### Design

Subject lines for client communications MUST originate from one of these canonical sources:

1. **Typeless-transcribed** (chairside dictation via `/chart-from-dictation`)
   - Signal: `--reply-to` flag points to a Typeless-generated message
   - Proof: Message metadata includes Typeless source attribution

2. **Pre-approved message templates** (e.g., "Update - privacy matter")
   - Signal: `--subject` value exactly matches an entry in `scripts/approved-subjects.json`
   - Proof: Audit log shows template was reviewed before deployment

3. **Reply threading** (re: existing message)
   - Signal: `--reply-to` flag is present; Subject is auto-derived by the builder from the original
   - Proof: Builder code (line 219 in `scripts/gmail-draft.ts`) shows derivation logic is deterministic

4. **Operator-explicit override** (rare, auditable)
   - Signal: `--subject` + `GMAIL_SUBJECT_OVERRIDE=1` prefix
   - Proof: Escape hatch in command and git history

### Why This Matters

The 2026-07-29 mojibake was sourced from a Subject that was:

- Typed directly into a `--subject` flag
- NOT validated against canonical sources
- Written by the operator in an IDE with the wrong encoding setting

A Subject canonicalization layer prevents operator typos and encoding issues at the SOURCE.

### Implementation Sketch

```bash
# Pseudocode: LAYER 3 validator

SUBJECT=$(extract_subject_from_command "$CMD")

# Case 1: Reply-to (auto-derived by builder, skip validation)
if has_reply_to "$CMD"; then
  exit 0
fi

# Case 2: Whitelist check
if subject_in_whitelist "$SUBJECT" "$APPROVED_LIST"; then
  exit 0
fi

# Case 3: Explicit override
if has_override_flag "$CMD"; then
  log_audit "operator override used"
  exit 0
fi

# Case 4: Reject
echo "Subject not canonical. Use --reply-to or whitelist."
exit 2
```

### Proofs (To Be Implemented)

- [ ] Reply-to subjects pass through unchanged
- [ ] Whitelisted subjects pass
- [ ] Non-whitelisted subjects BLOCK with guidance
- [ ] Override flag bypasses whitelist
- [ ] Non-drafts commands pass through

### Open Questions

1. Should the whitelist live in git (version-controlled) or in a mutable config?
   - **Proposal:** Git (matches docstring doctrine). Update via commit + review.

2. How to auto-detect Typeless-sourced Subjects?
   - **Proposal:** Check `--reply-to` message metadata for Typeless sender

3. Should operator override be rare/discouraged or common/documented?
   - **Proposal:** Rare + auditable. Log to a ledger; review in incident post-mortems.

---

## LAYER 4 — Round-Trip Verification 🔲

**Proposed File:** `scripts/gmail-draft-verify.ts` (new CLI tool)  
**Type:** Post-build verification (called after `gmail-draft.ts` creates a draft)  
**Signal:** Fetch the saved draft from Gmail, re-render locally, compare structure

### Design

After a draft is created and uploaded to Gmail:

1. **Fetch** the draft from Gmail's API
2. **Parse** its Subject, body, and MIME structure
3. **Check** that Subject is intact (not mojibaked, not mangled)
4. **Verify** body parts (plain + HTML) are both present and valid UTF-8
5. **Re-render** the draft in Gmail's Compose UI (via headless browser if needed) and take a screenshot
6. **Compare** the rendered output to the source text (check for hard-folds, encoding issues, etc.)

### Why This Matters

Gmail's ingestion pipeline re-encodes messages in ways that are hard to predict:

- 2026-07-23: text/plain → hard-fold at ~72 cols
- 2026-07-29: Subject header → UTF-8 bytes read as Latin-1

A round-trip verification catches silent rendering failures that neither Layer 2 nor Layer 3 can detect.

### Implementation Sketch

```typescript
// Pseudocode: LAYER 4 verification

const draft = await fetchDraftFromGmail(draftId, accessToken);
const mimeMessage = decodeMimeMessage(draft.message.raw);

// Check 1: Subject integrity
if (mojibakeDetected(mimeMessage.headers.subject)) {
  throw new Error("Subject contains mojibake (Layer 2 failed)");
}

// Check 2: MIME structure
if (!mimeMessage.parts.find((p) => p.contentType === "text/plain")) {
  throw new Error("Missing text/plain part");
}
if (!mimeMessage.parts.find((p) => p.contentType === "text/html")) {
  throw new Error("Missing text/html part");
}

// Check 3: Body UTF-8 validity
for (const part of mimeMessage.parts) {
  const decoded = decodeBody(part);
  if (!isValidUtf8(decoded)) {
    throw new Error(`Invalid UTF-8 in ${part.contentType}`);
  }
}

// Check 4: (Optional) Headless render & screenshot
const screenshot = await renderInGmailComposer(accessToken, draftId);
// Compare rendered text to source for hard-folds, etc.

console.log(JSON.stringify({ draftId, verified: true }));
```

### Proofs (To Be Implemented)

- [ ] Round-trip on a clean draft succeeds
- [ ] Round-trip on a mojibaked draft fails with specific error
- [ ] Round-trip on a hard-folded draft detects line breaks
- [ ] Screenshot comparison detects rendering issues
- [ ] Verification output is machine-readable (JSON)

### Open Questions

1. Should verification be mandatory or optional?
   - **Proposal:** Optional by default; mandatory for client-facing messages (flag: `--verify-client-safe`)

2. When should it run? Immediately after create, or async?
   - **Proposal:** Immediately after (blocks draft creation if verification fails). Async monitoring possible later.

3. How to detect hard-folds programmatically?
   - **Proposal:** Fetch body, check for unwanted line breaks within paragraphs (regex pattern matching soft-wrapped lines)

---

## Implementation Roadmap

### Phase 1: LAYER 2 Deployment ✅

- [x] Write hook script
- [x] Register in hooks.json
- [x] Write unit tests (manual proofs)
- [x] Document design + proofs
- [x] Deploy to client

### Phase 2: LAYER 3 Whitelist Validator 🚧

- [ ] Design approved-subjects list (git-tracked, reviewed updates)
- [ ] Write hook script with whitelist check
- [ ] Auto-detect Typeless-sourced subjects (optional, may require metadata)
- [ ] Implement override escape hatch with audit logging
- [ ] Write proofs and documentation
- [ ] Deploy to client

### Phase 3: LAYER 4 Round-Trip Verification 🚧

- [ ] Write `gmail-draft-verify.ts` CLI tool
- [ ] Implement MIME parsing + Subject integrity check
- [ ] Implement UTF-8 validation
- [ ] (Optional) Implement headless render check
- [ ] Integrate into CI/CD or optional post-hook
- [ ] Write proofs and documentation

---

## Incident Chronicle

| Date       | Incident                                   | Layer Response                                             | Status     |
| ---------- | ------------------------------------------ | ---------------------------------------------------------- | ---------- |
| 2026-07-23 | Hard-fold (text/plain wrapped at ~72 cols) | Layer 1: Added RFC 2047 encoding to subject                | ✓ Fixed    |
| 2026-07-29 | Mojibake (Subject bytes read as Latin-1)   | Layer 2: Mojibake pattern detector                         | ✓ Fixed    |
| Future     | Unknown failure mode                       | Layer 3 + 4: Catch data-source and output-rendering issues | 🚧 Planned |

---

## Related Docstring

- **Doctrine:** `docs/three-layer-defense.md` (project-a project)
- **No ad-hoc fixes:** All corrections become universal rules, never hand-edits
- **RFC 2047 encoder:** `scripts/gmail-draft.ts:encodeHeaderValueAsRfc2047EncodedWordIfNonAscii()`
- **Tests:** `scripts/gmail-draft.test.ts`

---

## Glossary

- **Mojibake:** UTF-8 text misinterpreted as Latin-1 (or vice versa), producing corruption
- **Hard-fold:** Forced line breaks inserted by Gmail's ingestion pipeline
- **Canonical:** Vetted, approved, version-controlled source of truth
- **Round-trip:** Encode → send → receive → decode → verify
- **Escape hatch:** Deliberately auditable override for rare exceptions
