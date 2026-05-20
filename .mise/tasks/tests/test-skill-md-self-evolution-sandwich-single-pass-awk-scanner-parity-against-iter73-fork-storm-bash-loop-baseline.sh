#!/usr/bin/env bash
#MISE description="Iter-74 regression test for scripts/skill-md-self-evolution-sandwich-single-pass-awk-scanner.awk. Synthesizes 4 fixture SKILL.md files exercising every audit-rule path (clean+top-missing+bottom-missing+bottom-not-at-end) and asserts the scanner's TSV output matches the iter-73 bash-loop reference semantics. Catches regressions in the perf-driven fork-storm replacement BEFORE release publishes a tag deploying the broken scanner to operator Layer 3 caches (see iter-42 docs/HOOKS.md for cache lifecycle)."

# Iter-74 parity regression test for the single-pass awk scanner that
# replaces the iter-73-baseline 217-file × ~8-fork-exec-per-file storm
# in `.mise/tasks/release/preflight` Check 4b (self-evolution sandwich).
#
# The scanner-under-test:
#   scripts/skill-md-self-evolution-sandwich-single-pass-awk-scanner.awk
#
# This test asserts that the scanner's TSV output (columns: filename,
# has_self_evolving_marker_in_top25_body_lines, last_post_execution_
# reflection_line_number, total_line_count_for_file) is semantically
# equivalent to the iter-73 bash-loop reference for every audit-rule
# path:
#
#   1. CLEAN: top reminder present + bottom reflection within last 15 lines
#   2. TOP-MISSING: no "self-evolv" in first 25 body lines
#   3. BOTTOM-MISSING: no "## Post-Execution Reflection" anywhere
#   4. BOTTOM-NOT-AT-END: reflection present but >15 lines from EOF

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCANNER_AWK_SCRIPT_PATH="$REPO_ROOT/scripts/skill-md-self-evolution-sandwich-single-pass-awk-scanner.awk"

if [[ ! -f "$SCANNER_AWK_SCRIPT_PATH" ]]; then
    echo "FAIL: Scanner awk script not found at expected path: $SCANNER_AWK_SCRIPT_PATH"
    exit 1
fi

# Synthesize fixtures in a temp dir cleaned up on exit.
FIXTURE_TEMP_DIR_FOR_ITER74_PARITY_TEST=$(mktemp -d -t iter74-sandwich-scanner-parity-fixtures.XXXXXX)
trap 'rm -rf "$FIXTURE_TEMP_DIR_FOR_ITER74_PARITY_TEST"' EXIT

# --- Fixture 1: CLEAN (top + bottom both present and within bounds) ---
FIXTURE_CLEAN_SKILL_MD_PATH="$FIXTURE_TEMP_DIR_FOR_ITER74_PARITY_TEST/fixture-1-clean-SKILL.md"
cat > "$FIXTURE_CLEAN_SKILL_MD_PATH" <<'EOF_FIXTURE_1_CLEAN_TOP_AND_BOTTOM_BOTH_PRESENT'
---
name: clean-fixture
description: A fixture with valid self-evolution sandwich
---

# Clean Fixture

This skill is **Self-Evolving** — it adapts based on usage.

Some other content goes here.

## Post-Execution Reflection

Reflect on what happened.
EOF_FIXTURE_1_CLEAN_TOP_AND_BOTTOM_BOTH_PRESENT

# --- Fixture 2: TOP-MISSING (no "self-evolv" in first 25 body lines) ---
FIXTURE_TOP_MISSING_SKILL_MD_PATH="$FIXTURE_TEMP_DIR_FOR_ITER74_PARITY_TEST/fixture-2-top-missing-SKILL.md"
cat > "$FIXTURE_TOP_MISSING_SKILL_MD_PATH" <<'EOF_FIXTURE_2_TOP_MARKER_ABSENT'
---
name: top-missing-fixture
description: A fixture without the Self-Evolving reminder
---

# Top-Missing Fixture

This skill has no self-evolution marker at the top.

## Post-Execution Reflection

Reflect on what happened.
EOF_FIXTURE_2_TOP_MARKER_ABSENT

# --- Fixture 3: BOTTOM-MISSING (no "## Post-Execution Reflection" anywhere) ---
FIXTURE_BOTTOM_MISSING_SKILL_MD_PATH="$FIXTURE_TEMP_DIR_FOR_ITER74_PARITY_TEST/fixture-3-bottom-missing-SKILL.md"
cat > "$FIXTURE_BOTTOM_MISSING_SKILL_MD_PATH" <<'EOF_FIXTURE_3_BOTTOM_HEADING_ABSENT'
---
name: bottom-missing-fixture
description: A fixture without the Post-Execution Reflection heading
---

