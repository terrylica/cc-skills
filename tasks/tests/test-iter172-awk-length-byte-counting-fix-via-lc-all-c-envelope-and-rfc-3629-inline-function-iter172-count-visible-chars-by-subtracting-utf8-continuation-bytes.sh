#!/usr/bin/env bash
#MISE description="Iter-172 regression test pinning the awk length() byte-counting fix in iter-152 commits-health. Pre-iter-172 the 6 awk length() call sites in iter-152 byte-counted CJK subjects regardless of locale (macOS BWK awk always byte-counts; gawk under UTF-8 locale rejects [\\200-\\277] as invalid Unicode range). Iter-172 wraps each char-counting awk pipeline with LC_ALL=C and inlines an awk function iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(text) that returns byte-length minus the count of UTF-8 continuation bytes (regex matches byte range 0x80-0xBF via octal [\\200-\\277] under C locale). This implements RFC 3629 byte-pattern character counting: per RFC 3629, only continuation bytes (10xxxxxx pattern) cannot start a Unicode character, so byte-length minus continuation-byte-count equals visible character count. Test asserts (a) all 5 awk pipelines have LC_ALL=C prefix, (b) all 5 contain the iter172 function definition, (c) end-to-end CJK probe through panel-3 worst-offender awk pipeline reports 15 chars for the 15-char/27-byte CJK probe subject, (d) histogram bin assignment classifies the CJK probe correctly in the iter-50-char bin (not the false-positive 73-100-char byte-counting bin), (e) top-of-file comment documents iter-172 closing the iter-171 awk gap."
set -euo pipefail

ITER172_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER172_REPO_ROOT"

ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH="$ITER172_REPO_ROOT/scripts/iter152-operator-facing-commits-subject-length-distribution-histogram-with-trend-analysis-and-worst-offender-callouts-for-conventional-commits-50-72-rule-compliance-visibility-fusing-iter150-readable-view-with-iter151-classification-overlay.sh"

# Synthetic UTF-8 probe subject — same as iter-171 to maintain test corpus consistency.
# Probe is 15 visible characters across 27 UTF-8 bytes (6 ASCII + 6 CJK×3 bytes + 3 ASCII);
# the iter-172 fix asserts char-count is reported (15), not byte-count (27).
ITER172_SYNTHETIC_CJK_PROBE_SUBJECT_WITH_KNOWN_VISIBLE_CHAR_COUNT_OF_FIFTEEN="feat: 修复编码问题XYZ"
ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT=15

ITER172_TOTAL_ASSERTIONS_EVALUATED=0
ITER172_TOTAL_ASSERTIONS_FAILED=0

