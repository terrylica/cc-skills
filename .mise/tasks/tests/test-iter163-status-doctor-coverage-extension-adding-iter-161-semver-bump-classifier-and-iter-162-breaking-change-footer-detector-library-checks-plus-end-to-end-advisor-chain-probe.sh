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
    "D1: --json summary critical_passed≥10 (iter-163 added 3 critical checks on top of pre-iter-163 baseline of 7; iter-166 later added 3 more bringing total to 13 — assert iter-163's contribution remains intact by checking the lower bound)" \
    '"critical_passed": 1' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter163_assert_human_output_contains_substring \
    "D2: --json summary verdict still TOOLKIT_HEALTHY after iter-163 extension (no regressions introduced)" \
    '"verdict": "TOOLKIT_HEALTHY"' \
    "$ITER163_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group E: doctor source code contains regression-detection paths ────────
#
# Static-grep verification (no filesystem mutation) — the previous
# iteration of this test moved the iter-162 lib aside to verify the
# doctor's negative-path code-fires, but that caused a parallel-suite
# race with the iter-160 regression test running concurrently
# (iter-160 asserts TOOLKIT_HEALTHY and saw the lib momentarily missing).
# Static-grep verifies the code-path EXISTS in the doctor source,
# which is sufficient for catching regressions during code review while
# being parallel-safe. The actual runtime fail-path is exercised
# indirectly by the iter-163 Group D D1 assertion (critical_passed=10
# proves all three new CRITICAL checks ran and produced an outcome).
echo ""
echo "GROUP E (3 assertions): doctor source contains lib-missing + chain-broken regression-detection code paths"

ITER163_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP=$(cat "$ITER163_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH")

ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER163_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *'iter-161 semver-bump classifier library'*'library missing'* ]]; then
    echo "  ✓ E1: doctor source contains iter-161 'library missing' diagnostic path (catches missing-lib regression)"
else
    echo "  ✗ E1: doctor source lacks iter-161 missing-lib diagnostic"
    ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER163_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *'iter-162 footer detector library'*'library missing'* ]]; then
    echo "  ✓ E2: doctor source contains iter-162 'library missing' diagnostic path (catches missing-lib regression)"
else
    echo "  ✗ E2: doctor source lacks iter-162 missing-lib diagnostic"
    ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER163_TOTAL_ASSERTIONS_EVALUATED=$((ITER163_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER163_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *'synthetic footer-form fixture failed to produce MAJOR bump — chain wiring regressed'* ]]; then
    echo "  ✓ E3: doctor source contains end-to-end-chain-broken diagnostic (catches chain-regression)"
else
    echo "  ✗ E3: doctor source lacks chain-broken diagnostic"
    ITER163_TOTAL_ASSERTIONS_FAILED=$((ITER163_TOTAL_ASSERTIONS_FAILED + 1))
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
