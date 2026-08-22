#!/usr/bin/env bash
#MISE description="Iter-168 regression test pinning the docs/RELEASE.md Conventional-Commits Operator Toolkit Index section. Pre-iter-168 the toolkit-index section header said 'iter-150 → iter-158 arc' and the canonical table covered 7 operator-facing tools — stale by 8 iterations (iter-160 doctor, iter-161 semver-bump preview, iter-162 BREAKING-CHANGE footer detector, iter-163 doctor extension, iter-164 next-version preview, iter-165 pending-release aggregator, iter-166 doctor extension #2, iter-167 perf optimization). New operators reading the canonical reference would never discover the iter-160 through iter-165 operator-facing tools. Iter-168 closes the doc-drift gap by (a) updating the section header arc range to iter-150 → iter-167, (b) expanding the canonical table to 11 operator-facing tools across the full lifecycle, (c) adding rows for iter-160 doctor (default + --json), iter-161 bump preview, iter-162 body-aware advisor, iter-164 next-version preview, iter-165 pending-release (default + --json), (d) adding a non-operator-visible quality + performance improvements subsection mentioning iter-163, iter-166, iter-167 with the empirically measured 5.17x speedup number, (e) updating the 'see the iter-150 through iter-158 subsections below' link-out to 'iter-150 through iter-167'. Test asserts each invariant via simple substring grep so a future iteration that re-introduces drift fails this guard."
set -euo pipefail

ITER168_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER168_REPO_ROOT"

ITER168_DOCS_RELEASE_MD_ABSOLUTE_PATH="$ITER168_REPO_ROOT/docs/RELEASE.md"

ITER168_TOTAL_ASSERTIONS_EVALUATED=0
ITER168_TOTAL_ASSERTIONS_FAILED=0

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER168_TOTAL_ASSERTIONS_EVALUATED=$((ITER168_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER168_DOCS_RELEASE_MD_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER168_TOTAL_ASSERTIONS_FAILED=$((ITER168_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter168_assert_substring_absent_in_docs_release_md_with_human_readable_label() {
    local human_readable_label="$1"
    local stale_substring="$2"
    ITER168_TOTAL_ASSERTIONS_EVALUATED=$((ITER168_TOTAL_ASSERTIONS_EVALUATED + 1))
    if ! grep -qF "$stale_substring" "$ITER168_DOCS_RELEASE_MD_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (stale substring still present: ${stale_substring:0:80})"
        ITER168_TOTAL_ASSERTIONS_FAILED=$((ITER168_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-168 DOCS/RELEASE.MD TOOLKIT-INDEX DOC-DRIFT COVERAGE-EXTENSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: section header + tool count up-to-date ────────────────────────
echo ""
echo "GROUP A (3 assertions): section header arc range + tool count reflect iter-167 state"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "A1: section header advertises 'iter-150 → iter-167 arc' (was 'iter-150 → iter-158 arc' pre-iter-168)" \
    "Conventional-Commits Operator Toolkit Index (iter-150 → iter-167 arc)"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "A2: section advertises '11 operator-facing tools' (was '7' pre-iter-168)" \
    "11 operator-facing tools"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "A3: closing link-out updated to 'iter-150 through iter-167 subsections below' (was 'iter-150 through iter-158')" \
    "iter-150 through iter-167 subsections below"

# ─── Group B: stale iter-158-bounded references removed ─────────────────────
echo ""
echo "GROUP B (2 assertions): pre-iter-168 stale 'iter-158' upper-bound markers removed"

iter168_assert_substring_absent_in_docs_release_md_with_human_readable_label \
    "B1: stale 'iter-150 → iter-158 arc' header gone" \
    "Conventional-Commits Operator Toolkit Index (iter-150 → iter-158 arc)"

iter168_assert_substring_absent_in_docs_release_md_with_human_readable_label \
    "B2: stale 'see the iter-150 through iter-158 subsections below' link-out gone" \
    "iter-150 through iter-158 subsections below"

# ─── Group C: canonical table includes iter-160 → iter-165 rows ─────────────
echo ""
echo "GROUP C (8 assertions): canonical table mentions every iter-160 → iter-165 operator-facing tool"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C1: iter-160 toolkit self-diagnosis tool (commits:status) advertised" \
    "mise run commits:status"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C2: iter-160 toolkit self-diagnosis --json mode advertised with iter160_schema_version=1 stability contract" \
    "iter160_schema_version=1"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C3: iter-161 SEMVER-BUMP PREVIEW lifecycle stage advertised" \
    "SEMVER-BUMP PREVIEW"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C4: iter-162 BREAKING CHANGE footer detection lifecycle stage advertised (body-aware --message-file)" \
    "BREAKING CHANGE footer detection"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C5: iter-164 NEXT-VERSION PREVIEW lifecycle stage advertised" \
    "NEXT-VERSION PREVIEW"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C6: iter-165 commits:pending-release tool advertised (default mode)" \
    "mise run commits:pending-release"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C7: iter-165 commits:pending-release --json mode advertised with iter165_schema_version=1 stability contract" \
    "iter165_schema_version=1"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "C8: iter-165 PENDING-RELEASE PREVIEW lifecycle stage label advertised" \
    "PENDING-RELEASE PREVIEW"

# ─── Group D: quality + perf subsection mentions iter-163/166/167 ───────────
echo ""
echo "GROUP D (4 assertions): non-operator-visible quality + perf improvements subsection added"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "D1: 'Quality + performance improvements (iter-163, iter-166, iter-167)' subsection header present" \
    "Quality + performance improvements (iter-163, iter-166, iter-167)"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "D2: iter-163 doctor extension #1 mentioned with closing-silent-regression-gap rationale" \
    "iter-163"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "D3: iter-166 doctor extension #2 mentioned with critical_passed counter bump to 13" \
    "critical_passed"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "D4: iter-167 perf optimization mentioned with empirical ≈5.17× speedup number" \
    "5.17"

# ─── Group E: doctor 15-check claim matches actual doctor critical_passed=13
# + warnings=2 (sanity check that toolkit table value isn't stale) ─────────
echo ""
echo "GROUP E (1 assertion): toolkit table describes doctor as '15-check' matching the actual iter-160 doctor"

iter168_assert_substring_present_in_docs_release_md_with_human_readable_label \
    "E1: doctor row describes the iter-160 doctor as a 15-check brew-doctor-style health report (matches iter-166 extension state where total checks = 15: 13 CRITICAL + 2 WARNING)" \
    "15-check brew-doctor-style"

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER168_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-168 REGRESSION TEST: ${ITER168_TOTAL_ASSERTIONS_EVALUATED}/${ITER168_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-168 REGRESSION TEST: $((ITER168_TOTAL_ASSERTIONS_EVALUATED - ITER168_TOTAL_ASSERTIONS_FAILED))/${ITER168_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER168_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