# Bottom-Missing Fixture

This skill is **Self-Evolving** and adapts.

No reflection section here.
EOF_FIXTURE_3_BOTTOM_HEADING_ABSENT

# --- Fixture 4: BOTTOM-NOT-AT-END (reflection >15 lines from EOF) ---
# Construct a file where "## Post-Execution Reflection" appears followed
# by 20 trailing body lines (>15) so the distance check fires.
FIXTURE_BOTTOM_NOT_AT_END_SKILL_MD_PATH="$FIXTURE_TEMP_DIR_FOR_ITER74_PARITY_TEST/fixture-4-bottom-not-at-end-SKILL.md"
{
    cat <<'EOF_FIXTURE_4_HEADER_AND_TOP_AND_REFLECTION'
---
name: bottom-not-at-end-fixture
description: A fixture where Post-Execution Reflection is too far from EOF
---

# Bottom-Not-At-End Fixture

This skill is **Self-Evolving** and adapts.

## Post-Execution Reflection

Reflect on what happened. But this section is NOT at the bottom of the file.
EOF_FIXTURE_4_HEADER_AND_TOP_AND_REFLECTION
    # Append 20 trailing body lines AFTER the reflection heading
    for trailing_line_index in $(seq 1 20); do
        echo "Trailing line $trailing_line_index that should push the reflection heading out of the last-15-lines window."
    done
} > "$FIXTURE_BOTTOM_NOT_AT_END_SKILL_MD_PATH"

# Run the scanner over all 4 fixtures.
SCANNER_TSV_OUTPUT_FOR_FOUR_FIXTURES=$(awk -f "$SCANNER_AWK_SCRIPT_PATH" \
    "$FIXTURE_CLEAN_SKILL_MD_PATH" \
    "$FIXTURE_TOP_MISSING_SKILL_MD_PATH" \
    "$FIXTURE_BOTTOM_MISSING_SKILL_MD_PATH" \
    "$FIXTURE_BOTTOM_NOT_AT_END_SKILL_MD_PATH")

# Assertions. The TSV row format is:
#   <filename>\t<has_self_evolving:0|1>\t<last_post_exec_line:0=missing>\t<total_lines>
ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=0
ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=0

assert_scanner_row_matches_expected_audit_facts() {
    local fixture_label_for_diagnostic="$1"
    local fixture_filename_to_grep_in_tsv="$2"
    local expected_has_self_evolving="$3"
    local expected_last_post_exec_nonzero_pattern="$4"  # "zero" or "nonzero"
    local expected_violates_distance_check="$5"          # "yes" or "no" — only valid if last_post_exec is nonzero

    local matched_tsv_row
    matched_tsv_row=$(echo "$SCANNER_TSV_OUTPUT_FOR_FOUR_FIXTURES" | grep -F "$fixture_filename_to_grep_in_tsv" || true)
    if [[ -z "$matched_tsv_row" ]]; then
        echo "  ✗ $fixture_label_for_diagnostic: no scanner TSV row found for fixture $fixture_filename_to_grep_in_tsv"
        ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
        return
    fi

    local actual_has_self_evolving actual_last_post_exec actual_total_lines
    actual_has_self_evolving=$(echo "$matched_tsv_row" | awk -F'\t' '{print $2}')
    actual_last_post_exec=$(echo "$matched_tsv_row" | awk -F'\t' '{print $3}')
    actual_total_lines=$(echo "$matched_tsv_row" | awk -F'\t' '{print $4}')

    # Assertion A: has_self_evolving column matches expectation
    if [[ "$actual_has_self_evolving" != "$expected_has_self_evolving" ]]; then
        echo "  ✗ $fixture_label_for_diagnostic: expected has_self_evolving=$expected_has_self_evolving, got $actual_has_self_evolving"
        ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
    else
        ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST + 1))
    fi

    # Assertion B: last_post_exec is zero vs nonzero
    if [[ "$expected_last_post_exec_nonzero_pattern" == "zero" ]]; then
        if [[ "$actual_last_post_exec" != "0" ]]; then
            echo "  ✗ $fixture_label_for_diagnostic: expected last_post_exec=0 (missing), got $actual_last_post_exec"
            ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
        else
            ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST + 1))
        fi
    elif [[ "$expected_last_post_exec_nonzero_pattern" == "nonzero" ]]; then
        if [[ "$actual_last_post_exec" == "0" ]]; then
            echo "  ✗ $fixture_label_for_diagnostic: expected last_post_exec>0 (present), got 0"
            ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
        else
            ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST + 1))
        fi
    fi

    # Assertion C: distance check (only when last_post_exec is nonzero)
    if [[ "$actual_last_post_exec" != "0" ]]; then
        local actual_distance_from_eof=$((actual_total_lines - actual_last_post_exec))
        if [[ "$expected_violates_distance_check" == "yes" ]]; then
            if [[ "$actual_distance_from_eof" -le 15 ]]; then
                echo "  ✗ $fixture_label_for_diagnostic: expected distance>15 (violates), got $actual_distance_from_eof"
                ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
            else
                ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST + 1))
            fi
        elif [[ "$expected_violates_distance_check" == "no" ]]; then
            if [[ "$actual_distance_from_eof" -gt 15 ]]; then
                echo "  ✗ $fixture_label_for_diagnostic: expected distance≤15 (ok), got $actual_distance_from_eof"
                ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
            else
                ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST + 1))
            fi
        fi
    fi
}

