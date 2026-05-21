#!/usr/bin/env bash
#MISE description="Iter-151 regression test pinning the long-subject overlay classifier extension to the iter-82 conventional-commits validator. Asserts (a) validator now defines STANDARD_CONVENTIONAL_COMMITS_SUBJECT_HARD_CAP_PER_INDUSTRY_72_CHAR_LIMIT_FROM_ITER_150_CONVENTION_SHIFT=72 constant per iter-150 going-forward convention, (b) validator declares iter-151 overlay counter + diagnostic-line array, (c) validator wires per-commit length measurement INSIDE the standard-conformant branch (overlay, not replacement), (d) validator emits the new summary line for the long-subject bucket, (e) validator emits the iter-151 informational diagnostic block including iter-150 cross-reference and mise-run-release-history pointer, (f) validator remains bash-clean + shellcheck-clean after extension, (g) overlay is INFORMATIONAL — does not contribute to strict-mode blocking total, (h) functional smoke test against actual cc-skills repo emits the new iter-151 summary line and detects existing iter-144-iter-149 long-subject violations."
set -euo pipefail

ITER151_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER151_REPO_ROOT"

ITER151_VALIDATOR_TASK_RELATIVE_PATH=".mise/tasks/audit-recent-git-commit-messages-for-conventional-commits-conformance-to-prevent-silent-semantic-release-skip-of-non-standard-compound-type-scope-prefixes.sh"
ITER151_VALIDATOR_TASK_ABSOLUTE_PATH="$ITER151_REPO_ROOT/$ITER151_VALIDATOR_TASK_RELATIVE_PATH"

ITER151_TOTAL_ASSERTIONS_EVALUATED=0
ITER151_TOTAL_ASSERTIONS_FAILED=0

iter151_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-151 LONG-SUBJECT-OVERLAY-CLASSIFIER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: validator file structurally valid + bash-clean + shellcheck-clean
echo ""
echo "GROUP A (3 assertions): validator file structurally valid"

ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: validator file exists at iter-82 path"
else
    echo "  ✗ A1: validator file missing"
    ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: validator passes bash -n syntax check after iter-151 extension"
else
    echo "  ✗ A2: validator FAILS bash -n syntax check"
    ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: validator passes shellcheck (zero warnings) after iter-151 extension"
    else
        echo "  ✗ A3: validator has shellcheck warnings"
        ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: validator declares iter-151 constant + counter + diagnostic array
echo ""
echo "GROUP B (4 assertions): validator declares iter-151 overlay scaffolding"

iter151_assert_substring_present_in_file \
    "B1: validator defines iter-150 72-char hard-cap constant with iter-150-convention-shift suffix" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "STANDARD_CONVENTIONAL_COMMITS_SUBJECT_HARD_CAP_PER_INDUSTRY_72_CHAR_LIMIT_FROM_ITER_150_CONVENTION_SHIFT=72"

iter151_assert_substring_present_in_file \
    "B2: validator declares iter-151 overlay violation counter zero-initialization" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "total_long_subject_overlay_violations_exceeding_iter150_72_char_hard_cap=0"

iter151_assert_substring_present_in_file \
    "B3: validator declares iter-151 overlay diagnostic-line array with measured-char-count name encoding" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "long_subject_overlay_violation_diagnostic_lines_with_measured_char_count_for_each_offender"

iter151_assert_substring_present_in_file \
    "B4: validator cites conventional-commits.org canonical industry-standard URL in iter-151 block" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "https://www.conventionalcommits.org/"

# ─── Group C: validator wires length-measurement INSIDE standard-conformant branch
echo ""
echo "GROUP C (3 assertions): validator wires per-commit length measurement as overlay (not replacement)"

# Next assertion intentionally references the literal bash-source pattern
# `measured_commit_subject_char_length="${#commit_subject_line}"`. The
# embedded `${#...}` length-expansion in the LABEL string and the embedded
# `${#commit_subject_line}` in the search-string are both LITERAL — they
# must NOT be expanded by the surrounding test harness. SC2154 (var
# referenced but not assigned) and SC2016 (expressions don't expand in
# single quotes) are the desired pin-the-source-pattern behavior here.
# shellcheck disable=SC2154,SC2016
iter151_assert_substring_present_in_file \
    "C1: validator measures subject length via bash dollar-brace-hash length expansion idiom" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    'measured_commit_subject_char_length="${#commit_subject_line}"'

iter151_assert_substring_present_in_file \
    "C2: validator compares measured length against iter-150 72-char hard-cap constant" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "measured_commit_subject_char_length > STANDARD_CONVENTIONAL_COMMITS_SUBJECT_HARD_CAP_PER_INDUSTRY_72_CHAR_LIMIT_FROM_ITER_150_CONVENTION_SHIFT"

iter151_assert_substring_present_in_file \
    "C3: validator increments overlay counter INSIDE the conformant branch (overlay-not-replacement design)" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "total_long_subject_overlay_violations_exceeding_iter150_72_char_hard_cap=\$((total_long_subject_overlay_violations_exceeding_iter150_72_char_hard_cap + 1))"

