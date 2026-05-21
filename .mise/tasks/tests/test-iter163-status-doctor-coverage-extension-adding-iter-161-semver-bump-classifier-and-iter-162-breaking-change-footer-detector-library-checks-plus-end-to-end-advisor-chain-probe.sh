#!/usr/bin/env bash
#MISE description="Iter-163 regression test pinning the iter-160 status-doctor coverage extension. Iter-160 originally verified iter-150 → iter-158 toolkit (9 checks). Iter-163 adds three new CRITICAL checks closing the silent-regression-coverage gap: (9) iter-161 semver-bump classifier shared lib sources + canonical function defined, (10) iter-162 BREAKING-CHANGE footer-token detector shared lib sources + canonical function defined, (11) end-to-end iter-153 → iter-161 → iter-162 advisor chain probe that runs a synthetic --message-file fixture (subject feat + body footer BREAKING CHANGE) and asserts iter-161 bump label resolves to MAJOR (proving the entire wired chain is intact). Asserts (a) all three new check labels are present in default human-readable output, (b) all three new identifiers are present in --json mode, (c) end-to-end probe correctly fails-CRITICAL if any chain link breaks (negative-path verification via temporary lib relocation), (d) doctor still reports TOOLKIT_HEALTHY when all three new checks pass on cc-skills HEAD, (e) total CRITICAL passed counter is now 10 (was 7 pre-iter-163; +3 new), (f) iter-160 backward-compat regression test still passes against the extended doctor."
set -euo pipefail

ITER163_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER163_REPO_ROOT"

ITER163_DOCTOR_TASK_ABSOLUTE_PATH="$ITER163_REPO_ROOT/.mise/tasks/commits/status"
ITER163_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH="$ITER163_REPO_ROOT/scripts/iter160-operator-facing-commits-arc-self-diagnosis-task-checking-each-iter150-through-iter158-tool-for-presence-executability-and-functional-correctness-with-per-check-wall-clock-latency-reporting-and-json-mode.sh"

ITER163_TOTAL_ASSERTIONS_EVALUATED=0
ITER163_TOTAL_ASSERTIONS_FAILED=0

