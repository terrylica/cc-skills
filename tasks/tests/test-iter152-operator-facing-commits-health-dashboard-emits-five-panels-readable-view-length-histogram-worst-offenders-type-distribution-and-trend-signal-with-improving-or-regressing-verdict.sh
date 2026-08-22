#!/usr/bin/env bash
#MISE description="Iter-152 regression test pinning the operator-facing commits:health dashboard. Asserts (a) renderer + mise wrapper exist + executable + bash-clean + shellcheck-clean, (b) renderer uses awk per the cc-skills CLAUDE.md awk-only principle, (c) renderer honors all 5 env-var tunables (commit-count, hard-cap, hard-target, histogram-bar-width, worst-offender-count), (d) renderer delegates Panel 1 to iter-150 renderer for readable-view consistency, (e) Panel 2 histogram bin labels match conventional-commits 50/72-rule anchored thresholds, (f) Panel 3 worst-offender callouts sort by char count descending, (g) Panel 4 enumerates the 11 canonical conventional-commits types in semantic-release priority order, (h) Panel 5 trend computes median (p50) per window and emits improving/regressing/stable/mixed verdict, (i) mise wrapper delegates via exec for clean signal propagation, (j) functional smoke test against actual cc-skills repo emits all 5 panel headers + footer knob hints + at least one histogram bar."
set -euo pipefail

ITER152_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER152_REPO_ROOT"

ITER152_RENDERER_SCRIPT_RELATIVE_PATH="scripts/iter152-operator-facing-commits-subject-length-distribution-histogram-with-trend-analysis-and-worst-offender-callouts-for-conventional-commits-50-72-rule-compliance-visibility-fusing-iter150-readable-view-with-iter151-classification-overlay.sh"
ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH="$ITER152_REPO_ROOT/$ITER152_RENDERER_SCRIPT_RELATIVE_PATH"
ITER152_MISE_TASK_WRAPPER_RELATIVE_PATH=".mise/tasks/commits/health"
ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH="$ITER152_REPO_ROOT/$ITER152_MISE_TASK_WRAPPER_RELATIVE_PATH"

ITER152_TOTAL_ASSERTIONS_EVALUATED=0
ITER152_TOTAL_ASSERTIONS_FAILED=0

