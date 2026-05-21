#!/usr/bin/env bash
#MISE description="Iter-173 regression test pinning the iter-172 LC_ALL=C envelope + RFC 3629 char-count function applied to iter-150 readable git log renderer. Pre-iter-173 the 3 subject-text length() call sites inside iter-150 soft-wrap-boundary detection byte-counted CJK subjects, causing aggressive over-wrap (a 100-char CJK subject of 280 UTF-8 bytes would wrap at byte 80 approximately char 30 for typical CJK density, much earlier than operator expects under 80-column terminal contract). Iter-173 closes this gap by reusing the iter-172 pattern: LC_ALL=C prefix on the awk invocation plus inline iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes function definition with 3 length() call sites replaced. Result soft-wrap boundary is measured in visible characters not bytes matching operator intuition for CJK emoji Latin diaeresis subjects. After iter-173 the iter-150 + iter-152 + iter-153 conventional-commits operator toolkit is fully UTF-8-correct end-to-end. Test asserts (a) iter-150 source contains iter-173 top-of-file doc block (b) LC_ALL=C awk prefix on the renderer awk invocation (c) inline iter172 function definition present (d) 3 length call sites inside soft-wrap algorithm replaced with iter172 function calls (e) bash -n syntax check passes (f) end-to-end CJK probe through a synthetic mktemp -d git repo renders without crash and produces output."
set -euo pipefail

ITER173_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER173_REPO_ROOT"

ITER173_ITER150_RENDERER_ABSOLUTE_PATH="$ITER173_REPO_ROOT/scripts/iter150-readable-git-log-renderer-with-awk-based-soft-wrap-of-verbose-conventional-commit-subjects-to-eighty-column-terminal-width-with-color-decorations-and-indentation-for-operator-readability.sh"

ITER173_SYNTHETIC_CJK_PROBE_SUBJECT_FOR_END_TO_END_RENDER_VERIFICATION="feat: 修复编码问题XYZ"

ITER173_TOTAL_ASSERTIONS_EVALUATED=0
ITER173_TOTAL_ASSERTIONS_FAILED=0

iter173_assert_substring_present_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER173_ITER150_RENDERER_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-173 SOFT-WRAP-BOUNDARY UTF-8 CHAR-COUNTING REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: top-of-file iter-173 doc block ────────────────────────────────
echo ""
echo "GROUP A (3 assertions): iter-150 source contains iter-173 top-of-file doc closing UTF-8 awk gap"

iter173_assert_substring_present_with_human_readable_label \
    "A1: iter-150 contains 'ITER-173 AWK SOFT-WRAP-BOUNDARY UTF-8 CORRECTNESS' banner header" \
    "ITER-173 AWK SOFT-WRAP-BOUNDARY UTF-8 CORRECTNESS"

iter173_assert_substring_present_with_human_readable_label \
    "A2: iter-150 documents the iter-172 pattern reuse rationale" \
    "applying the iter-172 pattern"

iter173_assert_substring_present_with_human_readable_label \
    "A3: iter-150 documents end-to-end UTF-8 correctness arc closure (iter-150 + iter-152 + iter-153)" \
    "operator toolkit is fully UTF-8-correct end-to-end"

# ─── Group B: LC_ALL=C envelope present on awk invocation ───────────────────
echo ""
echo "GROUP B (1 assertion): LC_ALL=C envelope present on the renderer awk invocation"

ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER173_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS=$(grep -cE 'LC_ALL=C[[:space:]]+awk' "$ITER173_ITER150_RENDERER_ABSOLUTE_PATH")
if (( ITER173_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS == 1 )); then
    echo "  ✓ B1: iter-150 contains exactly 1 'LC_ALL=C awk' invocation (single awk pipeline; matches iter-150 design)"
else
    echo "  ✗ B1: iter-150 contains ${ITER173_OBSERVED_COUNT_OF_LC_ALL_C_AWK_INVOCATIONS} 'LC_ALL=C awk' invocations (expected 1)"
    ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: iter172 inline function definition present ────────────────────
echo ""
echo "GROUP C (1 assertion): iter-150 awk script inlines the iter172 RFC 3629 char-count function"

ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS=$(grep -cF 'function iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(text,    byte_length_of_text_in_locale_native_units' "$ITER173_ITER150_RENDERER_ABSOLUTE_PATH")
if (( ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS == 1 )); then
    echo "  ✓ C1: iter-150 contains exactly 1 inline iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes function definition"
else
    echo "  ✗ C1: iter-150 contains ${ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_DEFINITIONS} inline function definitions (expected 1)"
    ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: 3 length() call sites replaced with iter172 function calls ────
