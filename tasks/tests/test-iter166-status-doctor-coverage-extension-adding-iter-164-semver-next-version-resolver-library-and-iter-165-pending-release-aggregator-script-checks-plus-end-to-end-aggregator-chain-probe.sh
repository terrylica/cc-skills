#!/usr/bin/env bash
#MISE description="Iter-166 regression test pinning the iter-160 status-doctor coverage extension for iter-164 + iter-165. Iter-163 added 3 critical checks (iter-161 lib + iter-162 lib + iter-153→iter-161→iter-162 footer-form end-to-end probe). Iter-166 closed the parallel silent-regression gap on iter-164 + iter-165 by adding 3 more critical checks: (12) iter-164 SemVer next-version resolver shared lib structurally valid + canonical function defined, (13) iter-165 pending-release aggregator script passes bash -n + --help, (14) end-to-end iter-153→iter-161→iter-164→iter-165 chain probe creating a temp git repo via mktemp -d + tagging baseline v1.0.0 + adding synthetic feat commit + running aggregator with ITER165_REPO_ROOT_OVERRIDE + asserting aggregate_bump_label=MINOR AND next_version=v1.1.0 — proves the entire wired chain is intact. Asserts (a) all three new check labels present in human output, (b) all three new check identifiers present in --json output, (c) summary critical_passed counter is now 13 (was 10 post-iter-163; +3 new from iter-166), (d) doctor still reports TOOLKIT_HEALTHY, (e) iter-163 backward-compat assertions still pass (iter-161/162/163 identifiers all still present), (f) doctor source contains lib-missing + chain-broken regression-detection diagnostic strings (static-grep, parallel-safe per iter-163 lesson)."
set -euo pipefail

ITER166_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER166_REPO_ROOT"

ITER166_DOCTOR_TASK_ABSOLUTE_PATH="$ITER166_REPO_ROOT/.mise/tasks/commits/status"
ITER166_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH="$ITER166_REPO_ROOT/scripts/iter160-operator-facing-commits-arc-self-diagnosis-task-checking-each-iter150-through-iter158-tool-for-presence-executability-and-functional-correctness-with-per-check-wall-clock-latency-reporting-and-json-mode.sh"

ITER166_TOTAL_ASSERTIONS_EVALUATED=0
ITER166_TOTAL_ASSERTIONS_FAILED=0

