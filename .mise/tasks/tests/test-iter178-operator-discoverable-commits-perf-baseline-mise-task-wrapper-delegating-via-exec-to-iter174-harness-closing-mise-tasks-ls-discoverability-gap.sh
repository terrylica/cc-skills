#!/usr/bin/env bash
#MISE description="Iter-178 regression test pinning the operator-discoverable commits:perf-baseline mise task wrapper that delegates via exec to the iter-174 wall-clock perf-baseline regression harness. Pre-iter-178 the iter-174 harness was invocable only via the 160-character .mise/tasks/tests/test-iter174-… filename — undiscoverable in 'mise tasks ls' output. Operators wanting to run the perf check after editing toolkit scripts had no first-class command. Iter-178 closes this usability gap by adding .mise/tasks/commits/perf-baseline as a thin dispatcher wrapper (mirroring the iter-160 commits:status dispatcher pattern) that exec-delegates to the canonical iter-174 harness — zero logic duplication, single source of truth preserved. Test asserts (a) wrapper file exists + executable + bash-syntax-clean + shellcheck-clean, (b) wrapper has #MISE description metadata for mise-tasks-ls discoverability, (c) wrapper delegates to iter-174 harness via exec (not invocation duplication), (d) wrapper has soft-fail diagnostic when iter-174 harness is missing (operator-visible error, not silent), (e) iter-156 dispatcher banner mentions the new commits:perf-baseline task in its PERFORMANCE BENCHMARK section, (f) iter-156 dispatcher arc range updated from iter-169 to iter-178, (g) end-to-end smoke test: 'mise run commits:perf-baseline' invocation surfaces the iter-174 harness banner header + GROUP A header proving exec delegation works."
set -euo pipefail

ITER178_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER178_REPO_ROOT"

ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH="$ITER178_REPO_ROOT/.mise/tasks/commits/perf-baseline"
ITER178_ITER174_HARNESS_ABSOLUTE_PATH="$ITER178_REPO_ROOT/.mise/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"
ITER178_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER178_REPO_ROOT/.mise/tasks/commits/_default"

ITER178_TOTAL_ASSERTIONS_EVALUATED=0
ITER178_TOTAL_ASSERTIONS_FAILED=0