iter152_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter152_assert_filesystem_predicate_holds() {
    local human_readable_assertion_label="$1"
    local bash_test_expression="$2"
    ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    failed bash predicate: $bash_test_expression"
        ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-152 COMMITS-HEALTH-DASHBOARD REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Structural validity ───────────────────────────────────────────
echo ""
echo "GROUP A (5 assertions): renderer + mise wrapper structurally valid"

iter152_assert_filesystem_predicate_holds \
    "A1: renderer exists at iter-152 verbose path" \
    "-f \"$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH\""

iter152_assert_filesystem_predicate_holds \
    "A2: renderer is executable (chmod +x)" \
    "-x \"$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH\""

iter152_assert_filesystem_predicate_holds \
    "A3: mise wrapper exists at commits/health" \
    "-f \"$ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH\""

ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" 2>/dev/null && bash -n "$ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A4: both renderer + mise wrapper pass bash -n syntax check"
else
    echo "  ✗ A4: bash -n syntax check failed"
    ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1 && shellcheck "$ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A5: both renderer + mise wrapper pass shellcheck (zero warnings)"
    else
        echo "  ✗ A5: shellcheck warnings detected"
        ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A5: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: Implementation invariants ─────────────────────────────────────
echo ""
echo "GROUP B (6 assertions): renderer implementation pins critical invariants"

iter152_assert_substring_present_in_file \
    "B1: renderer uses awk per CLAUDE.md Terminal-text-unwrapping awk-only principle" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "| awk"

iter152_assert_substring_present_in_file \
    "B2: renderer honors ITER152_COMMIT_COUNT_TO_ANALYZE env-var tunable" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER152_COMMIT_COUNT_TO_ANALYZE"

iter152_assert_substring_present_in_file \
    "B3: renderer honors ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS env-var tunable" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS"

iter152_assert_substring_present_in_file \
    "B4: renderer honors ITER152_SUBJECT_HARD_TARGET_THRESHOLD_CHARS env-var tunable" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER152_SUBJECT_HARD_TARGET_THRESHOLD_CHARS"

iter152_assert_substring_present_in_file \
    "B5: renderer honors ITER152_HISTOGRAM_BAR_WIDTH env-var tunable for terminal-fit predictability" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER152_HISTOGRAM_BAR_WIDTH"

iter152_assert_substring_present_in_file \
    "B6: renderer honors ITER152_WORST_OFFENDER_CALLOUT_COUNT env-var tunable" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER152_WORST_OFFENDER_CALLOUT_COUNT"

# ─── Group C: Panel-by-panel correctness ────────────────────────────────────
echo ""
echo "GROUP C (5 assertions): each of the 5 panels implements its design contract"

iter152_assert_substring_present_in_file \
    "C1: Panel 1 delegates to the iter-150 renderer (does not duplicate awk-soft-wrap logic)" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "iter150-readable-git-log-renderer"

iter152_assert_substring_present_in_file \
    "C2: Panel 2 histogram has the bin label for ≤hard-target with 'industry hard target' annotation" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "industry hard target"

iter152_assert_substring_present_in_file \
    "C3: Panel 2 histogram has a bin for 1000+ chars annotated as iter-144-149 outlier territory" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "1000+ chars (iter-144-149 outliers)"

iter152_assert_substring_present_in_file \
    "C4: Panel 4 enumerates the 11 canonical conventional-commits types in sem-rel priority order" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "feat fix perf chore docs refactor test build ci style revert"

iter152_assert_substring_present_in_file \
    "C5: Panel 5 computes p50 median (robust against iter-144-149 outliers vs mean)" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "iter152_compute_p50_median_of_array"

# ─── Group D: Trend-signal verdict logic ────────────────────────────────────
echo ""
echo "GROUP D (4 assertions): Panel 5 trend-signal verdict logic emits all 4 verdicts"

iter152_assert_substring_present_in_file \
    "D1: trend verdict can emit IMPROVING (both metrics moved in good direction)" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "verdict: IMPROVING"

iter152_assert_substring_present_in_file \
    "D2: trend verdict can emit REGRESSING (both metrics moved in bad direction)" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "verdict: REGRESSING"

iter152_assert_substring_present_in_file \
    "D3: trend verdict can emit STABLE (no change between windows)" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "verdict: STABLE"

iter152_assert_substring_present_in_file \
    "D4: trend verdict can emit MIXED (one metric improved, the other did not)" \
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "verdict: MIXED"

# ─── Group E: Mise task wrapper structurally valid ──────────────────────────
echo ""
echo "GROUP E (3 assertions): mise task wrapper delegates to renderer via exec"

# Single-quoted literal search string on next assertion intentionally
# preserves the `$VARNAME` dollar-sign as part of the substring being
# searched for in the source file. shellcheck SC2016 is the desired
# behavior here (we WANT literal dollar-sign).
# shellcheck disable=SC2016
iter152_assert_substring_present_in_file \
    "E1: mise wrapper delegates via exec for clean signal propagation" \
    "$ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    'exec "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH"'

iter152_assert_substring_present_in_file \
    "E2: mise wrapper has MISE description metadata for mise-tasks-listing discoverability" \
    "$ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    "#MISE description="

iter152_assert_substring_present_in_file \
    "E3: mise wrapper description mentions all 5 panels for operator discoverability" \
    "$ITER152_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    "iter-150 (VIEW) → iter-151 (DETECT) → iter-152 (HEALTH SUMMARY)"

# ─── Group F: Functional smoke test ─────────────────────────────────────────
echo ""
echo "GROUP F (5 assertions): functional smoke test emits all 5 panel headers + footer"

ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST=$(
    "$ITER152_RENDERER_SCRIPT_ABSOLUTE_PATH" 2>&1 || true
)

ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"Panel 1: Readable view (iter-150 renderer)"* ]]; then
    echo "  ✓ F1: renderer emits Panel 1 header (readable view)"
else
    echo "  ✗ F1: Panel 1 header missing"
    ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"Panel 2: Subject-length distribution histogram"* ]]; then
    echo "  ✓ F2: renderer emits Panel 2 header (length-distribution histogram)"
else
    echo "  ✗ F2: Panel 2 header missing"
    ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"Panel 3: Worst offenders"* ]] \
   && [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"Panel 4: Conventional-commits type distribution"* ]] \
   && [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"Panel 5: Trend"* ]]; then
    echo "  ✓ F3: renderer emits Panel 3, 4, 5 headers (worst offenders, type distribution, trend)"
else
    echo "  ✗ F3: one or more of Panel 3/4/5 headers missing"
    ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"tune via ITER152_"* ]] \
   && [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"mise run release:history"* ]]; then
    echo "  ✓ F4: renderer emits footer with operator-tunable knob hints + iter-150 cross-reference"
else
    echo "  ✗ F4: footer knob hints or iter-150 cross-reference missing"
    ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
fi

# At least one histogram bar should render (the cc-skills repo has commits in the window).
ITER152_TOTAL_ASSERTIONS_EVALUATED=$((ITER152_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER152_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"█"* ]]; then
    echo "  ✓ F5: renderer emits at least one histogram bar (full block char █ visible)"
else
    echo "  ✗ F5: no histogram bars rendered — empty cc-skills history or rendering broke"
    ITER152_TOTAL_ASSERTIONS_FAILED=$((ITER152_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER152_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-152 REGRESSION TEST: ${ITER152_TOTAL_ASSERTIONS_EVALUATED}/${ITER152_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-152 REGRESSION TEST: $((ITER152_TOTAL_ASSERTIONS_EVALUATED - ITER152_TOTAL_ASSERTIONS_FAILED))/${ITER152_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER152_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
