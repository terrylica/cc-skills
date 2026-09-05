#!/usr/bin/env bash
#MISE description="Iter-160 regression test pinning the commits:status self-diagnosis task. Asserts (a) status script + mise shim structurally valid (executable, bash-clean, shellcheck-clean), (b) human-readable mode emits all 9 canonical check labels covering iter-150 through iter-158, (c) --json mode parses cleanly via independent python3 json.loads, (d) JSON schema includes iter160_schema_version=1 + summary.verdict + checks array, (e) when run against healthy cc-skills HEAD: critical_failed=0 + verdict=TOOLKIT_HEALTHY, (f) exit code 0 in healthy mode (per industry-standard severity-tier convention)."
set -euo pipefail

ITER160_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER160_REPO_ROOT"

ITER160_STATUS_SCRIPT_RELATIVE_PATH="scripts/iter160-operator-facing-commits-arc-self-diagnosis-task-checking-each-iter150-through-iter158-tool-for-presence-executability-and-functional-correctness-with-per-check-wall-clock-latency-reporting-and-json-mode.sh"
ITER160_STATUS_SCRIPT_ABSOLUTE_PATH="$ITER160_REPO_ROOT/$ITER160_STATUS_SCRIPT_RELATIVE_PATH"
ITER160_MISE_TASK_SHIM_ABSOLUTE_PATH="$ITER160_REPO_ROOT/tasks/commits/status"

ITER160_TOTAL_ASSERTIONS_EVALUATED=0
ITER160_TOTAL_ASSERTIONS_FAILED=0

iter160_assert_file_structurally_valid_executable_bash_clean_shellcheck_clean() {
    local human_readable_label="$1"
    local file_absolute_path="$2"
    ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ ! -x "$file_absolute_path" ]]; then
        echo "  ✗ $human_readable_label: missing or not executable"
        ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
        return
    fi
    if ! bash -n "$file_absolute_path" 2>/dev/null; then
        echo "  ✗ $human_readable_label: bash -n FAILED"
        ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
        return
    fi
    if command -v shellcheck >/dev/null 2>&1; then
        if ! shellcheck "$file_absolute_path" >/dev/null 2>&1; then
            echo "  ✗ $human_readable_label: shellcheck FAILED"
            ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
            return
        fi
    fi
    echo "  ✓ $human_readable_label"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-160 COMMITS:STATUS SELF-DIAGNOSIS REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: structural validity ───────────────────────────────────────────
echo ""
echo "GROUP A (2 assertions): status script + mise shim structurally valid"

iter160_assert_file_structurally_valid_executable_bash_clean_shellcheck_clean \
    "A1: iter-160 status script (executable + bash-clean + shellcheck-clean)" \
    "$ITER160_STATUS_SCRIPT_ABSOLUTE_PATH"

iter160_assert_file_structurally_valid_executable_bash_clean_shellcheck_clean \
    "A2: commits:status mise task shim (executable + bash-clean + shellcheck-clean)" \
    "$ITER160_MISE_TASK_SHIM_ABSOLUTE_PATH"

# ─── Group B: human-readable mode covers all 9 canonical checks ─────────────
#
# Each check identifier is a snake_case string emitted in JSON mode and
# present (transformed to human-readable label) in default mode. We probe
# the human-readable output for the iter-150 / iter-152 / iter-153 / iter-155
# / iter-156 / iter-157 / iter-158 references, plus the iter-157 hook-
# installed warning, plus the pre-commit framework binary warning.

echo ""
echo "GROUP B (9 assertions): human-readable mode covers all 9 canonical checks"

ITER160_HUMAN_MODE_OUTPUT_CAPTURE=$(
    "$ITER160_STATUS_SCRIPT_ABSOLUTE_PATH" 2>&1 || true
)

iter160_assert_human_readable_output_contains_substring() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$ITER160_HUMAN_MODE_OUTPUT_CAPTURE" == *"$expected_substring"* ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:60})"
        ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter160_assert_human_readable_output_contains_substring \
    "B1: iter-150 readable renderer check label present" \
    "iter-150 release:history readable renderer"

