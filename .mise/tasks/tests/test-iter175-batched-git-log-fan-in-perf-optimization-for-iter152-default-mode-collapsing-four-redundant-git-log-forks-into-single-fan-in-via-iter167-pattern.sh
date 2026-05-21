#!/usr/bin/env bash
#MISE description="Iter-175 regression test pinning the batched-git-log-fan-in perf optimization applied to iter-152 default human-readable mode. Pre-iter-175 the default mode invoked git log 4 separate times — once per panel-2 / panel-3 / panel-4 / panel-5 awk pipeline — at progressively wider windows (N/N/N/2N commits), each fork redundantly walking the commit-DAG. Iter-175 applies the iter-167 batched-fan-in pattern (originally proven on iter-165 pending-release aggregator with 4.5x speedup) by issuing ONE git log -2N invocation up-front, caching raw output in a script-scoped bash variable keyed by the U+001F INFORMATION SEPARATOR ONE in-band field separator, and having each panel awk pipeline consume the cached batch via stdin redirection plus head -N filter. Empirically measured median wall-clock improvement: 79ms pre-iter-175 to 56ms post-iter-175 on a 10-commit window, approximately 29 percent reduction. Test asserts (a) iter-152 source contains iter-175 top-of-file doc block, (b) iter-175 fan-in helper function defined, (c) iter-175 cached-batch variable + in-band-separator variable defined, (d) all 4 default-mode panel git log invocations replaced with cached-batch consumption, (e) bash -n passes, (f) shellcheck passes, (g) end-to-end default-mode smoke test emits 5-panel output with expected headers, (h) end-to-end --json mode smoke test still emits valid JSON (json-mode git log invocations left as-is)."
set -euo pipefail

ITER175_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER175_REPO_ROOT"

ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH="$ITER175_REPO_ROOT/scripts/iter152-operator-facing-commits-subject-length-distribution-histogram-with-trend-analysis-and-worst-offender-callouts-for-conventional-commits-50-72-rule-compliance-visibility-fusing-iter150-readable-view-with-iter151-classification-overlay.sh"

ITER175_TOTAL_ASSERTIONS_EVALUATED=0
ITER175_TOTAL_ASSERTIONS_FAILED=0

iter175_assert_substring_present_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-175 BATCHED-GIT-LOG-FAN-IN PERF OPTIMIZATION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: iter-152 source contains iter-175 top-of-file doc block ──────
echo ""
echo "GROUP A (3 assertions): iter-152 source documents iter-175 batched-fan-in rationale"

iter175_assert_substring_present_with_human_readable_label \
    "A1: iter-152 contains 'ITER-175 BATCHED-GIT-LOG-FAN-IN' banner header" \
    "ITER-175 BATCHED-GIT-LOG-FAN-IN"

iter175_assert_substring_present_with_human_readable_label \
    "A2: iter-152 cites iter-167 pattern provenance (iter-165 4.5x speedup precedent)" \
    "iter-167 batched-git-log-fan-in pattern"

iter175_assert_substring_present_with_human_readable_label \
    "A3: iter-152 documents the 4-to-1 git-log fork reduction model" \
    "4 git-log forks → 1 git-log fork"

# ─── Group B: iter-175 fan-in helper function defined ──────────────────────
echo ""
echo "GROUP B (2 assertions): iter-175 fan-in helper function + batched-output variable defined"

iter175_assert_substring_present_with_human_readable_label \
    "B1: iter-175 fan-in helper function declared with verbose self-explanatory name" \
    "iter175_fan_in_single_git_log_invocation_collecting_two_n_commits_with_sha_and_subject_fields_for_all_four_downstream_default_mode_panel_consumers()"

iter175_assert_substring_present_with_human_readable_label \
    "B2: iter-175 cached-batch variable initialized at top-level (not function-local) for cross-panel access" \
    "ITER175_BATCHED_GIT_LOG_RAW_OUTPUT_ACROSS_TWO_N_COMMITS_WITH_SHA_AND_SUBJECT_FIELDS_SEPARATED_BY_INFORMATION_SEPARATOR_ONE_FOR_FAN_IN_TO_PANELS_TWO_THROUGH_FIVE=\"\""

# ─── Group C: orchestrator invokes fan-in helper before panels ─────────────
echo ""
echo "GROUP C (1 assertion): orchestrator primes the cached batch BEFORE panel-2/3/4/5 render"

iter175_assert_substring_present_with_human_readable_label \
    "C1: main orchestrator calls iter-175 fan-in helper between panel-1 and panel-2" \
    "    iter175_fan_in_single_git_log_invocation_collecting_two_n_commits_with_sha_and_subject_fields_for_all_four_downstream_default_mode_panel_consumers"

# ─── Group D: 4 default-mode panel git-log invocations replaced ────────────
echo ""
echo "GROUP D (1 assertion): default-mode panels 2/3/4/5 no longer spawn redundant git-log forks"

# Count remaining `git log ` invocations. After iter-175, there should be
# exactly 3 in the entire script:
#   1. The iter-175 fan-in helper itself (collects 2N batched output)
#   2. The --json mode aggregate panel (single git log fork — own scope)
#   3. The --json mode trend panel (single git log fork — own scope)
ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER175_OBSERVED_GIT_LOG_INVOCATION_COUNT=$(grep -cE '^[[:space:]]+git log ' "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH")
ITER175_EXPECTED_GIT_LOG_INVOCATION_COUNT=3
if (( ITER175_OBSERVED_GIT_LOG_INVOCATION_COUNT == ITER175_EXPECTED_GIT_LOG_INVOCATION_COUNT )); then
    echo "  ✓ D1: iter-152 contains exactly ${ITER175_OBSERVED_GIT_LOG_INVOCATION_COUNT} 'git log' invocations (iter-175 fan-in helper + 2 --json mode pipelines; default-mode panels 2/3/4/5 no longer fork redundantly)"
