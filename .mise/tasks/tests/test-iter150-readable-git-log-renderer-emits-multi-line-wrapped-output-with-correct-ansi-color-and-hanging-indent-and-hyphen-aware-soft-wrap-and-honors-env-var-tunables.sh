#!/usr/bin/env bash
#MISE description="Iter-150 regression test pinning the readable-git-log-renderer wrapper. Asserts (a) renderer script exists + executable + bash-syntax-clean + shellcheck-clean, (b) renderer uses awk per the cc-skills CLAUDE.md 'Terminal text unwrapping: awk only' principle (rejects par/fmt/fold/pandoc/textwrap/pysbd), (c) renderer honors ITER150_COMMIT_COUNT_TO_DISPLAY + ITER150_SOFT_WRAP_COLUMN_WIDTH + ITER150_CONTINUATION_INDENT env-var tunables, (d) renderer implements hyphen-replacement so verbose kebab-cased subjects soft-wrap on word boundaries (the iter-144-through-iter-149 cohort would otherwise dump as 1000-char unbroken lines), (e) renderer parses conventional-commit type-scope prefix correctly with double-colon defect fixed (RLENGTH-2 strips both colon and space), (f) functional smoke test against the actual cc-skills repo emits expected multi-line readable output for the iter-149 commit which was 1078 chars on one line in the underlying git history, (g) .mise/tasks/release/history mise task wrapper exists + delegates to the renderer via exec."
set -euo pipefail

ITER150_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER150_REPO_ROOT"

ITER150_RENDERER_SCRIPT_RELATIVE_PATH="scripts/iter150-readable-git-log-renderer-with-awk-based-soft-wrap-of-verbose-conventional-commit-subjects-to-eighty-column-terminal-width-with-color-decorations-and-indentation-for-operator-readability.sh"
ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH="$ITER150_REPO_ROOT/$ITER150_RENDERER_SCRIPT_RELATIVE_PATH"
ITER150_MISE_TASK_WRAPPER_RELATIVE_PATH=".mise/tasks/release/history"
ITER150_MISE_TASK_WRAPPER_ABSOLUTE_PATH="$ITER150_REPO_ROOT/$ITER150_MISE_TASK_WRAPPER_RELATIVE_PATH"

ITER150_TOTAL_ASSERTIONS_EVALUATED=0
ITER150_TOTAL_ASSERTIONS_FAILED=0

iter150_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter150_assert_filesystem_predicate_holds() {
    local human_readable_assertion_label="$1"
    local bash_test_expression="$2"
    ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    failed bash predicate: $bash_test_expression"
        ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-150 READABLE-GIT-LOG-RENDERER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Renderer structural validity ──────────────────────────────────
echo ""
echo "GROUP A (4 assertions): Renderer script structurally valid"

iter150_assert_filesystem_predicate_holds \
    "A1: renderer exists at iter-150 verbose path" \
    "-f \"$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH\""

iter150_assert_filesystem_predicate_holds \
    "A2: renderer is executable (chmod +x)" \
    "-x \"$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH\""

ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A3: renderer passes bash -n syntax check"
else
    echo "  ✗ A3: renderer FAILS bash -n syntax check"
    ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A4: renderer passes shellcheck (zero warnings)"
    else
        echo "  ✗ A4: renderer has shellcheck warnings"
        ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A4: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: Renderer implementation invariants ────────────────────────────
echo ""
echo "GROUP B (5 assertions): Renderer implementation pins critical invariants"

iter150_assert_substring_present_in_file \
    "B1: renderer uses awk per CLAUDE.md Terminal-text-unwrapping awk-only principle (matches both bare 'awk' and iter-173 'LC_ALL=C awk' envelope forms via the awk-with-line-continuation invariant signature)" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "awk \\"

iter150_assert_substring_present_in_file \
    "B2: renderer honors ITER150_COMMIT_COUNT_TO_DISPLAY env-var tunable" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER150_COMMIT_COUNT_TO_DISPLAY"

iter150_assert_substring_present_in_file \
    "B3: renderer honors ITER150_SOFT_WRAP_COLUMN_WIDTH env-var tunable" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER150_SOFT_WRAP_COLUMN_WIDTH"

iter150_assert_substring_present_in_file \
    "B4: renderer honors ITER150_CONTINUATION_INDENT env-var tunable" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "ITER150_CONTINUATION_INDENT"

iter150_assert_substring_present_in_file \
    "B5: renderer implements hyphen-replacement so kebab-cased verbose subjects soft-wrap" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "iter150_replace_hyphens_with_spaces_so_verbose_kebab_case_descriptions_can_soft_wrap_on_word_boundaries"

# ─── Group C: Conventional-commit grammar parser correctness ───────────────
echo ""
echo "GROUP C (2 assertions): Conventional-commit parser correctness"

# shellcheck disable=SC2016
iter150_assert_substring_present_in_file \
    "C1: renderer matches conventional-commit type-scope-colon prefix grammar (a-zA-Z type prefix regex)" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    '/^[a-zA-Z]+(\([^)]+\))?!?:'

iter150_assert_substring_present_in_file \
    "C2: renderer strips trailing colon+space (RLENGTH-2) to prevent double-colon defect" \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" \
    "RLENGTH - 2"

# ─── Group D: Functional smoke test against actual cc-skills repo ──────────
echo ""
echo "GROUP D (3 assertions): Functional smoke test emits expected readable output"

ITER150_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST=$(
    ITER150_COMMIT_COUNT_TO_DISPLAY=10 \
    ITER150_SOFT_WRAP_COLUMN_WIDTH=80 \
    "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH" 2>&1 || true
)

ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER150_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"ITER-150 READABLE GIT LOG"* ]]; then
    echo "  ✓ D1: renderer emits banner header"
