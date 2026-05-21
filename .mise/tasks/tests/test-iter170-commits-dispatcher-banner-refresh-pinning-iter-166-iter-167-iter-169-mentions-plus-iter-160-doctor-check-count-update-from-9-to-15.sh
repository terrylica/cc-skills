#!/usr/bin/env bash
#MISE description="Iter-170 regression test pinning the iter-156 commits-namespace default dispatcher banner refresh. Pre-iter-170 the dispatcher header said 'iter-150 → iter-165 arc' (4 iterations stale) and the DIAGNOSE section described commits:status as a '9-check ... iter-150 → iter-158 tools' diagnostic (6 iterations stale; doctor was actually 15 checks across iter-150 → iter-167 after iter-163 + iter-166 coverage extensions). Operators running mise run commits for in-terminal discovery would miss the most recent quality + UX wins: iter-166 doctor extension #2 (3 critical checks), iter-167 5.17× perf optimization, iter-169 release:preflight informational integration. Iter-170 closes the doc-drift gap by (a) updating dispatcher header arc range, (b) refreshing MISE description to mention iter-166/167/169, (c) bumping commits:status description from '9-check ... iter-150 → iter-158' to '15-check ... iter-150 → iter-167', (d) adding a new QUALITY + PERFORMANCE section listing the 4 non-operator-visible iterations with empirical numbers. Parallel to iter-168 docs/RELEASE.md update but for in-terminal cheatsheet visibility. Test asserts each invariant via simple substring grep so future iter-N drift fails."
set -euo pipefail

ITER170_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER170_REPO_ROOT"

ITER170_DISPATCHER_TASK_ABSOLUTE_PATH="$ITER170_REPO_ROOT/.mise/tasks/commits/_default"

ITER170_TOTAL_ASSERTIONS_EVALUATED=0
ITER170_TOTAL_ASSERTIONS_FAILED=0

iter170_assert_substring_present_in_dispatcher_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER170_TOTAL_ASSERTIONS_EVALUATED=$((ITER170_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER170_DISPATCHER_TASK_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER170_TOTAL_ASSERTIONS_FAILED=$((ITER170_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter170_assert_substring_absent_in_dispatcher_with_human_readable_label() {
    local human_readable_label="$1"
    local stale_substring="$2"
    ITER170_TOTAL_ASSERTIONS_EVALUATED=$((ITER170_TOTAL_ASSERTIONS_EVALUATED + 1))
    if ! grep -qF "$stale_substring" "$ITER170_DISPATCHER_TASK_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (stale substring still present: ${stale_substring:0:80})"
        ITER170_TOTAL_ASSERTIONS_FAILED=$((ITER170_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-170 COMMITS-DISPATCHER BANNER-REFRESH REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: dispatcher structurally valid after iter-170 refresh ──────────
echo ""
echo "GROUP A (1 assertion): dispatcher structurally valid after iter-170 refresh"

ITER170_TOTAL_ASSERTIONS_EVALUATED=$((ITER170_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER170_DISPATCHER_TASK_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A1: dispatcher passes bash -n syntax check after iter-170 refresh"
else
    echo "  ✗ A1: dispatcher FAILS bash -n syntax check after refresh"
    ITER170_TOTAL_ASSERTIONS_FAILED=$((ITER170_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group B: arc-range header + tool count updated ─────────────────────────
echo ""
echo "GROUP B (2 assertions): arc range header + MISE description reflect iter-169 state"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B1: dispatcher header advertises 'iter-150 → iter-169 arc' (was 'iter-150 → iter-165 arc' pre-iter-170; 4 iterations stale)" \
    "(iter-150 → iter-169 arc)"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "B2: MISE description references 'iter-150-through-iter-169' (discoverable via 'mise tasks' enumeration)" \
    "iter-150-through-iter-169"

# ─── Group C: stale pre-iter-170 markers removed ────────────────────────────
echo ""
echo "GROUP C (3 assertions): pre-iter-170 stale upper-bound markers removed"

iter170_assert_substring_absent_in_dispatcher_with_human_readable_label \
    "C1: stale 'iter-150 → iter-165 arc' header gone" \
    "(iter-150 → iter-165 arc)"

iter170_assert_substring_absent_in_dispatcher_with_human_readable_label \
    "C2: stale 'iter-150-through-iter-165' MISE description text gone" \
    "iter-150-through-iter-165"

iter170_assert_substring_absent_in_dispatcher_with_human_readable_label \
    "C3: stale '9-check self-diagnosis across iter-150 → iter-158' doctor-description text gone" \
    "9-check self-diagnosis across iter-150 → iter-158"

# ─── Group D: doctor description updated to 15-check ────────────────────────
echo ""
echo "GROUP D (2 assertions): commits:status DIAGNOSE section reflects 15-check (13 CRITICAL + 2 WARNING) state"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "D1: doctor description says '15-check self-diagnosis across iter-150 → iter-167 tools'" \
    "15-check self-diagnosis across iter-150 → iter-167 tools"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "D2: doctor description explicitly references '13 CRITICAL + 2 WARNING' tier breakdown (sanity check vs actual doctor counters)" \
    "13 CRITICAL + 2 WARNING"

# ─── Group E: new QUALITY + PERFORMANCE section + iter-166/167/169 mentions
echo ""
echo "GROUP E (5 assertions): new QUALITY + PERFORMANCE section added with iter-166/167/169 mentions"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "E1: QUALITY + PERFORMANCE section header present (lists iter-163, iter-166, iter-167, iter-169 as non-operator-visible hardening work)" \
    "QUALITY + PERFORMANCE (iter-163, iter-166, iter-167, iter-169)"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "E2: iter-166 doctor extension #2 entry mentions 'critical_passed counter 10 → 13' bump" \
    "10 → 13"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "E3: iter-167 perf entry advertises '≈5.17× speedup at N=50' empirical measurement" \
    "≈5.17× speedup at N=50"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "E4: iter-167 perf entry advertises 'ASCII NUL safe' design invariant (cites git-pretty-formats(1) %x00 specifier)" \
    "ASCII NUL safe"

iter170_assert_substring_present_in_dispatcher_with_human_readable_label \
    "E5: iter-169 entry advertises 'Check 3b' preflight splice landmark" \
    "Check 3b"

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER170_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-170 REGRESSION TEST: ${ITER170_TOTAL_ASSERTIONS_EVALUATED}/${ITER170_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-170 REGRESSION TEST: $((ITER170_TOTAL_ASSERTIONS_EVALUATED - ITER170_TOTAL_ASSERTIONS_FAILED))/${ITER170_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER170_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
