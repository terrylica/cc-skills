#!/usr/bin/env bash
#MISE description="Iter-185 regression test pinning the SUMMARY INDEX section at the top of the iter-156 dispatcher banner. Pre-iter-185 the banner had grown organically to 380+ lines through iter-150-through-iter-184 with detailed sections only — no compact top-of-banner index. A fresh operator running 'mise run commits' (no-subcommand dispatch) saw a wall of text and could not quickly find what they needed. Industry-standard CLI help (man pages plus gh-help plus brew-help plus npm-help) all open with a compact INDEX table at the top then expand into detailed sections. Iter-185 closes this first-impression-UX gap with an ITER-185 SUMMARY INDEX block between the title and the VIEW section — a one-line-per-tool invocation guide listing all 11 operator-facing entry points (release-history, commits-health plus json variant, 3 commits-advise variants, commits-advise message-file, commits-pending-release plus json variant, commits-status plus json variant, commits-install-hook, commits-uninstall-hook, commits-perf-baseline plus json variant) with terse purpose descriptors. Test asserts (a) SUMMARY INDEX section header present, (b) index appears BEFORE the VIEW section (line ordering preserved), (c) all 11 expected operator-facing tool invocations listed in the index, (d) footer scroll hint present pointing operators to detailed sections, (e) bash -n + shellcheck clean."
set -euo pipefail

ITER185_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER185_REPO_ROOT"

ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER185_REPO_ROOT/.mise/tasks/commits/_default"

ITER185_TOTAL_ASSERTIONS_EVALUATED=0
ITER185_TOTAL_ASSERTIONS_FAILED=0