# ─── Group D: validator emits new summary line + diagnostic block
echo ""
echo "GROUP D (4 assertions): validator emits iter-151 summary + diagnostic output"

iter151_assert_substring_present_in_file \
    "D1: validator emits the iter-151 long-subject summary line with info-only label" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "Long-subject overlay (>72 chars, iter-151 info-only)"

iter151_assert_substring_present_in_file \
    "D2: validator emits the iter-151 diagnostic block header" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "Long-subject overlay (iter-151 informational, >72 chars per iter-150 convention)"

iter151_assert_substring_present_in_file \
    "D3: validator cross-references iter-150 readable-renderer mise task for existing-history view" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "mise run release:history"

iter151_assert_substring_present_in_file \
    "D4: validator clarifies the /loop verbose-self-explanatory directive enumerates IDENTIFIERS not commit subjects" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "enumerates IDENTIFIERS"

# ─── Group E: overlay is INFORMATIONAL — does NOT block strict mode
echo ""
echo "GROUP E (2 assertions): iter-151 overlay is informational — does not contribute to strict-mode blocking total"

# The strict-mode blocking total is computed as:
#   total_violations_blocking_strict_mode=$((total_compound_prefix_violations + total_missing_type_violations))
# iter-151 long-subject overlay MUST NOT appear in this formula.
iter151_assert_substring_present_in_file \
    "E1: strict-mode blocking total formula unchanged (only compound-prefix + missing-type)" \
    "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" \
    "total_violations_blocking_strict_mode=\$(("

# Negative assertion: long-subject counter MUST NOT appear in the strict-mode blocking total formula line.
ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER151_STRICT_BLOCKING_FORMULA_LINE_GREP_RESULT=$(
    grep -A2 "total_violations_blocking_strict_mode=\$((" "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" || true
)
if [[ "$ITER151_STRICT_BLOCKING_FORMULA_LINE_GREP_RESULT" != *"long_subject_overlay"* ]]; then
    echo "  ✓ E2: strict-mode blocking total does NOT include iter-151 long-subject overlay (informational-only design preserved)"
else
    echo "  ✗ E2: strict-mode blocking total ERRONEOUSLY includes long-subject overlay counter"
    ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: functional smoke test against actual cc-skills repo
echo ""
echo "GROUP F (3 assertions): functional smoke test against actual cc-skills repo"

ITER151_VALIDATOR_SMOKE_TEST_OUTPUT_CAPTURE=$(
    bash "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" 2>&1 || true
)

ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER151_VALIDATOR_SMOKE_TEST_OUTPUT_CAPTURE" == *"Long-subject overlay (>72 chars, iter-151 info-only)"* ]]; then
    echo "  ✓ F1: validator emits the iter-151 summary line at runtime"
else
    echo "  ✗ F1: validator did not emit iter-151 summary line"
    ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
fi

# The iter-144-iter-149 cohort produced commit subjects 754-1078 chars.
# The validator MUST detect these as long-subject violations. We assert
# the detected count is ≥1 (allowing for the case where the lookback
# window slides past the cohort over time — the test should not be
# brittle to commit-history advancement).
ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER151_DETECTED_LONG_SUBJECT_COUNT_PARSED_FROM_SMOKE_OUTPUT=$(
    printf '%s\n' "$ITER151_VALIDATOR_SMOKE_TEST_OUTPUT_CAPTURE" \
        | awk -F: '/Long-subject overlay/ { gsub(/[^0-9]/, "", $2); print $2; exit }'
)
ITER151_DETECTED_LONG_SUBJECT_COUNT_PARSED_FROM_SMOKE_OUTPUT="${ITER151_DETECTED_LONG_SUBJECT_COUNT_PARSED_FROM_SMOKE_OUTPUT:-0}"
if [[ "$ITER151_DETECTED_LONG_SUBJECT_COUNT_PARSED_FROM_SMOKE_OUTPUT" -ge 1 ]]; then
    echo "  ✓ F2: validator detected ${ITER151_DETECTED_LONG_SUBJECT_COUNT_PARSED_FROM_SMOKE_OUTPUT} long-subject violation(s) in HEAD~20..HEAD (iter-144-149 cohort visible)"
else
    echo "  ✗ F2: validator detected ZERO long-subject violations — iter-144-149 cohort should produce ≥1"
    ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Validator must still exit 0 in informational mode even with violations.
ITER151_TOTAL_ASSERTIONS_EVALUATED=$((ITER151_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash "$ITER151_VALIDATOR_TASK_ABSOLUTE_PATH" >/dev/null 2>&1; then
    echo "  ✓ F3: validator exits 0 in informational mode despite long-subject violations (correct overlay design)"
else
    echo "  ✗ F3: validator exits non-zero in informational mode (overlay should not gate)"
    ITER151_TOTAL_ASSERTIONS_FAILED=$((ITER151_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER151_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-151 REGRESSION TEST: ${ITER151_TOTAL_ASSERTIONS_EVALUATED}/${ITER151_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-151 REGRESSION TEST: $((ITER151_TOTAL_ASSERTIONS_EVALUATED - ITER151_TOTAL_ASSERTIONS_FAILED))/${ITER151_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER151_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