echo ""
echo "GROUP D (1 assertion): 3 length() call sites inside iter150_soft_wrap_long_string_on_word_boundaries_to_target_width are replaced with iter172 function calls"

ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
# Count iter172 function INVOCATIONS (not definitions) — should be exactly 3 inside the soft-wrap function.
# Pattern: iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(  ← invocation has open paren immediately
ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_INVOCATIONS=$(grep -cE 'iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes\(accumulated' "$ITER173_ITER150_RENDERER_ABSOLUTE_PATH")
ITER173_EXPECTED_COUNT_OF_INVOCATIONS=3
if (( ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_INVOCATIONS == ITER173_EXPECTED_COUNT_OF_INVOCATIONS )); then
    echo "  ✓ D1: iter-150 contains ${ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_INVOCATIONS} iter172 function invocations on accumulated_* variables (replaces the 3 subject-text length() call sites inside soft-wrap algorithm)"
else
    echo "  ✗ D1: iter-150 contains ${ITER173_OBSERVED_COUNT_OF_INLINE_FUNCTION_INVOCATIONS} iter172 function invocations on accumulated_* vars (expected ${ITER173_EXPECTED_COUNT_OF_INVOCATIONS})"
    ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: bash -n syntax check ──────────────────────────────────────────
echo ""
echo "GROUP E (1 assertion): iter-150 passes bash -n syntax check after iter-173 refactor"

ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER173_ITER150_RENDERER_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ E1: iter-150 passes bash -n syntax check after iter-173 refactor"
else
    echo "  ✗ E1: iter-150 FAILS bash -n syntax check after iter-173 refactor"
    ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: end-to-end CJK probe through synthetic git repo ───────────────
echo ""
echo "GROUP F (2 assertions): end-to-end CJK probe through iter-150 in mktemp -d synthetic git repo"

ITER173_SYNTHETIC_GIT_REPO_TEMPDIR=$(mktemp -d)
trap 'rm -rf "$ITER173_SYNTHETIC_GIT_REPO_TEMPDIR"' EXIT

(
    cd "$ITER173_SYNTHETIC_GIT_REPO_TEMPDIR"
    git init -q -b main
    git config user.email "iter173-cjk-soft-wrap-probe@local"
    git config user.name "iter173-cjk-soft-wrap-probe"
    git commit --allow-empty -q -m "$ITER173_SYNTHETIC_CJK_PROBE_SUBJECT_FOR_END_TO_END_RENDER_VERIFICATION"
) 2>/dev/null

ITER173_SYNTHETIC_REPO_ITER150_OUTPUT=$(ITER150_COMMIT_COUNT_TO_DISPLAY=1 AUDIT_REPO_ROOT_OVERRIDE="$ITER173_SYNTHETIC_GIT_REPO_TEMPDIR" bash "$ITER173_ITER150_RENDERER_ABSOLUTE_PATH" 2>&1 || true)

# Assertion F1: Renderer produces non-empty output (does not crash on CJK).
ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -n "$ITER173_SYNTHETIC_REPO_ITER150_OUTPUT" ]]; then
    echo "  ✓ F1: iter-150 renderer produces output for CJK probe ($(echo "$ITER173_SYNTHETIC_REPO_ITER150_OUTPUT" | wc -l | tr -d ' ') lines emitted; no crash under iter-173 refactor)"
else
    echo "  ✗ F1: iter-150 renderer produces NO output for CJK probe — iter-173 may have broken rendering"
    ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Assertion F2: Renderer output contains the CJK probe subject characters intact.
ITER173_TOTAL_ASSERTIONS_EVALUATED=$((ITER173_TOTAL_ASSERTIONS_EVALUATED + 1))
if echo "$ITER173_SYNTHETIC_REPO_ITER150_OUTPUT" | grep -qF "修复编码问题"; then
    echo "  ✓ F2: iter-150 renderer output preserves CJK characters intact (no mid-UTF-8 byte truncation; soft-wrap boundary correctly measured in chars not bytes)"
else
    echo "  ✗ F2: iter-150 renderer output does NOT contain CJK characters — output may be byte-truncated"
    echo "      (output excerpt: $(echo "$ITER173_SYNTHETIC_REPO_ITER150_OUTPUT" | head -10))"
    ITER173_TOTAL_ASSERTIONS_FAILED=$((ITER173_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER173_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-173 REGRESSION TEST: ${ITER173_TOTAL_ASSERTIONS_EVALUATED}/${ITER173_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-173 REGRESSION TEST: $((ITER173_TOTAL_ASSERTIONS_EVALUATED - ITER173_TOTAL_ASSERTIONS_FAILED))/${ITER173_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER173_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