else
    echo "  ✗ D1: renderer banner header missing"
    ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER150_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" == *"tune via ITER150_COMMIT_COUNT_TO_DISPLAY"* ]]; then
    echo "  ✓ D2: renderer emits operator-tunable knob hints in footer"
else
    echo "  ✗ D2: renderer footer knob hints missing"
    ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Critical functional test: verify the iter-149 commit subject (1078 chars
# raw) now renders wrapped. We measure ONLY the indented continuation lines
# (lines starting with 8 spaces) — these are the wrapped subject body, the
# actual product of the awk soft-wrap. The banner, footer, and the verbose
# iter-150 script-path-in-footer-example all contain long lines that aren't
# subject to wrap and would pollute the measurement.
ITER150_TOTAL_ASSERTIONS_EVALUATED=$((ITER150_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY=$(
    printf '%s\n' "$ITER150_RENDERER_OUTPUT_CAPTURE_FOR_SMOKE_TEST" \
        | grep -E '^        [^ ]' \
        | awk '{ print length($0) }' \
        | sort -rn \
        | head -1
)
ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY="${ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY:-0}"
# Wrap target is 80; indented lines should be ≤ 80+ANSI-overhead. 120 is
# a safe ceiling that comfortably catches both the un-wrapped 1078-char
# defect and the per-test-machine ANSI escape variability.
if [[ "$ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY" -gt 0 ]] && [[ "$ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY" -lt 120 ]]; then
    echo "  ✓ D3: max wrapped-subject continuation line length is ${ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY} chars < 120 (wrap working — was 1078 char raw)"
else
    echo "  ✗ D3: max wrapped-subject continuation line length = ${ITER150_MAX_WRAPPED_SUBJECT_LINE_LENGTH_FROM_INDENTED_CONTINUATION_LINES_ONLY} chars — wrap not working or no continuation lines emitted"
    ITER150_TOTAL_ASSERTIONS_FAILED=$((ITER150_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: mise task wrapper structurally valid ─────────────────────────
echo ""
echo "GROUP E (4 assertions): mise task wrapper delegates to renderer correctly"

iter150_assert_filesystem_predicate_holds \
    "E1: mise release:history task file exists" \
    "-f \"$ITER150_MISE_TASK_WRAPPER_ABSOLUTE_PATH\""

iter150_assert_filesystem_predicate_holds \
    "E2: mise release:history task file is executable" \
    "-x \"$ITER150_MISE_TASK_WRAPPER_ABSOLUTE_PATH\""

# Single-quoted literal search string on next assertion intentionally
# preserves the `$VARNAME` dollar-sign as part of the substring being
# searched for in the source file. Shellcheck SC2016 is the desired
# behavior here (we WANT literal dollar-sign).
# shellcheck disable=SC2016
iter150_assert_substring_present_in_file \
    "E3: mise release:history task delegates to iter-150 renderer via exec for clean signal propagation" \
    "$ITER150_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    'exec "$ITER150_RENDERER_SCRIPT_ABSOLUTE_PATH"'

iter150_assert_substring_present_in_file \
    "E4: mise release:history task has MISE description metadata for mise-tasks-listing discoverability" \
    "$ITER150_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    "#MISE description="

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER150_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-150 REGRESSION TEST: ${ITER150_TOTAL_ASSERTIONS_EVALUATED}/${ITER150_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-150 REGRESSION TEST: $((ITER150_TOTAL_ASSERTIONS_EVALUATED - ITER150_TOTAL_ASSERTIONS_FAILED))/${ITER150_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER150_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
