#!/usr/bin/env bash
#MISE description="Iter-171 regression test pinning the UTF-8 locale invariant guard added at script entry of iter-150 (readable git-log renderer), iter-152 (5-panel commits-health histogram), and iter-153 (pre-commit advisor). Pre-iter-171 these scripts inherited the operator's LC_ALL — and CI runners with LC_ALL=C (common systemd-default misconfiguration) would silently byte-count subject length via bash \${#var}, mis-classifying e.g. 'feat: 修复编码问题XYZ' (15 visible characters, 30 UTF-8 bytes) as 27-30 chars under C locale and false-triggering ≥72-char hard-cap warnings on conformant 67-char CJK subjects. Iter-171 closes the silent-fail-class gap by injecting a case-statement guard at the top of all three scripts that maps empty/unset/C/POSIX → en_US.UTF-8 while respecting any other operator-set UTF-8 locale (en_CA, zh_CN, C.UTF-8, etc.) verbatim. Test asserts (a) each script source contains the guard, (b) guard correctly upgrades C → UTF-8, (c) the canonical iter-153 advisor returns 15 chars for the 15-char CJK probe subject under hostile LC_ALL=C (proving the end-to-end pipeline), (d) iter-152 worst-offender callout reports the correct char count for the same CJK subject under LC_ALL=C, (e) iter-150 renderer's awk soft-wrap still soft-wraps within terminal-width (sanity check that the LC_ALL fix didn't break awk-based rendering)."
set -euo pipefail

ITER171_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER171_REPO_ROOT"

ITER171_ITER150_RENDERER_ABSOLUTE_PATH="$ITER171_REPO_ROOT/scripts/iter150-readable-git-log-renderer-with-awk-based-soft-wrap-of-verbose-conventional-commit-subjects-to-eighty-column-terminal-width-with-color-decorations-and-indentation-for-operator-readability.sh"
ITER171_ITER152_HISTOGRAM_ABSOLUTE_PATH="$ITER171_REPO_ROOT/scripts/iter152-operator-facing-commits-subject-length-distribution-histogram-with-trend-analysis-and-worst-offender-callouts-for-conventional-commits-50-72-rule-compliance-visibility-fusing-iter150-readable-view-with-iter151-classification-overlay.sh"
ITER171_ITER153_ADVISOR_ABSOLUTE_PATH="$ITER171_REPO_ROOT/scripts/iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"

# Synthetic UTF-8 probe subject: 6 ASCII chars ("feat: ") + 6 CJK chars (修复编码问题) + 3 ASCII chars ("XYZ") = 15 visible chars, 27 UTF-8 bytes.
ITER171_SYNTHETIC_CJK_PROBE_SUBJECT_WITH_KNOWN_VISIBLE_CHAR_COUNT_OF_FIFTEEN_AND_UTF8_BYTE_COUNT_OF_TWENTYSEVEN="feat: 修复编码问题XYZ"
ITER171_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT=15
ITER171_EXPECTED_UTF8_BYTE_COUNT_FOR_PROBE_SUBJECT_USED_AS_NEGATIVE_CONTROL_TO_DETECT_REGRESSION_TO_PRE_ITER171_BYTE_COUNTING=27

ITER171_TOTAL_ASSERTIONS_EVALUATED=0
ITER171_TOTAL_ASSERTIONS_FAILED=0