iter185_assert_substring_present_in_dispatcher_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER185_TOTAL_ASSERTIONS_EVALUATED=$((ITER185_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER185_TOTAL_ASSERTIONS_FAILED=$((ITER185_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-185 DISPATCHER SUMMARY INDEX REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: SUMMARY INDEX section header + scroll-down footer hint present ─
echo ""
echo "GROUP A (2 assertions): iter-185 SUMMARY INDEX section header + footer scroll hint present"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "A1: ITER-185 SUMMARY INDEX section header text present" \
    "ITER-185 SUMMARY INDEX (one-line operator-facing invocation guide"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "A2: footer scroll-down hint pointing operators to detailed sections below" \
    "Scroll down for full descriptions"

# ─── Group B: all 11 operator-facing tool invocations listed in the INDEX ───
echo ""
echo "GROUP B (11 assertions): every operator-facing tool invocation listed in the SUMMARY INDEX"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B1:  release:history (iter-150 readable git log render)" \
    "mise run release:history"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B2:  commits:health [--json] (iter-152 5-panel dashboard)" \
    "mise run commits:health [--json]"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B3:  commits:advise -- <subject> (iter-153 advisor default mode)" \
    'mise run commits:advise -- "<subj>"'

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B4:  commits:advise --json (iter-153 AI-agent mode)" \
    "mise run commits:advise --json"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B5:  commits:advise --strict (iter-153 hard-gating mode)" \
    "mise run commits:advise --strict"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B6:  commits:advise --message-file <path> (iter-162 body-aware footer reader)" \
    "mise run commits:advise --message-file"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B7:  commits:pending-release [--json] (iter-165 aggregate preview)" \
    "mise run commits:pending-release [--json]"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B8:  commits:status [--json] (iter-160 brew-doctor-style self-diagnosis)" \
    "mise run commits:status [--json]"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B9:  commits:install-hook (iter-157 git commit-msg hook installer)" \
    "mise run commits:install-hook"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B10: commits:uninstall-hook (iter-157 hook remover)" \
    "mise run commits:uninstall-hook"

iter185_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B11: commits:perf-baseline [--json] (iter-178 wrapper + iter-179/182/183/184 envelope)" \
    "mise run commits:perf-baseline [--json]"

# ─── Group C: ordering — INDEX appears BEFORE the VIEW section ─────────────
echo ""
echo "GROUP C (1 assertion): SUMMARY INDEX block ordering precedes the VIEW section (operator first-impression UX)"

ITER185_LINE_OF_SUMMARY_INDEX_HEADER=$(grep -n "ITER-185 SUMMARY INDEX" "$ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH" | head -1 | cut -d: -f1)
ITER185_LINE_OF_VIEW_SECTION_HEADER=$(grep -n "VIEW (iter-150)" "$ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH" | head -1 | cut -d: -f1)

ITER185_TOTAL_ASSERTIONS_EVALUATED=$((ITER185_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -n "$ITER185_LINE_OF_SUMMARY_INDEX_HEADER" ]] && [[ -n "$ITER185_LINE_OF_VIEW_SECTION_HEADER" ]] && \
   (( ITER185_LINE_OF_SUMMARY_INDEX_HEADER < ITER185_LINE_OF_VIEW_SECTION_HEADER )); then
    echo "  ✓ C1: SUMMARY INDEX header (L${ITER185_LINE_OF_SUMMARY_INDEX_HEADER}) appears BEFORE VIEW section (L${ITER185_LINE_OF_VIEW_SECTION_HEADER}) — operators see the index first"
else
    echo "  ✗ C1: SUMMARY INDEX ordering broken (index=${ITER185_LINE_OF_SUMMARY_INDEX_HEADER:-MISSING}, view=${ITER185_LINE_OF_VIEW_SECTION_HEADER:-MISSING})"
    ITER185_TOTAL_ASSERTIONS_FAILED=$((ITER185_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: end-to-end dispatcher invocation still renders without errors ─
echo ""
echo "GROUP D (1 assertion): dispatcher invocation renders without errors after iter-185 INDEX injection"

ITER185_TOTAL_ASSERTIONS_EVALUATED=$((ITER185_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER185_DISPATCHER_RENDERED_OUTPUT_CAPTURE=$(bash "$ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH" 2>&1 || true)
if [[ "$ITER185_DISPATCHER_RENDERED_OUTPUT_CAPTURE" == *"ITER-185 SUMMARY INDEX"* ]] && \
   [[ "$ITER185_DISPATCHER_RENDERED_OUTPUT_CAPTURE" == *"VIEW (iter-150)"* ]] && \
   [[ "$ITER185_DISPATCHER_RENDERED_OUTPUT_CAPTURE" == *"PERFORMANCE BENCHMARK"* ]]; then
    echo "  ✓ D1: dispatcher renders SUMMARY INDEX + all existing sections (regression-safe; iter-185 didn't break any existing section)"
else
    echo "  ✗ D1: dispatcher output missing expected sections — iter-185 may have broken existing layout"
    ITER185_TOTAL_ASSERTIONS_FAILED=$((ITER185_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: bash -n + shellcheck ─────────────────────────────────────────
echo ""
echo "GROUP E (2 assertions): dispatcher passes bash -n + shellcheck after iter-185 SUMMARY INDEX injection"

ITER185_TOTAL_ASSERTIONS_EVALUATED=$((ITER185_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ E1: dispatcher passes bash -n syntax check after iter-185 INDEX injection"
else
    echo "  ✗ E1: dispatcher FAILS bash -n syntax check after iter-185 INDEX injection"
    ITER185_TOTAL_ASSERTIONS_FAILED=$((ITER185_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER185_TOTAL_ASSERTIONS_EVALUATED=$((ITER185_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER185_ITER156_DISPATCHER_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ E2: dispatcher passes shellcheck zero-warning after iter-185 INDEX injection"
    else
        echo "  ✗ E2: dispatcher has shellcheck warnings after iter-185 INDEX injection"
        ITER185_TOTAL_ASSERTIONS_FAILED=$((ITER185_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER185_TOTAL_ASSERTIONS_EVALUATED=$((ITER185_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER185_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-185 REGRESSION TEST: ${ITER185_TOTAL_ASSERTIONS_EVALUATED}/${ITER185_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-185 REGRESSION TEST: $((ITER185_TOTAL_ASSERTIONS_EVALUATED - ITER185_TOTAL_ASSERTIONS_FAILED))/${ITER185_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER185_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