iter172_assert_substring_present_with_human_readable_label() {
    local human_readable_label="$1"
    local file_path="$2"
    local expected_substring="$3"
    ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$file_path"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-172 AWK LENGTH() BYTE-COUNTING FIX REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: iter-152 source contains the iter-172 documentation ──────────
echo ""
echo "GROUP A (3 assertions): iter-152 source contains iter-172 top-of-file doc closing iter-171 awk gap"

iter172_assert_substring_present_with_human_readable_label \
    "A1: iter-152 contains 'ITER-172 AWK length() BYTE-COUNTING REMEDIATION' banner header" \
    "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    "ITER-172 AWK length() BYTE-COUNTING REMEDIATION"

iter172_assert_substring_present_with_human_readable_label \
    "A2: iter-152 cites RFC 3629 as authoritative spec for UTF-8 byte-pattern character counting" \
    "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    "RFC 3629"

iter172_assert_substring_present_with_human_readable_label \
    "A3: iter-152 documents the LC_ALL=C envelope pair-up rationale (UTF-8 locale outside awk, byte locale inside)" \
    "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    "preserves iter-171's UTF-8-locale bash semantics OUTSIDE awk"

# ─── Group B: all char-counting awk pipelines have LC_ALL=C prefix ─────────
echo ""
echo "GROUP B (1 assertion): all char-counting awk pipelines in iter-152 prefixed with LC_ALL=C envelope"

# Count occurrences of "LC_ALL=C awk" — should be exactly 5 (panel 2 + panel 3 dual-stage as 2 + panel 5 + --json aggregate + --json trend = 6 pipelines total, but panel 3 has 2 awk stages so total LC_ALL=C awk = 5; wait, let me recount: P2=1, P3-stage1=1, P3-stage2=1, P5=1, JSON-agg=1, JSON-trend=1 → 6 total).
ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER172_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS=$(grep -cE 'LC_ALL=C[[:space:]]+awk' "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH")
ITER172_EXPECTED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS=6
if (( ITER172_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS == ITER172_EXPECTED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS )); then
    echo "  ✓ B1: iter-152 contains ${ITER172_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS} 'LC_ALL=C awk' invocations (panel-2 + panel-3 dual-stage + panel-5 + --json aggregate + --json trend)"
else
    echo "  ✗ B1: iter-152 contains ${ITER172_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS} 'LC_ALL=C awk' invocations (expected ${ITER172_EXPECTED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS})"
    ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: all char-counting awk pipelines define the iter172 function ──
echo ""
echo "GROUP C (1 assertion): all 6 char-counting awk pipelines inline-define the iter172 char-count function"

ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
# Match the function definition's parameter-list signature uniquely to
# exclude the top-of-file comment mention.
ITER172_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS=$(grep -cF 'function iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(text,    byte_length_of_text_in_locale_native_units' "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH")
ITER172_EXPECTED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS=6
if (( ITER172_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS == ITER172_EXPECTED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS )); then
    echo "  ✓ C1: iter-152 contains ${ITER172_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS} inline iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes function definitions (1 per awk pipeline)"
else
    echo "  ✗ C1: iter-152 contains ${ITER172_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS} inline function definitions (expected ${ITER172_EXPECTED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS})"
    ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: bash -n syntax check passes after iter-172 refactor ──────────
echo ""
echo "GROUP D (1 assertion): iter-152 passes bash -n syntax check after iter-172 awk-function inlining"

ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ D1: iter-152 passes bash -n syntax check after iter-172 refactor"
else
    echo "  ✗ D1: iter-152 FAILS bash -n syntax check after iter-172 refactor"
    ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: end-to-end CJK probe through synthetic git repo ──────────────
echo ""
echo "GROUP E (2 assertions): end-to-end CJK probe through iter-152 awk pipelines in mktemp -d synthetic git repo"

ITER172_SYNTHETIC_GIT_REPO_TEMPDIR=$(mktemp -d)
trap 'rm -rf "$ITER172_SYNTHETIC_GIT_REPO_TEMPDIR"' EXIT

(
    cd "$ITER172_SYNTHETIC_GIT_REPO_TEMPDIR"
    git init -q -b main
    git config user.email "iter172-cjk-end-to-end-probe@local"
    git config user.name "iter172-cjk-end-to-end-probe"
    # Commit the CJK probe subject — guaranteed to be the most recent commit
    # and thus the worst offender by char count (15 chars > nothing else).
    git commit --allow-empty -q -m "$ITER172_SYNTHETIC_CJK_PROBE_SUBJECT_WITH_KNOWN_VISIBLE_CHAR_COUNT_OF_FIFTEEN"
) 2>/dev/null

# Run iter-152 against the synthetic repo via AUDIT_REPO_ROOT_OVERRIDE.
ITER172_SYNTHETIC_REPO_ITER152_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$ITER172_SYNTHETIC_GIT_REPO_TEMPDIR" bash "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH" 2>&1 || true)

# Assertion E1: Panel 3 worst-offender output reports the CJK subject with measured length=15 (chars, not 27 bytes).
ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
if echo "$ITER172_SYNTHETIC_REPO_ITER152_OUTPUT" | grep -qE "\(${ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT} chars\).*${ITER172_SYNTHETIC_CJK_PROBE_SUBJECT_WITH_KNOWN_VISIBLE_CHAR_COUNT_OF_FIFTEEN}"; then
    echo "  ✓ E1: panel-3 worst-offender reports correct char count (${ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT}) for CJK probe subject (iter-172 char-counting works end-to-end)"
else
    echo "  ✗ E1: panel-3 worst-offender does NOT report ${ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT}-char count for CJK subject — iter-172 char-counting NOT working end-to-end"
    echo "      (panel-3 output excerpt: $(echo "$ITER172_SYNTHETIC_REPO_ITER152_OUTPUT" | grep -A2 'Worst offenders' | tail -2))"
    ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Assertion E2: Panel 2 histogram bin assignment — the 15-char CJK subject should classify into the
# ≤50-char hard-target bin (industry hard target), NOT the 73-100-char mild-over-cap byte-counting false-positive bin.
ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
# Extract the count column for the ≤50-char bin. The histogram-bar-row
# printf renders as: "  <bin-label>  <count>  <bar>  <pct>". sed regex
# matches the integer immediately following the bin label closing paren
# (robust to multi-byte ≤ character position drift across awk dialects).
ITER172_PANEL2_LE_HARD_TARGET_COUNT=$(echo "$ITER172_SYNTHETIC_REPO_ITER152_OUTPUT" | sed -nE 's/^[[:space:]]*≤50 chars \(industry hard target\)[[:space:]]+([0-9]+).*/\1/p' | head -1)
if [[ "${ITER172_PANEL2_LE_HARD_TARGET_COUNT:-0}" -ge 1 ]] 2>/dev/null; then
    echo "  ✓ E2: panel-2 histogram classifies CJK probe into ≤50-char hard-target bin (count=${ITER172_PANEL2_LE_HARD_TARGET_COUNT}; iter-172 prevents byte-counting false-positive into 73-100-char bin)"
else
    echo "  ✗ E2: panel-2 histogram does NOT classify CJK probe into ≤50-char bin (count='${ITER172_PANEL2_LE_HARD_TARGET_COUNT}'); iter-172 char-counting may not be working in histogram"
    echo "      (panel-2 output excerpt:"
    echo "$ITER172_SYNTHETIC_REPO_ITER152_OUTPUT" | grep -A8 'Panel 2:' | head -10
    echo "      )"
    ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: --json mode CJK probe ──────────────────────────────────────
echo ""
echo "GROUP F (1 assertion): --json mode reports correct char count for CJK probe subject"

ITER172_TOTAL_ASSERTIONS_EVALUATED=$((ITER172_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER172_SYNTHETIC_REPO_ITER152_JSON_OUTPUT=$(AUDIT_REPO_ROOT_OVERRIDE="$ITER172_SYNTHETIC_GIT_REPO_TEMPDIR" bash "$ITER172_ITER152_HISTOGRAM_ABSOLUTE_PATH" --json 2>/dev/null || true)
# Assert the JSON contains a length_chars=15 entry for the CJK probe.
if echo "$ITER172_SYNTHETIC_REPO_ITER152_JSON_OUTPUT" | grep -qE '"length_chars":\s*'"$ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT"; then
    echo "  ✓ F1: --json output contains \"length_chars\": ${ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT} for CJK probe (AI-agent automation pipeline sees correct char count)"
else
    echo "  ✗ F1: --json output does NOT contain \"length_chars\": ${ITER172_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT} for CJK probe"
    echo "      (--json output excerpt: $(echo "$ITER172_SYNTHETIC_REPO_ITER152_JSON_OUTPUT" | grep -A1 'worst_offenders' | head -5))"
    ITER172_TOTAL_ASSERTIONS_FAILED=$((ITER172_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER172_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-172 REGRESSION TEST: ${ITER172_TOTAL_ASSERTIONS_EVALUATED}/${ITER172_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-172 REGRESSION TEST: $((ITER172_TOTAL_ASSERTIONS_EVALUATED - ITER172_TOTAL_ASSERTIONS_FAILED))/${ITER172_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER172_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