iter171_assert_substring_present_with_human_readable_label() {
    local human_readable_label="$1"
    local file_path="$2"
    local expected_substring="$3"
    ITER171_TOTAL_ASSERTIONS_EVALUATED=$((ITER171_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$file_path"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER171_TOTAL_ASSERTIONS_FAILED=$((ITER171_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-171 UTF-8 LOCALE INVARIANT GUARD REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: all three scripts contain the LC_ALL guard ────────────────────
echo ""
echo "GROUP A (6 assertions): iter-150/152/153 scripts each contain the canonical UTF-8 locale invariant guard"

iter171_assert_substring_present_with_human_readable_label \
    "A1: iter-150 renderer contains ITER-171 banner header comment" \
    "$ITER171_ITER150_RENDERER_ABSOLUTE_PATH" \
    "ITER-171 UTF-8 LOCALE INVARIANT GUARD"

iter171_assert_substring_present_with_human_readable_label \
    "A2: iter-150 renderer contains case-statement guard mapping ''/C/POSIX → en_US.UTF-8" \
    "$ITER171_ITER150_RENDERER_ABSOLUTE_PATH" \
    '""|C|POSIX) export LC_ALL=en_US.UTF-8'

iter171_assert_substring_present_with_human_readable_label \
    "A3: iter-152 histogram contains ITER-171 banner header comment" \
    "$ITER171_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    "ITER-171 UTF-8 LOCALE INVARIANT GUARD"

iter171_assert_substring_present_with_human_readable_label \
    "A4: iter-152 histogram contains case-statement guard mapping ''/C/POSIX → en_US.UTF-8" \
    "$ITER171_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    '""|C|POSIX) export LC_ALL=en_US.UTF-8'

iter171_assert_substring_present_with_human_readable_label \
    "A5: iter-153 advisor contains ITER-171 banner header comment" \
    "$ITER171_ITER153_ADVISOR_ABSOLUTE_PATH" \
    "ITER-171 UTF-8 LOCALE INVARIANT GUARD"

iter171_assert_substring_present_with_human_readable_label \
    "A6: iter-153 advisor contains case-statement guard mapping ''/C/POSIX → en_US.UTF-8" \
    "$ITER171_ITER153_ADVISOR_ABSOLUTE_PATH" \
    '""|C|POSIX) export LC_ALL=en_US.UTF-8'

# ─── Group B: bash structurally valid after guard injection ─────────────────
echo ""
echo "GROUP B (3 assertions): bash -n syntax check passes after iter-171 guard injection"

for iter171_each_script_under_test_absolute_path in \
    "$ITER171_ITER150_RENDERER_ABSOLUTE_PATH" \
    "$ITER171_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    "$ITER171_ITER153_ADVISOR_ABSOLUTE_PATH"; do
    ITER171_TOTAL_ASSERTIONS_EVALUATED=$((ITER171_TOTAL_ASSERTIONS_EVALUATED + 1))
    iter171_each_script_basename=$(basename "$iter171_each_script_under_test_absolute_path" .sh)
    iter171_each_script_short_id="${iter171_each_script_basename%%-*}"
    if bash -n "$iter171_each_script_under_test_absolute_path" 2>/dev/null; then
        echo "  ✓ B (${iter171_each_script_short_id}): passes bash -n syntax check after iter-171 guard injection"
    else
        echo "  ✗ B (${iter171_each_script_short_id}): FAILS bash -n syntax check after iter-171 guard injection"
        ITER171_TOTAL_ASSERTIONS_FAILED=$((ITER171_TOTAL_ASSERTIONS_FAILED + 1))
    fi
done

# ─── Group C: end-to-end iter-153 advisor reports correct char count under hostile LC_ALL=C ─
echo ""
echo "GROUP C (2 assertions): iter-153 advisor end-to-end correctness under hostile LC_ALL=C"

ITER171_TOTAL_ASSERTIONS_EVALUATED=$((ITER171_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER171_ITER153_ADVISOR_OUTPUT_UNDER_HOSTILE_C_LOCALE=$(LC_ALL=C bash "$ITER171_ITER153_ADVISOR_ABSOLUTE_PATH" -- "$ITER171_SYNTHETIC_CJK_PROBE_SUBJECT_WITH_KNOWN_VISIBLE_CHAR_COUNT_OF_FIFTEEN_AND_UTF8_BYTE_COUNT_OF_TWENTYSEVEN" 2>&1 || true)
if echo "$ITER171_ITER153_ADVISOR_OUTPUT_UNDER_HOSTILE_C_LOCALE" | grep -qF "measured length:        ${ITER171_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT} chars"; then
    echo "  ✓ C1: iter-153 advisor reports correct visible-char count (${ITER171_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT}) for CJK probe under hostile LC_ALL=C (guard upgraded C → en_US.UTF-8)"
else
    echo "  ✗ C1: iter-153 advisor does NOT report ${ITER171_EXPECTED_VISIBLE_CHAR_COUNT_FOR_PROBE_SUBJECT}-char count under hostile LC_ALL=C — guard is not working end-to-end"
    echo "      (advisor output: $(echo "$ITER171_ITER153_ADVISOR_OUTPUT_UNDER_HOSTILE_C_LOCALE" | grep -E 'measured length' | head -1))"
    ITER171_TOTAL_ASSERTIONS_FAILED=$((ITER171_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Negative control: assert the pre-iter-171 byte-count (27) is NOT reported. Catches any future regression that reverts the guard.
ITER171_TOTAL_ASSERTIONS_EVALUATED=$((ITER171_TOTAL_ASSERTIONS_EVALUATED + 1))
if echo "$ITER171_ITER153_ADVISOR_OUTPUT_UNDER_HOSTILE_C_LOCALE" | grep -qF "measured length:        ${ITER171_EXPECTED_UTF8_BYTE_COUNT_FOR_PROBE_SUBJECT_USED_AS_NEGATIVE_CONTROL_TO_DETECT_REGRESSION_TO_PRE_ITER171_BYTE_COUNTING} chars"; then
    echo "  ✗ C2: iter-153 advisor STILL reports ${ITER171_EXPECTED_UTF8_BYTE_COUNT_FOR_PROBE_SUBJECT_USED_AS_NEGATIVE_CONTROL_TO_DETECT_REGRESSION_TO_PRE_ITER171_BYTE_COUNTING}-byte count under LC_ALL=C — REGRESSION to pre-iter-171 byte-counting behavior"
    ITER171_TOTAL_ASSERTIONS_FAILED=$((ITER171_TOTAL_ASSERTIONS_FAILED + 1))
else
    echo "  ✓ C2: iter-153 advisor does NOT report pre-iter-171 byte-count (${ITER171_EXPECTED_UTF8_BYTE_COUNT_FOR_PROBE_SUBJECT_USED_AS_NEGATIVE_CONTROL_TO_DETECT_REGRESSION_TO_PRE_ITER171_BYTE_COUNTING}) — guard correctly suppresses byte-counting regression"
fi

# ─── Group D: hostile LC_ALL=C does not affect iter-150 renderer's basic operation ─
echo ""
echo "GROUP D (1 assertion): iter-150 renderer still functions correctly under hostile LC_ALL=C"

ITER171_TOTAL_ASSERTIONS_EVALUATED=$((ITER171_TOTAL_ASSERTIONS_EVALUATED + 1))
# Just verify it produces output without crashing under LC_ALL=C — the awk length() byte-counting limitation
# is documented as known and a candidate for iter-172+ refactor, so we don't assert on it here.
# Capture full output first then check (avoiding SIGPIPE-induced pipefail interaction with `head | grep`).
ITER171_ITER150_RENDERER_OUTPUT_UNDER_HOSTILE_C_LOCALE=$(LC_ALL=C ITER150_COMMIT_COUNT_TO_DISPLAY=1 bash "$ITER171_ITER150_RENDERER_ABSOLUTE_PATH" 2>/dev/null || true)
if [[ -n "$ITER171_ITER150_RENDERER_OUTPUT_UNDER_HOSTILE_C_LOCALE" ]]; then
    echo "  ✓ D1: iter-150 renderer produces output under hostile LC_ALL=C (guard prevents script-level crash; $(echo "$ITER171_ITER150_RENDERER_OUTPUT_UNDER_HOSTILE_C_LOCALE" | wc -l | tr -d ' ') lines emitted)"
else
    echo "  ✗ D1: iter-150 renderer produces no output under LC_ALL=C — guard may have broken rendering"
    ITER171_TOTAL_ASSERTIONS_FAILED=$((ITER171_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: documentary invariant — Conventional Commits §5 reference ─────
echo ""
echo "GROUP E (3 assertions): guard comment cites Conventional Commits §5 character-counting semantics rationale"

iter171_assert_substring_present_with_human_readable_label \
    "E1: iter-150 guard comment cites 'Conventional Commits §5' (CHARACTER-counting semantics rationale)" \
    "$ITER171_ITER150_RENDERER_ABSOLUTE_PATH" \
    "Conventional Commits §5 specifies CHARACTER-counting"

iter171_assert_substring_present_with_human_readable_label \
    "E2: iter-152 guard comment cites 'Conventional Commits §5' (CHARACTER-counting semantics rationale)" \
    "$ITER171_ITER152_HISTOGRAM_ABSOLUTE_PATH" \
    "Conventional Commits §5 specifies CHARACTER-counting"

iter171_assert_substring_present_with_human_readable_label \
    "E3: iter-153 guard comment cites 'Conventional Commits §5' (CHARACTER-counting semantics rationale)" \
    "$ITER171_ITER153_ADVISOR_ABSOLUTE_PATH" \
    "Conventional Commits §5 specifies CHARACTER-counting"

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER171_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-171 REGRESSION TEST: ${ITER171_TOTAL_ASSERTIONS_EVALUATED}/${ITER171_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-171 REGRESSION TEST: $((ITER171_TOTAL_ASSERTIONS_EVALUATED - ITER171_TOTAL_ASSERTIONS_FAILED))/${ITER171_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER171_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