iter160_assert_human_readable_output_contains_substring \
    "B2: iter-152 commits:health dashboard check label present" \
    "iter-152 commits:health"

iter160_assert_human_readable_output_contains_substring \
    "B3: iter-153 advisor check label present" \
    "iter-153 commits:advise"

iter160_assert_human_readable_output_contains_substring \
    "B4: iter-155 shared library check label present" \
    "iter-155 pure-bash RFC 8259 shared library"

iter160_assert_human_readable_output_contains_substring \
    "B5: iter-156 dispatcher check label present" \
    "iter-156 commits namespace default dispatcher"

iter160_assert_human_readable_output_contains_substring \
    "B6: iter-157 installer check label present" \
    "iter-157 commit-msg hook installer"

iter160_assert_human_readable_output_contains_substring \
    "B7: iter-157 hook-installed-in-current-repo check label present" \
    "iter-157 hook installed"

iter160_assert_human_readable_output_contains_substring \
    "B8: iter-158 manifest check label present" \
    "iter-158 .pre-commit-hooks.yaml"

iter160_assert_human_readable_output_contains_substring \
    "B9: pre-commit binary check label present" \
    "pre-commit framework binary"

# ─── Group C: --json mode parses + has expected schema fields ───────────────
echo ""
echo "GROUP C (6 assertions): --json mode parses cleanly + has expected schema"

ITER160_JSON_MODE_OUTPUT_CAPTURE=$(
    "$ITER160_STATUS_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true
)

# ─── ITER-187: WHEN C3/C4 FAIL, NAME THE CHECK ───────────────────────────────
# This test is a confirmed intermittent: it went red in 1 of 10 `moon run
# repo:check` runs (2026-09-05) while passing 24 of 24 standalone at 12-way
# self-contention, so it only flaps under the full gate's co-scheduled load —
# which is also why iter-186 deliberately left it OUT of the serial perf lane.
#
# The problem is that C3 and C4 reported only the AGGREGATE verdict
# ("verdict is not TOOLKIT_HEALTHY", "at least one CRITICAL check failed"), so
# the captured red log said the toolkit was broken without saying WHICH of the
# 15 checks broke — the same unidentifiable-failure trap one level down from the
# suite's own. The JSON in hand already carries every check's identifier and
# status, so the answer was sitting in a variable and simply never printed.
# Note D1 re-invokes the doctor seconds later and has been observed passing in
# the very same run that C3/C4 failed, so the two invocations disagree; naming
# the check is what will make that disagreement diagnosable next time.
iter187_emit_failing_critical_checks_from_the_captured_doctor_json() {
    local captured_doctor_json="$1"
    echo "    ↳ failing CRITICAL check(s), extracted from the --json capture:"
    printf '%s' "$captured_doctor_json" | python3 -c '
import json, sys
try:
    parsed_doctor_report = json.load(sys.stdin)
except Exception as parse_error:
    print("       (JSON did not parse: %s)" % parse_error)
    sys.exit(0)
# Schema keys are "outcome" and "diagnostic_message" (iter160_schema_version=1),
# NOT "status"/"detail" — verified against live --json output 2026-09-05. Getting
# these wrong prints None for every record and is only noticed the one time the
# output actually matters, so they are asserted by C6 below.
emitted_any_failing_check = False
for check_record in parsed_doctor_report.get("checks", []):
    if check_record.get("severity") == "critical" and check_record.get("outcome") != "pass":
        emitted_any_failing_check = True
        print("       %s | outcome=%s | latency=%sms | %s" % (
            check_record.get("identifier"),
            check_record.get("outcome"),
            check_record.get("wall_clock_latency_milliseconds"),
            str(check_record.get("diagnostic_message", ""))[:300],
        ))
if not emitted_any_failing_check:
    print("       (no critical check is marked failed — the verdict and the "
          "per-check records disagree, which is itself the finding)")
' 2>&1 || true
}

ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER160_JSON_MODE_OUTPUT_CAPTURE" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✓ C1: --json output parses cleanly via independent python3 json.loads"
else
    echo "  ✗ C1: --json output does NOT parse"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"iter160_schema_version": 1'* ]]; then
    echo "  ✓ C2: --json emits stable iter160_schema_version=1 (AI-agent consumer contract)"