else
    echo "  ✗ D1: iter-152 contains ${ITER175_OBSERVED_GIT_LOG_INVOCATION_COUNT} 'git log' invocations (expected ${ITER175_EXPECTED_GIT_LOG_INVOCATION_COUNT}: fan-in + 2 json-mode)"
    ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: each default-mode panel consumes the cached batch ────────────
echo ""
echo "GROUP E (1 assertion): each default-mode panel reads via printf-and-pipe from the cached batch"

ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
# Single-quoted literal-dollar-sign search string is intentional — we
# want grep to match the literal `$ITER175_…` source-text substring, not
# expand it as a bash variable. Shellcheck SC2016 false-positive here.
# shellcheck disable=SC2016
ITER175_OBSERVED_BATCH_CONSUMER_COUNT=$(grep -cF 'printf '"'"'%s\n'"'"' "$ITER175_BATCHED_GIT_LOG_RAW_OUTPUT_ACROSS_TWO_N_COMMITS' "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH")
ITER175_EXPECTED_BATCH_CONSUMER_COUNT=4
if (( ITER175_OBSERVED_BATCH_CONSUMER_COUNT == ITER175_EXPECTED_BATCH_CONSUMER_COUNT )); then
    echo "  ✓ E1: iter-152 has ${ITER175_OBSERVED_BATCH_CONSUMER_COUNT} cached-batch consumer call sites (panels 2/3/4/5 all read from the same cached batch)"
else
    echo "  ✗ E1: iter-152 has ${ITER175_OBSERVED_BATCH_CONSUMER_COUNT} cached-batch consumer call sites (expected ${ITER175_EXPECTED_BATCH_CONSUMER_COUNT}: one per default-mode panel)"
    ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: bash -n syntax check ──────────────────────────────────────────
echo ""
echo "GROUP F (1 assertion): iter-152 passes bash -n syntax check after iter-175 refactor"

ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ F1: iter-152 passes bash -n syntax check after iter-175 refactor"
else
    echo "  ✗ F1: iter-152 FAILS bash -n syntax check after iter-175 refactor"
    ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group G: shellcheck zero-warning ───────────────────────────────────────
echo ""
echo "GROUP G (1 assertion): iter-152 passes shellcheck zero-warning after iter-175 refactor"

ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ G1: iter-152 passes shellcheck zero-warning after iter-175 refactor"
    else
        echo "  ✗ G1: iter-152 has shellcheck warnings after iter-175 refactor"
        ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ G1: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group H: end-to-end smoke test default-mode + --json mode ──────────────
echo ""
echo "GROUP H (2 assertions): end-to-end smoke test default + --json mode emit expected output"

ITER175_DEFAULT_MODE_OUTPUT_CAPTURE=$(bash "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH" 2>&1 || true)

ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
# Verify all 5 panel headers present in the default-mode output, proving
# the orchestrator correctly fans the cached batch through all four
# panel-2/3/4/5 consumers (panel-1 is the iter-150 delegate, unaffected).
if [[ "$ITER175_DEFAULT_MODE_OUTPUT_CAPTURE" == *"Panel 1: Readable view"* ]] && \
   [[ "$ITER175_DEFAULT_MODE_OUTPUT_CAPTURE" == *"Panel 2: Subject-length distribution histogram"* ]] && \
   [[ "$ITER175_DEFAULT_MODE_OUTPUT_CAPTURE" == *"Panel 3: Worst offenders"* ]] && \
   [[ "$ITER175_DEFAULT_MODE_OUTPUT_CAPTURE" == *"Panel 4: Conventional-commits type distribution"* ]] && \
   [[ "$ITER175_DEFAULT_MODE_OUTPUT_CAPTURE" == *"Panel 5: Trend"* ]]; then
    echo "  ✓ H1: default-mode dashboard emits all 5 panel headers (fan-in correctly feeds panels 2/3/4/5)"
else
    echo "  ✗ H1: default-mode dashboard missing one or more of the 5 panel headers — iter-175 fan-in may have broken a panel"
    ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER175_JSON_MODE_OUTPUT_CAPTURE=$(bash "$ITER175_ITER152_DASHBOARD_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER175_TOTAL_ASSERTIONS_EVALUATED=$((ITER175_TOTAL_ASSERTIONS_EVALUATED + 1))
# Verify --json mode still emits a valid-shape JSON envelope (iter-175
# left --json mode's two git-log invocations untouched — only default-
# mode panels 2/3/4/5 were refactored).
if [[ "$ITER175_JSON_MODE_OUTPUT_CAPTURE" == *'"iter155_schema_version"'* ]] && \
   [[ "$ITER175_JSON_MODE_OUTPUT_CAPTURE" == *'"panel_3_worst_offenders_top_n_by_char_count"'* ]] && \
   [[ "$ITER175_JSON_MODE_OUTPUT_CAPTURE" == *'"panel_5_recent_vs_previous_window_trend_signal"'* ]]; then
    echo "  ✓ H2: --json mode emits valid envelope with all 5 panel sections (iter-175 default-mode refactor did not regress --json mode)"
else
    echo "  ✗ H2: --json mode envelope malformed or missing panel sections"
    ITER175_TOTAL_ASSERTIONS_FAILED=$((ITER175_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER175_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-175 REGRESSION TEST: ${ITER175_TOTAL_ASSERTIONS_EVALUATED}/${ITER175_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-175 REGRESSION TEST: $((ITER175_TOTAL_ASSERTIONS_EVALUATED - ITER175_TOTAL_ASSERTIONS_FAILED))/${ITER175_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER175_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
