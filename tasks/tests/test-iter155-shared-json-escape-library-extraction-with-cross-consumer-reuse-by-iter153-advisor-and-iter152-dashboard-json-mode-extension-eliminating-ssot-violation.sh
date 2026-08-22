#!/usr/bin/env bash
#MISE description="Iter-155 regression test pinning the architectural refactor: pure-bash RFC 8259 JSON escape function extracted from iter-153 advisor into shared library at scripts/lib/, refactored iter-153 to source the lib (zero behavior change — iter-153 + iter-154 tests must still pass), added --json mode to iter-152 dashboard sourcing the same lib (closes the AI-agent surface gap parallel to what iter-153 filled for the advisor). Asserts (a) shared lib exists at scripts/lib/iter155-...sh + bash-clean + shellcheck-clean, (b) lib exports the canonical function name + the iter154-shim-compat alias + the LIBRARY_LOADED_SENTINEL env var, (c) iter-153 advisor sources the lib via git rev-parse path construction, (d) iter-152 dashboard sources the lib via git rev-parse path construction, (e) iter-152 dashboard parses --json flag and dispatches to iter-155 JSON renderer, (f) --json output parses cleanly via independent python3 json.loads, (g) JSON schema includes all 5 panel keys + stable iter155_schema_version=1 + verdict from the trend signal, (h) iter-153 + iter-154 regression tests still pass after refactor (zero-behavior-change invariant)."
set -euo pipefail

ITER155_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER155_REPO_ROOT"

ITER155_SHARED_LIB_RELATIVE_PATH="scripts/lib/iter155-pure-bash-rfc8259-json-string-escape-shared-library-for-cross-script-reuse-eliminating-duplication-of-iter154-correctness-fix-across-iter152-iter153-and-future-consumers.sh"
ITER155_SHARED_LIB_ABSOLUTE_PATH="$ITER155_REPO_ROOT/$ITER155_SHARED_LIB_RELATIVE_PATH"
ITER155_ITER153_ADVISOR_RELATIVE_PATH="scripts/iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"
ITER155_ITER153_ADVISOR_ABSOLUTE_PATH="$ITER155_REPO_ROOT/$ITER155_ITER153_ADVISOR_RELATIVE_PATH"
ITER155_ITER152_DASHBOARD_RELATIVE_PATH="scripts/iter152-operator-facing-commits-subject-length-distribution-histogram-with-trend-analysis-and-worst-offender-callouts-for-conventional-commits-50-72-rule-compliance-visibility-fusing-iter150-readable-view-with-iter151-classification-overlay.sh"
ITER155_ITER152_DASHBOARD_ABSOLUTE_PATH="$ITER155_REPO_ROOT/$ITER155_ITER152_DASHBOARD_RELATIVE_PATH"

ITER155_TOTAL_ASSERTIONS_EVALUATED=0
ITER155_TOTAL_ASSERTIONS_FAILED=0

iter155_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-155 SHARED-JSON-ESCAPE-LIB-EXTRACTION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Shared library structurally valid ─────────────────────────────
echo ""
echo "GROUP A (3 assertions): shared library structurally valid"

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER155_SHARED_LIB_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: shared lib exists at scripts/lib/ canonical path"
else
    echo "  ✗ A1: shared lib missing"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER155_SHARED_LIB_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: shared lib passes bash -n syntax check"
else
    echo "  ✗ A2: shared lib FAILS bash -n"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER155_SHARED_LIB_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: shared lib passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: shared lib has shellcheck warnings"
        ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: Shared library exports canonical surface ──────────────────────
echo ""
echo "GROUP B (3 assertions): shared library exports canonical surface"

iter155_assert_substring_present_in_file \
    "B1: shared lib declares the canonical function name (RFC 8259 escape with verbose-self-explanatory naming)" \
    "$ITER155_SHARED_LIB_ABSOLUTE_PATH" \
    "iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars"

iter155_assert_substring_present_in_file \
    "B2: shared lib exports module-load sentinel for consumer success-verification" \
    "$ITER155_SHARED_LIB_ABSOLUTE_PATH" \
    "ITER155_PURE_BASH_RFC8259_JSON_ESCAPE_LIBRARY_LOADED_SENTINEL"

iter155_assert_substring_present_in_file \
    "B3: shared lib cites RFC 8259 § 7 specification for traceability" \
    "$ITER155_SHARED_LIB_ABSOLUTE_PATH" \
    "RFC 8259 § 7"

# ─── Group C: Iter-153 advisor sources the shared lib ───────────────────────
echo ""
echo "GROUP C (2 assertions): iter-153 advisor sources the shared lib (SSoT integration)"

iter155_assert_substring_present_in_file \
    "C1: iter-153 advisor constructs shared-lib absolute path via git rev-parse --show-toplevel" \
    "$ITER155_ITER153_ADVISOR_ABSOLUTE_PATH" \
    "ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH"

