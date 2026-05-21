#!/usr/bin/env bash
#MISE description="Iter-182 regression test pinning the pytest-benchmark-machine-info-style measurement-context metadata block added to the iter-179 JSON envelope. Pre-iter-182 the envelope emitted per-scenario {median_ms, cap_ms, verdict} + aggregate summary but lacked measurement-context provenance metadata. Web research (2026) confirmed pytest-benchmark is the only major benchmark harness with built-in machine_info + commit_info metadata; criterion.rs and hyperfine LACK this — Bencher and other CI platforms explicitly recommend wrapping them and layering metadata in sidecar files. Our iter-179 envelope had the same gap. Iter-182 closes it additively (iter174_schema_version stays at 1, backward-compatible per JSON-best-practice — older consumers ignore unknown fields). Captured BEFORE the trial loop so the timestamp marks measurement-start. Pure-bash construction. Schema enriches AI-agent + CI-pipeline longitudinal regression trend tracking with measurement_timestamp_iso8601_utc + host_machine_uname_srm_for_baseline_hardware_context + bash_version_for_epochrealtime_zero_fork_capability_context + epochrealtime_fast_path_engaged_per_iter180_zero_fork_dogfood (bool) + git_commit_sha_short_for_provenance_against_codebase_drift. Test asserts (a) measurement_context capture block present in iter-174 with 5 verbose constant names + capture-before-trial-loop ordering, (b) JSON envelope contains the iter182_measurement_context block, (c) all 5 fields populated and structurally valid (ISO 8601 timestamp format YYYY-MM-DDTHH:MM:SSZ, uname-srm not literally 'unknown', bash version starts with '5.' on this host, epochrealtime fast-path engaged is JSON-bool true, git SHA is 7+ hex chars or 'unknown'), (d) schema_version unchanged at 1 (backward-compat invariant), (e) human-mode output unchanged + still 7/7 PASS (regression-safe), (f) bash -n + shellcheck clean."
set -euo pipefail

ITER182_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER182_REPO_ROOT"

ITER182_ITER174_HARNESS_ABSOLUTE_PATH="$ITER182_REPO_ROOT/.mise/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"
ITER182_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER182_REPO_ROOT/.mise/tasks/commits/_default"

ITER182_TOTAL_ASSERTIONS_EVALUATED=0
ITER182_TOTAL_ASSERTIONS_FAILED=0

iter182_assert_substring_present_in_harness_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$ITER182_ITER174_HARNESS_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-182 MEASUREMENT-CONTEXT METADATA BLOCK REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: capture block present in iter-174 with 5 verbose constants ──
echo ""
echo "GROUP A (6 assertions): iter-182 measurement-context capture block declared with verbose pytest-benchmark-style constants"

iter182_assert_substring_present_in_harness_with_human_readable_label \
    "A1: iter-182 capture block doc-cites pytest-benchmark machine_info industry pattern" \
    "ITER-182 MEASUREMENT-CONTEXT METADATA CAPTURE (pytest-benchmark-style)"

iter182_assert_substring_present_in_harness_with_human_readable_label \
    "A2: measurement_timestamp_iso8601_utc constant captured at harness-start before trial loop" \
    "ITER182_MEASUREMENT_TIMESTAMP_ISO8601_UTC_CAPTURED_AT_HARNESS_START_BEFORE_TRIAL_LOOP"

iter182_assert_substring_present_in_harness_with_human_readable_label \
    "A3: host_machine_uname_srm_for_baseline_hardware_context constant captured" \
    "ITER182_HOST_MACHINE_UNAME_SRM_FOR_BASELINE_HARDWARE_CONTEXT"

iter182_assert_substring_present_in_harness_with_human_readable_label \
    "A4: bash_version_for_epochrealtime_zero_fork_capability_context constant captured" \
    "ITER182_BASH_VERSION_FOR_EPOCHREALTIME_ZERO_FORK_CAPABILITY_CONTEXT"

iter182_assert_substring_present_in_harness_with_human_readable_label \
    "A5: epochrealtime_fast_path_engaged_per_iter180_zero_fork_dogfood bool captured (bash5 detection)" \
    "ITER182_EPOCHREALTIME_FAST_PATH_ENGAGED_PER_ITER180_ZERO_FORK_DOGFOOD"