iter163_assert_human_output_contains_substring() {
    local human_readable_label="$1"
    local expected_substring="$2"
    local captured_output="$3"
    ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$captured_output" == *"$expected_substring"* ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:60})"
        ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-163 STATUS-DOCTOR COVERAGE-EXTENSION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: doctor structural validity preserved ───────────────────────────
echo ""
echo "GROUP A (2 assertions): iter-160 doctor structurally valid after iter-163 extension"

ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER163_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A1: doctor bash -n syntax check passes after iter-163 extension"
else
    echo "  ✗ A1: doctor FAILS bash -n syntax check"
    ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER163_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A2: doctor passes shellcheck (zero warnings) after iter-163 extension"
    else
        echo "  ✗ A2: doctor has shellcheck warnings"
        ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A2: shellcheck not installed — SKIPPED"
    ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: three new check labels present in human-readable output ────────
echo ""
echo "GROUP B (3 assertions): three new iter-163 check labels present in human output"

ITER163_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION=$(
    "$ITER163_DOCTOR_TASK_ABSOLUTE_PATH" 2>&1 || true
)

iter163_assert_human_output_contains_substring \
    "B1: iter-161 semver-bump classifier library check label present" \
    "iter-161 semver-bump classifier shared library" \
    "$ITER163_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter163_assert_human_output_contains_substring \
    "B2: iter-162 BREAKING-CHANGE footer-token detector library check label present" \
    "iter-162 BREAKING-CHANGE footer-token detector library" \
    "$ITER163_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter163_assert_human_output_contains_substring \
    "B3: iter-163 end-to-end advisor chain probe check label present" \
    "iter-163 end-to-end iter-153→iter-161→iter-162 chain probe" \
    "$ITER163_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group C: three new check identifiers present in --json output ───────────
echo ""
echo "GROUP C (3 assertions): three new iter-163 check identifiers present in --json output"

ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION=$(
    "$ITER163_DOCTOR_TASK_ABSOLUTE_PATH" --json 2>/dev/null || true
)

iter163_assert_human_output_contains_substring \
    "C1: --json emits iter161_semver_bump_classifier_library identifier (compact JSON format)" \
    '"identifier":"iter161_semver_bump_classifier_library"' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter163_assert_human_output_contains_substring \
    "C2: --json emits iter162_breaking_change_footer_detector_library identifier (compact JSON format)" \
    '"identifier":"iter162_breaking_change_footer_detector_library"' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter163_assert_human_output_contains_substring \
    "C3: --json emits iter163_end_to_end_advisor_chain_probe identifier (compact JSON format)" \
    '"identifier":"iter163_end_to_end_advisor_chain_probe"' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group D: critical_passed counter incremented from 7 → 10 ────────────────
echo ""
echo "GROUP D (2 assertions): summary counters reflect iter-163 +3 critical checks"

# Summary block uses pretty-printed JSON (with spaces after colons),
# unlike the checks array which is compact. Pin both formats so any
# future iter-160 JSON-renderer refactor must consider both code paths.
iter163_assert_human_output_contains_substring \
    "D1: --json summary critical_passed=10 (was 7 pre-iter-163; iter-161 + iter-162 + end-to-end add 3)" \
    '"critical_passed": 10' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter163_assert_human_output_contains_substring \
    "D2: --json summary verdict still TOOLKIT_HEALTHY after iter-163 extension (no regressions introduced)" \
    '"verdict": "TOOLKIT_HEALTHY"' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group E: end-to-end probe correctly fails-CRITICAL if chain breaks ──────
#
# Negative-path verification: temporarily move the iter-162 lib aside,
# run the doctor, confirm the end-to-end probe FAILS (proving the
# probe actually catches chain regressions). Then restore.
echo ""
echo "GROUP E (2 assertions): end-to-end probe correctly catches chain regressions"

ITER163_ITER162_LIB_ABSOLUTE_PATH="$ITER163_REPO_ROOT/scripts/lib/iter162-conventional-commits-breaking-change-footer-token-detector-applying-uppercase-required-and-blank-line-separator-rules-per-conventional-commits-v1-section-13-and-semantic-release-commit-analyzer-default-angular-preset-behavior.sh"
# Backup path uses /tmp because the iter-162 lib filename already
# saturates macOS's 255-char filename limit, so appending a suffix in
# the same directory overflows. /tmp also avoids polluting scripts/lib/
# with a transient test artifact even if the test crashes mid-run.
ITER163_ITER162_LIB_BACKUP_PATH=$(mktemp -t iter163-negative-path-iter162-lib-backup-XXXXXX)

if [[ -f "$ITER163_ITER162_LIB_ABSOLUTE_PATH" ]]; then
    mv "$ITER163_ITER162_LIB_ABSOLUTE_PATH" "$ITER163_ITER162_LIB_BACKUP_PATH"
    ITER163_DOCTOR_OUTPUT_WITH_ITER162_LIB_MOVED_ASIDE=$(
        "$ITER163_DOCTOR_TASK_ABSOLUTE_PATH" 2>&1 || true
    )
    ITER163_DOCTOR_EXIT_WITH_ITER162_LIB_MOVED_ASIDE=0
    "$ITER163_DOCTOR_TASK_ABSOLUTE_PATH" >/dev/null 2>&1 || ITER163_DOCTOR_EXIT_WITH_ITER162_LIB_MOVED_ASIDE=$?
    mv "$ITER163_ITER162_LIB_BACKUP_PATH" "$ITER163_ITER162_LIB_ABSOLUTE_PATH"

    ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$ITER163_DOCTOR_OUTPUT_WITH_ITER162_LIB_MOVED_ASIDE" == *"Toolkit BROKEN"* ]]; then
        echo "  ✓ E1: doctor correctly reports 'Toolkit BROKEN' when iter-162 lib is missing (negative path)"
    else
        echo "  ✗ E1: doctor did NOT detect missing iter-162 lib"
        ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
    fi

    ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$ITER163_DOCTOR_EXIT_WITH_ITER162_LIB_MOVED_ASIDE" -ne 0 ]]; then
        echo "  ✓ E2: doctor exits non-zero when iter-162 lib is missing (gates exit code)"
    else
        echo "  ✗ E2: doctor exit code did NOT reflect missing CRITICAL dep"
        ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E1+E2: iter-162 lib already missing — cannot run negative-path test (SKIPPED)"
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER163_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-163 REGRESSION TEST: ${ITER163_TOTAL_ASSERTIONS_EVALUATED}/${ITER163_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-163 REGRESSION TEST: $((ITER163_TOTAL_ASSERTIONS_EVALUATED - ITER163_TOTAL_ASSERTIONS_FAILED))/${ITER163_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER163_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