assert_scanner_row_matches_expected_audit_facts \
    "Fixture 1 CLEAN" "fixture-1-clean-SKILL.md" \
    "1" "nonzero" "no"

assert_scanner_row_matches_expected_audit_facts \
    "Fixture 2 TOP-MISSING" "fixture-2-top-missing-SKILL.md" \
    "0" "nonzero" "no"

assert_scanner_row_matches_expected_audit_facts \
    "Fixture 3 BOTTOM-MISSING" "fixture-3-bottom-missing-SKILL.md" \
    "1" "zero" "no"

assert_scanner_row_matches_expected_audit_facts \
    "Fixture 4 BOTTOM-NOT-AT-END" "fixture-4-bottom-not-at-end-SKILL.md" \
    "1" "nonzero" "yes"

# Live marketplace parity check: the scanner against the real 217 SKILL.md
# files should produce ZERO violations (current marketplace is sandwich-
# complete per iter-73 preflight green). This guards against the scanner
# silently producing different counts than the iter-73 bash loop.
LIVE_TSV_OUTPUT_FROM_SCANNER=$(awk -f "$SCANNER_AWK_SCRIPT_PATH" "$REPO_ROOT"/plugins/*/skills/*/SKILL.md)
LIVE_VIOLATION_COUNT_AS_BASH_LOOP_WOULD_SEE_IT=$(echo "$LIVE_TSV_OUTPUT_FROM_SCANNER" | awk -F'\t' '
$2 == 0 { missing_top++ }
$3 == 0 { missing_bottom++ }
$3 > 0 && ($4 - $3) > 15 { not_at_bottom++ }
END {
    print (missing_top+0) + (missing_bottom+0) + (not_at_bottom+0)
}')
LIVE_FILES_SCANNED=$(echo "$LIVE_TSV_OUTPUT_FROM_SCANNER" | wc -l | tr -d ' ')

if [[ "$LIVE_VIOLATION_COUNT_AS_BASH_LOOP_WOULD_SEE_IT" != "0" ]]; then
    echo "  ✗ Live marketplace parity: scanner reports $LIVE_VIOLATION_COUNT_AS_BASH_LOOP_WOULD_SEE_IT violations across $LIVE_FILES_SCANNED files; expected 0 (iter-73 preflight was green)"
    ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST + 1))
else
    ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST + 1))
fi

if [[ "$LIVE_FILES_SCANNED" != "217" ]]; then
    echo "  ⚠ Live marketplace parity: scanner emitted $LIVE_FILES_SCANNED rows; iter-73 baseline measured 217 SKILL.md files. If marketplace has grown/shrunk, update this assertion."
    # Not a hard fail — just a warning. The exact count drifts as plugins evolve.
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Iter-74 sandwich-scanner parity test"
echo "═══════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST"
echo "  Live files scanned: $LIVE_FILES_SCANNED"
echo "  Live violations: $LIVE_VIOLATION_COUNT_AS_BASH_LOOP_WOULD_SEE_IT"
echo "═══════════════════════════════════════════════════════════"

if [[ "$ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED_FOR_ITER74_PARITY_TEST assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED_FOR_ITER74_PARITY_TEST assertions passed"