iter178_assert_filesystem_predicate_holds_for_wrapper() {
    local human_readable_label="$1"
    local bash_test_expression="$2"
    ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (failed predicate: $bash_test_expression)"
        ITER178_TOTAL_ASSERTIONS_FAILED=$((ITER178_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter178_assert_substring_present_in_file() {
    local human_readable_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER178_TOTAL_ASSERTIONS_FAILED=$((ITER178_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-178 OPERATOR-DISCOVERABLE COMMITS:PERF-BASELINE WRAPPER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: wrapper file structural validity ─────────────────────────────
echo ""
echo "GROUP A (4 assertions): commits:perf-baseline wrapper file structurally valid"

iter178_assert_filesystem_predicate_holds_for_wrapper \
    "A1: wrapper file exists at .mise/tasks/commits/perf-baseline" \
    "-f \"$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH\""

iter178_assert_filesystem_predicate_holds_for_wrapper \
    "A2: wrapper file is executable (chmod +x)" \
    "-x \"$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH\""

ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A3: wrapper passes bash -n syntax check"
else
    echo "  ✗ A3: wrapper FAILS bash -n syntax check"
    ITER178_TOTAL_ASSERTIONS_FAILED=$((ITER178_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A4: wrapper passes shellcheck zero-warning"
    else
        echo "  ✗ A4: wrapper has shellcheck warnings"
        ITER178_TOTAL_ASSERTIONS_FAILED=$((ITER178_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A4: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: wrapper has MISE description metadata for discoverability ────
echo ""
echo "GROUP B (2 assertions): wrapper has MISE description metadata for mise-tasks-ls discoverability"

iter178_assert_substring_present_in_file \
    "B1: wrapper has #MISE description= metadata header" \
    "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    "#MISE description="

iter178_assert_substring_present_in_file \
    "B2: wrapper description cites the iter-174 harness as delegation target" \
    "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    "delegates to the iter-174 harness"

# ─── Group C: wrapper delegates via exec (not duplication) ─────────────────
echo ""
echo "GROUP C (2 assertions): wrapper delegates to iter-174 harness via exec preserving single source of truth"

# Single-quoted literal-dollar-sign search string is intentional — grep for
# literal source-text substring. Shellcheck SC2016 false-positive here.
# shellcheck disable=SC2016
iter178_assert_substring_present_in_file \
    "C1: wrapper uses exec to delegate (clean signal propagation, no fork waste)" \
    "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    'exec "$ITER178_PERF_BASELINE_HARNESS_ABSOLUTE_PATH"'

iter178_assert_substring_present_in_file \
    "C2: wrapper has missing-harness soft-fail diagnostic (operator-visible error, not silent)" \
    "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    "iter-174 perf-baseline harness not found or not executable"

# ─── Group D: iter-156 dispatcher banner mentions the new task ─────────────
echo ""
echo "GROUP D (3 assertions): iter-156 dispatcher banner refresh — mentions iter-178 commits:perf-baseline + arc range bump"

iter178_assert_substring_present_in_file \
    "D1: iter-156 dispatcher has PERFORMANCE BENCHMARK section header citing iter-178" \
    "$ITER178_ITER156_DISPATCHER_ABSOLUTE_PATH" \
    "PERFORMANCE BENCHMARK (iter-178 wrapper of iter-174 harness)"

iter178_assert_substring_present_in_file \
    "D2: iter-156 dispatcher includes 'mise run commits:perf-baseline' invocation line" \
    "$ITER178_ITER156_DISPATCHER_ABSOLUTE_PATH" \
    "mise run commits:perf-baseline"

iter178_assert_substring_present_in_file \
    "D3: iter-156 dispatcher arc-range banner updated from iter-169 to iter-178" \
    "$ITER178_ITER156_DISPATCHER_ABSOLUTE_PATH" \
    "(iter-150 → iter-178 arc)"

# ─── Group E: end-to-end smoke test — mise run commits:perf-baseline ───────
echo ""
echo "GROUP E (1 assertion): end-to-end smoke test — wrapper delegation works through mise"

# Note: skip this assertion if iter-174 harness itself isn't executable
# (would be a separate failure mode caught by iter-174 test directly).
ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER178_ITER174_HARNESS_ABSOLUTE_PATH" ]]; then
    # Invoke through the wrapper directly (not via mise to avoid pulling in mise dependency).
    # The wrapper's exec delegation should produce the iter-174 harness banner.
    ITER178_WRAPPER_OUTPUT_CAPTURE=$(bash "$ITER178_PERF_BASELINE_MISE_TASK_WRAPPER_ABSOLUTE_PATH" 2>&1 || true)
    if [[ "$ITER178_WRAPPER_OUTPUT_CAPTURE" == *"ITER-174 EMPIRICAL WALL-CLOCK PERF-BASELINE REGRESSION HARNESS"* ]] && \
       [[ "$ITER178_WRAPPER_OUTPUT_CAPTURE" == *"GROUP A"* ]]; then
        echo "  ✓ E1: wrapper exec-delegation surfaces iter-174 harness banner + GROUP A header (single-source-of-truth invariant preserved)"
    else
        echo "  ✗ E1: wrapper invocation did NOT surface iter-174 harness banner — exec delegation may be broken"
        ITER178_TOTAL_ASSERTIONS_FAILED=$((ITER178_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E1: iter-174 harness not executable — SKIPPED (separately gated by iter-174 test)"
    ITER178_TOTAL_ASSERTIONS_EVALUATED=$((ITER178_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER178_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-178 REGRESSION TEST: ${ITER178_TOTAL_ASSERTIONS_EVALUATED}/${ITER178_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-178 REGRESSION TEST: $((ITER178_TOTAL_ASSERTIONS_EVALUATED - ITER178_TOTAL_ASSERTIONS_FAILED))/${ITER178_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER178_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