else
    echo "  ✗ C2: iter160_schema_version field missing or wrong value"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"verdict": "TOOLKIT_HEALTHY"'* ]]; then
    echo "  ✓ C3: --json verdict=TOOLKIT_HEALTHY (cc-skills HEAD is currently healthy)"
else
    echo "  ✗ C3: verdict is not TOOLKIT_HEALTHY — iter-150-iter-158 toolkit may be broken"
    iter187_emit_failing_critical_checks_from_the_captured_doctor_json "$ITER160_JSON_MODE_OUTPUT_CAPTURE"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"critical_failed": 0'* ]]; then
    echo "  ✓ C4: --json critical_failed=0 (all CRITICAL checks passed)"
else
    echo "  ✗ C4: at least one CRITICAL check failed"
    iter187_emit_failing_critical_checks_from_the_captured_doctor_json "$ITER160_JSON_MODE_OUTPUT_CAPTURE"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"checks":'* ]] \
   && [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"identifier":'* ]] \
   && [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"wall_clock_latency_milliseconds":'* ]]; then
    echo "  ✓ C5: --json checks array has expected per-record fields (identifier + latency)"
else
    echo "  ✗ C5: checks array missing canonical per-record fields"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── ITER-187: pin the two schema keys the C3/C4 diagnostic emitter reads ────
# The emitter above selects failing checks by `severity`/`outcome` and prints
# `diagnostic_message`. If the doctor ever renames those keys, the emitter would
# silently degrade to printing "outcome=None" for every record — useless at
# exactly the moment it is needed, and invisible on every green run because the
# emitter only executes when C3/C4 fail. Assert the keys on the happy path so
# the drift is caught while the suite is green.
ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"severity":'* ]] \
   && [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"outcome":'* ]] \
   && [[ "$ITER160_JSON_MODE_OUTPUT_CAPTURE" == *'"diagnostic_message":'* ]]; then
    echo "  ✓ C6: per-check records carry severity/outcome/diagnostic_message (the iter-187 C3/C4 emitter's contract)"
else
    echo "  ✗ C6: schema drift — the iter-187 C3/C4 failure-diagnostic emitter reads"
    echo "        severity/outcome/diagnostic_message and at least one is now absent,"
    echo "        so a future C3/C4 failure would not name the failing check"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: exit-code gating per industry-standard convention ─────────────
echo ""
echo "GROUP D (1 assertion): exit code 0 when toolkit is healthy"

ITER160_TOTAL_ASSERTIONS_EVALUATED=$((ITER160_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER160_EXIT_CODE_FROM_HEALTHY_RUN=0
"$ITER160_STATUS_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1 \
    || ITER160_EXIT_CODE_FROM_HEALTHY_RUN=$?
if [[ "$ITER160_EXIT_CODE_FROM_HEALTHY_RUN" -eq 0 ]]; then
    echo "  ✓ D1: exit 0 when all CRITICAL checks pass (industry-standard severity-tier convention)"
else
    echo "  ✗ D1: exit code is $ITER160_EXIT_CODE_FROM_HEALTHY_RUN (should be 0 in healthy mode)"
    ITER160_TOTAL_ASSERTIONS_FAILED=$((ITER160_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER160_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-160 REGRESSION TEST: ${ITER160_TOTAL_ASSERTIONS_EVALUATED}/${ITER160_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-160 REGRESSION TEST: $((ITER160_TOTAL_ASSERTIONS_EVALUATED - ITER160_TOTAL_ASSERTIONS_FAILED))/${ITER160_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER160_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