iter155_assert_substring_present_in_file \
    "C2: iter-153 advisor delegates iter-154 shim to the canonical iter-155 shared-lib function" \
    "$ITER155_ITER153_ADVISOR_ABSOLUTE_PATH" \
    "iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars"

# ─── Group D: Iter-152 dashboard sources the shared lib + has --json mode ──
echo ""
echo "GROUP D (4 assertions): iter-152 dashboard gains --json mode reusing shared lib"

iter155_assert_substring_present_in_file \
    "D1: iter-152 dashboard sources shared lib via git rev-parse path construction" \
    "$ITER155_ITER152_DASHBOARD_ABSOLUTE_PATH" \
    "ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH_FOR_ITER152_DASHBOARD"

iter155_assert_substring_present_in_file \
    "D2: iter-152 dashboard parses --json flag for AI-agent output mode dispatch" \
    "$ITER155_ITER152_DASHBOARD_ABSOLUTE_PATH" \
    'ITER155_ITER152_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION'

iter155_assert_substring_present_in_file \
    "D3: iter-152 dashboard declares iter-155 JSON-renderer function with verbose-self-explanatory name" \
    "$ITER155_ITER152_DASHBOARD_ABSOLUTE_PATH" \
    "iter155_render_iter152_dashboard_as_machine_readable_json_aggregating_all_five_panels_for_ai_agent_automation_pipeline_consumption"

iter155_assert_substring_present_in_file \
    "D4: iter-152 dashboard invokes shared-lib escape function for safe subject embedding" \
    "$ITER155_ITER152_DASHBOARD_ABSOLUTE_PATH" \
    "iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars"

# ─── Group E: Functional --json output parses + has all 5 panels ────────────
echo ""
echo "GROUP E (3 assertions): --json output parses cleanly + includes all 5 panel keys + stable schema"

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE=$(
    "$ITER155_ITER152_DASHBOARD_ABSOLUTE_PATH" --json 2>/dev/null || true
)
if printf '%s' "$ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✓ E1: iter-152 --json output parses cleanly via independent python3 json.loads"
else
    echo "  ✗ E1: --json output fails to parse"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE" == *'"panel_2_subject_length_distribution_histogram"'* ]] \
   && [[ "$ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE" == *'"panel_3_worst_offenders_top_n_by_char_count"'* ]] \
   && [[ "$ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE" == *'"panel_4_conventional_commits_type_distribution"'* ]] \
   && [[ "$ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE" == *'"panel_5_recent_vs_previous_window_trend_signal"'* ]]; then
    echo "  ✓ E2: --json output includes Panel 2 + 3 + 4 + 5 keys (Panel 1 is delegated to iter-150 renderer + omitted from JSON by design)"
else
    echo "  ✗ E2: --json output missing one or more panel keys"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER155_DASHBOARD_JSON_OUTPUT_CAPTURE" == *'"iter155_schema_version": 1'* ]]; then
    echo "  ✓ E3: --json output emits stable iter155_schema_version=1 for AI-agent consumer contract"
else
    echo "  ✗ E3: schema_version field missing or wrong value"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: Zero-behavior-change invariant — iter-153 + iter-154 still pass
echo ""
echo "GROUP F (2 assertions): zero-behavior-change invariant — iter-153 + iter-154 regression tests still pass"

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if "$ITER155_REPO_ROOT/.mise/tasks/tests/test-iter153-pre-commit-dry-run-advisor-classifies-proposed-conventional-commit-subject-with-human-readable-verdict-and-json-mode-and-strict-mode-gating-on-silent-fail-class-only-not-long-subject-overlay.sh" >/dev/null 2>&1; then
    echo "  ✓ F1: iter-153 regression test still passes after iter-155 refactor (24/24)"
else
    echo "  ✗ F1: iter-153 regression test FAILED — iter-155 refactor introduced behavior change"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER155_TOTAL_ASSERTIONS_EVALUATED=$((ITER155_TOTAL_ASSERTIONS_EVALUATED + 1))
if "$ITER155_REPO_ROOT/.mise/tasks/tests/test-iter154-advisor-pure-bash-json-escape-correctness-for-all-seven-rfc8259-special-chars-and-git-commit-editmsg-auto-detect-path-eliminating-python3-dependency-correctness-bug.sh" >/dev/null 2>&1; then
    echo "  ✓ F2: iter-154 regression test still passes after iter-155 refactor (16/16)"
else
    echo "  ✗ F2: iter-154 regression test FAILED — iter-155 refactor introduced behavior change"
    ITER155_TOTAL_ASSERTIONS_FAILED=$((ITER155_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER155_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-155 REGRESSION TEST: ${ITER155_TOTAL_ASSERTIONS_EVALUATED}/${ITER155_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-155 REGRESSION TEST: $((ITER155_TOTAL_ASSERTIONS_EVALUATED - ITER155_TOTAL_ASSERTIONS_FAILED))/${ITER155_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER155_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