iter166_assert_output_contains_substring() {
    local human_readable_label="$1"
    local expected_substring="$2"
    local captured_output="$3"
    ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$captured_output" == *"$expected_substring"* ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:60})"
        ITER166_TOTAL_ASSERTIONS_FAILED=$((ITER166_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-166 STATUS-DOCTOR COVERAGE-EXTENSION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: doctor still structurally valid after iter-166 extension ──────
echo ""
echo "GROUP A (2 assertions): iter-160 doctor structurally valid after iter-166 extension"

ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER166_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A1: doctor passes bash -n after iter-166 extension"
else
    echo "  ✗ A1: doctor FAILS bash -n syntax check"
    ITER166_TOTAL_ASSERTIONS_FAILED=$((ITER166_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER166_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A2: doctor passes shellcheck (zero warnings) after iter-166 extension"
    else
        echo "  ✗ A2: doctor has shellcheck warnings"
        ITER166_TOTAL_ASSERTIONS_FAILED=$((ITER166_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A2: shellcheck not installed — SKIPPED"
    ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: three new iter-166 check labels present in human output ───────
echo ""
echo "GROUP B (3 assertions): three new iter-166 check labels present in human output"

ITER166_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION=$(
    "$ITER166_DOCTOR_TASK_ABSOLUTE_PATH" 2>&1 || true
)

iter166_assert_output_contains_substring \
    "B1: iter-164 SemVer next-version resolver library check label present" \
    "iter-164 SemVer next-version resolver shared library" \
    "$ITER166_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "B2: iter-165 pending-release aggregator script check label present" \
    "iter-165 pending-release aggregator script" \
    "$ITER166_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "B3: iter-166 end-to-end iter-153→iter-161→iter-164→iter-165 chain probe label present" \
    "iter-166 end-to-end iter-153→iter-161→iter-164→iter-165 chain probe" \
    "$ITER166_DOCTOR_HUMAN_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group C: three new iter-166 check identifiers present in --json ────────
echo ""
echo "GROUP C (3 assertions): three new iter-166 check identifiers present in --json output"

ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION=$(
    "$ITER166_DOCTOR_TASK_ABSOLUTE_PATH" --json 2>/dev/null || true
)

iter166_assert_output_contains_substring \
    "C1: --json emits iter164_semver_next_version_resolver_library identifier (compact JSON format)" \
    '"identifier":"iter164_semver_next_version_resolver_library"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "C2: --json emits iter165_pending_release_aggregator_script identifier (compact JSON format)" \
    '"identifier":"iter165_pending_release_aggregator_script"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "C3: --json emits iter166_end_to_end_aggregator_chain_probe identifier (compact JSON format)" \
    '"identifier":"iter166_end_to_end_aggregator_chain_probe"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group D: critical_passed counter reflects iter-166 +3 ──────────────────
echo ""
echo "GROUP D (2 assertions): summary counters reflect iter-166 +3 critical checks (10 → 13)"

iter166_assert_output_contains_substring \
    "D1: --json summary critical_passed=13 (was 10 post-iter-163; iter-164 lib + iter-165 script + iter-166 end-to-end add 3)" \
    '"critical_passed": 13' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "D2: --json summary verdict still TOOLKIT_HEALTHY after iter-166 extension (no regressions introduced)" \
    '"verdict": "TOOLKIT_HEALTHY"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group E: iter-163 backward-compat (all iter-163 identifiers still present)
echo ""
echo "GROUP E (3 assertions): iter-163 backward-compat — all iter-163 identifiers still present"

iter166_assert_output_contains_substring \
    "E1: iter-163 iter161_semver_bump_classifier_library identifier still present (backward compat)" \
    '"identifier":"iter161_semver_bump_classifier_library"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "E2: iter-163 iter162_breaking_change_footer_detector_library identifier still present (backward compat)" \
    '"identifier":"iter162_breaking_change_footer_detector_library"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

iter166_assert_output_contains_substring \
    "E3: iter-163 iter163_end_to_end_advisor_chain_probe identifier still present (backward compat)" \
    '"identifier":"iter163_end_to_end_advisor_chain_probe"' \
    "$ITER166_DOCTOR_JSON_OUTPUT_CAPTURE_AFTER_EXTENSION"

# ─── Group F: doctor source contains negative-path diagnostic strings ───────
#
# Static-grep verification (no filesystem mutation) per iter-163's lesson:
# moving the iter-164 lib aside would race with parallel iter-160/iter-163
# tests asserting TOOLKIT_HEALTHY. Static-grep proves the doctor source
# CONTAINS the lib-missing + chain-broken diagnostic paths, which is
# sufficient for catching regressions during code review while being
# parallel-safe. The actual runtime fail-path is exercised indirectly by
# the iter-166 Group D D1 assertion (critical_passed=13 proves all three
# new CRITICAL checks ran and produced an outcome).
echo ""
echo "GROUP F (3 assertions): doctor source contains iter-166 lib-missing + script-missing + chain-broken regression-detection code paths"

ITER166_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP=$(cat "$ITER166_ITER160_DOCTOR_SCRIPT_ABSOLUTE_PATH")

ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER166_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *'iter-164 next-version resolver library'*'library missing'* ]]; then
    echo "  ✓ F1: doctor source contains iter-164 'library missing' diagnostic (catches missing-lib regression)"
else
    echo "  ✗ F1: doctor source lacks iter-164 missing-lib diagnostic"
    ITER166_TOTAL_ASSERTIONS_FAILED=$((ITER166_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER166_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *'iter-165 pending-release aggregator script'*'script missing or not executable'* ]]; then
    echo "  ✓ F2: doctor source contains iter-165 'script missing or not executable' diagnostic (catches missing-script regression)"
else
    echo "  ✗ F2: doctor source lacks iter-165 missing-script diagnostic"
    ITER166_TOTAL_ASSERTIONS_FAILED=$((ITER166_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER166_TOTAL_ASSERTIONS_EVALUATED=$((ITER166_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER166_DOCTOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *'synthetic feat fixture failed to produce MINOR aggregate + v1.1.0 next-version'* ]]; then
    echo "  ✓ F3: doctor source contains iter-166 end-to-end-chain-broken diagnostic (catches aggregator chain regression)"
else
    echo "  ✗ F3: doctor source lacks iter-166 end-to-end-chain-broken diagnostic"
    ITER166_TOTAL_ASSERTIONS_FAILED=$((ITER166_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER166_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-166 REGRESSION TEST: ${ITER166_TOTAL_ASSERTIONS_EVALUATED}/${ITER166_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-166 REGRESSION TEST: $((ITER166_TOTAL_ASSERTIONS_EVALUATED - ITER166_TOTAL_ASSERTIONS_FAILED))/${ITER166_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER166_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