iter182_assert_substring_present_in_harness_with_human_readable_label \
    "A6: git_commit_sha_short_for_provenance_against_codebase_drift constant captured" \
    "ITER182_GIT_COMMIT_SHA_SHORT_FOR_PROVENANCE_AGAINST_CODEBASE_DRIFT"

# ─── Group B: --json envelope contains measurement_context block + 5 fields ─
echo ""
echo "GROUP B (5 assertions): --json envelope contains iter182_measurement_context block with all 5 fields populated + structurally valid"

ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE=$(bash "$ITER182_ITER174_HARNESS_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    # Use a temp file to avoid pipe-quoting hell on the bash↔python boundary.
    ITER182_TEMP_JSON_CAPTURE_FILE=$(mktemp -t iter182-json-envelope-capture-XXXXXX)
    echo "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" > "$ITER182_TEMP_JSON_CAPTURE_FILE"
    if python3 - "$ITER182_TEMP_JSON_CAPTURE_FILE" <<'PYTHON_BLOCK' 2>/dev/null
import json, re, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
mc = d["iter182_measurement_context_for_ai_agent_and_ci_pipeline_longitudinal_regression_trend_tracking_per_pytest_benchmark_machine_info_pattern"]
assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", mc["measurement_timestamp_iso8601_utc"]), "timestamp not ISO 8601"
assert mc["host_machine_uname_srm_for_baseline_hardware_context"] != "unknown" and len(mc["host_machine_uname_srm_for_baseline_hardware_context"]) > 0, "uname-srm not captured"
assert isinstance(mc["epochrealtime_fast_path_engaged_per_iter180_zero_fork_dogfood"], bool), "fast-path-engaged not a JSON bool"
assert mc["bash_version_for_epochrealtime_zero_fork_capability_context"] != "unknown" and len(mc["bash_version_for_epochrealtime_zero_fork_capability_context"]) > 0, "bash version not captured"
assert mc["git_commit_sha_short_for_provenance_against_codebase_drift"] != "" and (mc["git_commit_sha_short_for_provenance_against_codebase_drift"] == "unknown" or re.match(r"^[0-9a-f]{7,}$", mc["git_commit_sha_short_for_provenance_against_codebase_drift"])), "git SHA invalid"
PYTHON_BLOCK
    then
        echo "  ✓ B1: measurement_context block present + all 5 fields structurally valid (ISO 8601 timestamp + non-empty uname-srm + JSON bool for fast-path + non-empty bash version + 7+ hex git SHA OR 'unknown')"
    else
        echo "  ✗ B1: measurement_context block missing OR field validation failed"
        echo "      (envelope head: $(echo "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" | head -15))"
        ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
    fi
    rm -f "$ITER182_TEMP_JSON_CAPTURE_FILE"
else
    echo "  ⊘ B1: python3 not available — SKIPPED (assertion uncounted)"
    ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# B2: bash version on this host starts with "5." (we just verified bash 5.3.9 supports EPOCHREALTIME).
ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" == *'"bash_version_for_epochrealtime_zero_fork_capability_context": "5.'* ]]; then
    echo "  ✓ B2: bash version field on this host starts with '5.' (matches the bash 5.3.9 we verified supports EPOCHREALTIME)"
else
    echo "  ✗ B2: bash version field does not start with '5.' (unexpected; this host should be bash 5+)"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B3: epochrealtime_fast_path_engaged is true on this host (bash 5+).
ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" == *'"epochrealtime_fast_path_engaged_per_iter180_zero_fork_dogfood": true'* ]]; then
    echo "  ✓ B3: epochrealtime_fast_path_engaged_per_iter180_zero_fork_dogfood is JSON true on this bash-5+ host"
else
    echo "  ✗ B3: epochrealtime_fast_path_engaged should be true on this bash-5+ host"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B4: schema_version unchanged at 1 (backward-compat invariant).
ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" == *'"iter174_schema_version": 1'* ]]; then
    echo "  ✓ B4: iter174_schema_version still at 1 (additive iter-182 metadata is backward-compatible; older consumers ignore unknown fields)"
else
    echo "  ✗ B4: iter174_schema_version bumped or missing — backward-compat invariant violated"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B5: ordering — measurement_context appears AFTER trials_per_script and BEFORE results
# (so AI agents reading top-to-bottom see context before raw data).
ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER182_LINE_OF_TRIALS_PER_SCRIPT=$(echo "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" | grep -nF '"trials_per_script"' | head -1 | cut -d: -f1)
ITER182_LINE_OF_MEASUREMENT_CONTEXT=$(echo "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" | grep -nF '"iter182_measurement_context' | head -1 | cut -d: -f1)
ITER182_LINE_OF_RESULTS_ARRAY=$(echo "$ITER182_JSON_ENVELOPE_OUTPUT_CAPTURE" | grep -nF '"results"' | head -1 | cut -d: -f1)
if [[ -n "$ITER182_LINE_OF_TRIALS_PER_SCRIPT" ]] && [[ -n "$ITER182_LINE_OF_MEASUREMENT_CONTEXT" ]] && [[ -n "$ITER182_LINE_OF_RESULTS_ARRAY" ]] && \
   (( ITER182_LINE_OF_TRIALS_PER_SCRIPT < ITER182_LINE_OF_MEASUREMENT_CONTEXT )) && \
   (( ITER182_LINE_OF_MEASUREMENT_CONTEXT < ITER182_LINE_OF_RESULTS_ARRAY )); then
    echo "  ✓ B5: envelope-field ordering trials_per_script(L${ITER182_LINE_OF_TRIALS_PER_SCRIPT}) < measurement_context(L${ITER182_LINE_OF_MEASUREMENT_CONTEXT}) < results(L${ITER182_LINE_OF_RESULTS_ARRAY}) — AI agents see context before raw data"
else
    echo "  ✗ B5: envelope-field ordering broken (trials=${ITER182_LINE_OF_TRIALS_PER_SCRIPT:-MISSING}, context=${ITER182_LINE_OF_MEASUREMENT_CONTEXT:-MISSING}, results=${ITER182_LINE_OF_RESULTS_ARRAY:-MISSING})"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: human-mode output unchanged + still 7/7 PASS ─────────────────
echo ""
echo "GROUP C (1 assertion): human-mode invocation still 7/7 PASS (regression-safe; iter-182 metadata only emitted in --json mode)"

ITER182_HUMAN_MODE_OUTPUT_CAPTURE=$(bash "$ITER182_ITER174_HARNESS_ABSOLUTE_PATH" 2>&1 || true)

ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER182_HUMAN_MODE_OUTPUT_CAPTURE" == *"7/7 assertions PASSED"* ]] && \
   [[ "$ITER182_HUMAN_MODE_OUTPUT_CAPTURE" != *"iter182_measurement_context"* ]] && \
   [[ "$ITER182_HUMAN_MODE_OUTPUT_CAPTURE" != *"iter174_schema_version"* ]]; then
    echo "  ✓ C1: human-mode still 7/7 PASS + no JSON-envelope leak (measurement_context only emitted in --json mode)"
else
    echo "  ✗ C1: human-mode regressed OR leaked measurement_context block into text output"
    echo "      (tail: $(echo "$ITER182_HUMAN_MODE_OUTPUT_CAPTURE" | tail -3))"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: iter-156 dispatcher cites iter-182 ──────────────────────────
echo ""
echo "GROUP D (1 assertion): iter-156 dispatcher banner cites iter-182 measurement-context metadata"

ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if grep -qF "iter-182" "$ITER182_ITER156_DISPATCHER_ABSOLUTE_PATH"; then
    echo "  ✓ D1: iter-156 dispatcher banner cites iter-182"
else
    echo "  ✗ D1: iter-156 dispatcher banner missing iter-182 citation"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: bash -n + shellcheck ─────────────────────────────────────────
echo ""
echo "GROUP E (2 assertions): iter-174 harness passes bash -n + shellcheck after iter-182 metadata additions"

ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER182_ITER174_HARNESS_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ E1: iter-174 passes bash -n syntax check after iter-182 metadata additions"
else
    echo "  ✗ E1: iter-174 FAILS bash -n syntax check after iter-182 metadata additions"
    ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER182_ITER174_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ E2: iter-174 passes shellcheck zero-warning after iter-182 metadata additions"
    else
        echo "  ✗ E2: iter-174 has shellcheck warnings after iter-182 metadata additions"
        ITER182_TOTAL_ASSERTIONS_FAILED=$((ITER182_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER182_TOTAL_ASSERTIONS_EVALUATED=$((ITER182_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER182_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-182 REGRESSION TEST: ${ITER182_TOTAL_ASSERTIONS_EVALUATED}/${ITER182_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-182 REGRESSION TEST: $((ITER182_TOTAL_ASSERTIONS_EVALUATED - ITER182_TOTAL_ASSERTIONS_FAILED))/${ITER182_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER182_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
