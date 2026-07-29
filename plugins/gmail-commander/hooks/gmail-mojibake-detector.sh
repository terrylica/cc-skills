#!/usr/bin/env bash
# gmail-mojibake-detector — LAYER 2: detect RFC 5322 Subject/body mojibake before sending.
#
# PURPOSE (regression 2026-07-29, symptom-detection layer):
# Block a draft write whose Subject or body already contains UTF-8-read-as-Latin-1 signatures.
# The corruption happened BEFORE the builder (e.g. caller read a file with the wrong encoding,
# or pasted corrupted text into the file argument), and this hook is a cheap SYMPTOM-DETECTION
# backstop — not a substitute for Layer 1 (the canonical builder's RFC 2047 encoding).
#
# WHAT THIS CATCHES:
# Classic UTF-8 byte sequences, when misinterpreted as Latin-1, produce distinctive character
# pairs nobody types intentionally:
#   - em dash (UTF-8: e2 80 94) → "â€"
#   - left/right curly quotes (e2 80 9c/e2 80 9d) → "â€œ" / "â€"
#   - single curly quotes (e2 80 98/e2 80 99) → "â€˜" / "â€™"
#   - accented letters: é (c3 a9) → "Ã©", è (c3 a8) → "Ã¨", ü (c3 bc) → "Ã¼", ñ (c3 b1) → "Ã±"
#   - Unicode spaces: no-break space (c2 a0) → "Â " (before punctuation, diagnostic)
#   - copyright, pound: © (c2 a9) → "Â©", £ (c2 a3) → "Â£"
#
# LIMITATIONS (be precise about what this layer does):
# - Detects SYMPTOMS already present, not ROOT CAUSES (encoding errors at write time).
# - Only knows corruptions already seen in this repo (em dash, curly quotes, accented vowels).
# - Future corruptions are invisible until added here.
# - Will false-positive on any message that QUOTES mojibake while discussing it (e.g. this
#   repo's own documentation). Escape hatch exists.
# - Complementary to Layer 1 (the builder's RFC 2047 encoding, which PREVENTS these from
#   being created by the builder), and Layer 3 (canonical text sources). This layer is
#   cheap insurance for data that arrives pre-corrupted.
#
# FAIL-OPEN POLICY:
# Parse errors or file-reading failures are advisory infrastructure — never fail the
# session. Limit checks to a reasonable size (first 50KB); huge files should pass.
#
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null || true)

[ -z "$CMD" ] && exit 0

# Escape hatch: allow deliberate mojibake in a message being discussed/quoted.
if printf '%s' "$CMD" | grep -q 'GMAIL_MOJIBAKE_OK=1'; then
  exit 0
fi

# Only check drafts-API calls (same scope as the existing guard).
if ! printf '%s' "$CMD" | grep -qE 'users/me/drafts|gmail\.googleapis\.com[^ ]*draft'; then
  exit 0
fi

# Extract the Subject from the command's --subject flag, if present.
# The --body flag points to a file we can read; --subject is inline in the command.
# This regex is deliberately lenient (fail-open on parse errors).
SUBJECT=$(printf '%s' "$CMD" | grep -oE "\-\-subject '[^']*'" | head -1 | sed "s/^--subject '//" | sed "s/'$//" || true)

# WHAT MOJIBAKE ACTUALLY LOOKS LIKE IN BYTES — the first version of this hook had it exactly
# backwards, and would have blocked every correct message while passing every corrupt one.
#
#   legitimate em dash "—"            = e2 80 94        <-- CORRECT text. Must NOT be blocked.
#   that em dash, mis-decoded as
#   Latin-1 and re-encoded as UTF-8   = c3 a2 c2 80 c2 94   <-- MOJIBAKE. This is the target.
#
# The earlier rule matched `e2 80`, i.e. the legitimate character, on the stated premise that
# "E2 80 XX never appears in legitimate UTF-8" — which is false: e2 80 94 IS the em dash, and it
# appears in most prose this repo sends. Verified 2026-07-29 by hashing both forms.
#
# The real signature is the UTF-8 encoding of the Latin-1 misreading: a `c3 a2` (â) or `c3 83` (Ã)
# followed by another C2/C3 continuation. Those pairs are vanishingly rare in genuine text and are
# the fingerprint of a double-encode.
if [ -n "$SUBJECT" ]; then
  OD_OUT=$(printf '%s' "$SUBJECT" | od -An -tx1 2>/dev/null || echo "")
  if printf '%s' "$OD_OUT" | grep -qE 'c3[[:space:]]+a2[[:space:]]+c2|c3[[:space:]]+83[[:space:]]+c2'; then
    cat >&2 <<'MSG'
BLOCKED: subject contains UTF-8-read-as-Latin-1 mojibake (e.g. "â€"" for em dash).

This usually means the source text was read with the wrong encoding, pasted from a
misconfigured editor, or corrupted in transit. The Gmail draft builder uses RFC 2047
encoding to PREVENT this, so if you are using the builder, the corruption is upstream.

Examples of mojibake signatures:
  - â€– (em dash)
  - Ã©, Ã¨, Ã¼, Ã± (accented letters)
  - Â (no-break space or symbol)

CHECK:
  1. Verify your text editor is UTF-8 (not Latin-1, CP1252, or ISO-8859-1).
  2. If pasting from another source, paste into a clean UTF-8 file first.
  3. If you are deliberately quoting mojibake (e.g. in a bug report), use the escape
     hatch: prefix your command with GMAIL_MOJIBAKE_OK=1.

Escape hatch (auditable):
  GMAIL_MOJIBAKE_OK=1 bun ... (your command)
MSG
    exit 2
  fi
fi

# If a body file was specified, spot-check the first 50KB for mojibake patterns.
# Don't read huge files; advisory guards are cheap, not exhaustive.
BODY_FILE=$(printf '%s' "$CMD" | grep -oE "\-\-body [^ ]+" | awk '{print $2}' || true)
if [ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ]; then
  BODY_HEAD=$(head -c 51200 "$BODY_FILE" 2>/dev/null || true)
  OD_BODY=$(printf '%s' "$BODY_HEAD" | od -An -tx1 2>/dev/null || echo "")
  if printf '%s' "$OD_BODY" | grep -qE 'c3[[:space:]]+a2[[:space:]]+c2|c3[[:space:]]+83[[:space:]]+c2'; then
    cat >&2 <<'MSG'
BLOCKED: body file contains UTF-8-read-as-Latin-1 mojibake.

(First 50KB checked; if the file is much larger, the patterns may exist further down.)

Escape hatch (auditable):
  GMAIL_MOJIBAKE_OK=1 bun ... (your command)
MSG
    exit 2
  fi
fi

exit 0
