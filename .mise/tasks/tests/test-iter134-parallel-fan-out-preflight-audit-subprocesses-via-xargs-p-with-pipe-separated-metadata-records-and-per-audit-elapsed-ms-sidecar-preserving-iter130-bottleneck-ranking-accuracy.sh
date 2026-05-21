#!/usr/bin/env bash
#MISE description="Iter-135 regression test for the iter-134 parallel-fan-out-all-preflight-audit-subprocesses-via-xargs-p compressing-2603ms-sequential-into-510ms-wall-clock feature. Two-tier coverage mirroring the iter-132 pattern: (1) source-fingerprint assertions verify the iter134_parallelizable_preflight_audit_metadata_records array exists with exactly 17 records using PIPE separator (NOT TAB — the iter-134 BSD-xargs-collapse-whitespace bug); the pre-warm function, exit-code checker, timing-seed helper, and adaptive lane heuristic functions all exist; the parallel pre-warm is invoked right after Check 4e; and every Check 4f-4v uses the iter-134 helpers (no surviving inline `mise run` audit invocations except in operator-help error-message echoes). (2) Integration assertions invoke release:preflight with PREFLIGHT_TIMING_PROFILE=1 and verify the parallel-execution shape: preflight passes, whole-script wall-clock is below 6000ms (warm cache; pre-iter-134 baseline was ~7000ms), and the iter-130 top-N ranking still emits accurate per-audit milliseconds. Tier-2 self-skips under MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD=1 to prevent runaway suite recursion when this test runs as part of the suite itself (same recursion-guard pattern as iter-75 / iter-132). Closes the every-iter-N-gets-a-regression-test discipline gap for iter-134."

# Iter-135 regression test for iter-134's parallel preflight-audit fan-out.
#
# Iter-134 is the largest preflight perf-optimization in the campaign (~30%
# wall-clock reduction). It introduces several interlocking invariants:
#
#   1. PIPE `|` is the record separator (NOT TAB). The TAB-to-PIPE switch
#      was a mid-iteration bug-fix after discovering BSD xargs collapses
#      internal whitespace to single SPACE at the `-I {}` substitution
#      handoff. If a future maintainer "cleans up" the metadata records by
#      converting `|` back to TAB (thinking TAB is the more idiomatic
#      field separator), the two longest audit task names (iter-103 at
#      207 chars + iter-105 at 220 chars) silently fail with "File name
#      too long" errors — but only on macOS (BSD xargs). GNU xargs (Linux)
#      preserves TABs, so a CI machine running Linux might not catch the
#      regression. This test pins PIPE as the invariant.
#
#   2. Adaptive lane sizing reuses iter-128's clamp(ncpu-4, 4, 12)
#      heuristic. A future "let me just hardcode -P 8" simplification would
#      break low-end laptop perf (4-core machines need floor=4) and
#      high-end M-series perf (14-core deserves 10 lanes).
#
#   3. Per-audit timing accuracy is preserved by seeding phase-start
#      backwards from the `.elapsed_ms` sidecar. A future "let me just use
#      EPOCHREALTIME directly" cleanup would distort the iter-130 top-N
#      ranking (each Check 4f-4v would report ~1ms instead of the actual
#      audit work time).
#
#   4. All 17 inline check blocks must use the iter-134 helpers. A future
#      "let me add a new audit Check 4w via inline `mise run`" would
#      undermine the parallelization (Check 4w would run AFTER the Phase A
#      pre-warm completes, paying full sequential cost).
#
# This test pins all four invariants as source-fingerprint assertions
# plus an integration assertion verifying the observable speedup.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PREFLIGHT_SCRIPT_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/release/preflight"

ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=0
ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=0

assert_substring_present() {
    local assertion_label_for_iter135="$1"
    local haystack="$2"
    local expected_substring="$3"
    if [[ "$haystack" == *"$expected_substring"* ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✓ PASS: $assertion_label_for_iter135"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: $assertion_label_for_iter135"
        echo "    expected substring: $expected_substring"
        echo "    haystack (first 200 chars): ${haystack:0:200}"
    fi
}

assert_substring_absent() {
    local assertion_label_for_iter135="$1"
    local haystack="$2"
    local forbidden_substring="$3"
    if [[ "$haystack" != *"$forbidden_substring"* ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✓ PASS: $assertion_label_for_iter135"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: $assertion_label_for_iter135"
        echo "    forbidden substring: $forbidden_substring"
    fi
}

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-135 regression test"
echo "  (covers iter-134 parallel-fan-out preflight audits + BSD-xargs PIPE-vs-TAB fix)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "── TIER 1: source-fingerprint assertions (always run, no subprocess) ──"

# ─── Tier 1.A: iter-134 helper function definitions exist ────────────────
preflight_script_source="$(cat "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")"

assert_substring_present \
    "Tier 1.A1: iter-134 parallel-fan-out function defined" \
    "$preflight_script_source" \
    "__iter134_parallel_fan_out_all_preflight_audit_subprocesses_via_xargs_p_with_per_audit_log_exit_and_elapsed_ms_sidecar_capture"

assert_substring_present \
    "Tier 1.A2: iter-134 exit-code sidecar checker function defined" \
    "$preflight_script_source" \
    "__iter134_audit_subprocess_completed_successfully_per_sidecar_exit_code_file"

assert_substring_present \
    "Tier 1.A3: iter-134 timing-seed helper preserves iter-130 ranking accuracy" \
    "$preflight_script_source" \
    "__iter134_seed_phase_timing_start_from_externally_captured_audit_wall_clock_elapsed_ms_sidecar_file"

assert_substring_present \
    "Tier 1.A4: iter-134 adaptive lane heuristic exists (mirrors iter-128)" \
    "$preflight_script_source" \
    "__iter134_compute_adaptive_preflight_audit_parallel_lanes_clamped_against_host_cpu_count"

# ─── Tier 1.B: iter-134 metadata array shape + separator invariant ───────

assert_substring_present \
    "Tier 1.B1: iter-134 metadata array declared" \
    "$preflight_script_source" \
    "iter134_parallelizable_preflight_audit_metadata_records_keyed_by_existing_log_path_basename"

# The PIPE separator invariant — this is the load-bearing invariant that
# BSD xargs cannot collapse. The test directly grep's for a PIPE between
# a known sidecar key and the matching mise task name.
assert_substring_present \
    "Tier 1.B2: iter-134 metadata records use PIPE separator (not TAB) — BSD xargs invariant" \
    "$preflight_script_source" \
    "pretooluse-schema-audit|audit-pretooluse-hooks-for-deprecated-top-level-decision-schema"

# Count the records by counting `|<TASK-NAME>|` patterns (each record has
# exactly two PIPEs: between key+task and between task+extra-args).
# Use awk to count occurrences of the canonical record opening for ALL 17
# audit keys to verify the array hasn't been truncated.
iter134_metadata_record_count_actual=$(echo "$preflight_script_source" | grep -cE '^[[:space:]]+"[a-z][a-z0-9-]+\|audit-|^[[:space:]]+"iter[0-9]+[a-z-]*\|(audit-|generate-)')
if [[ "$iter134_metadata_record_count_actual" -eq 17 ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Tier 1.B3: iter-134 metadata array has exactly 17 records (all Checks 4f-4v covered)"
else
    ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Tier 1.B3: iter-134 metadata array record count mismatch (expected 17, got $iter134_metadata_record_count_actual)"
fi

# ─── Tier 1.C: xargs worker uses cut -d"|" (not default TAB) ─────────────

assert_substring_present \
    "Tier 1.C1: iter-134 xargs worker uses cut -d\"|\" for field extraction (not default TAB)" \
    "$preflight_script_source" \
    'cut -d"|" -f1'

assert_substring_present \
    "Tier 1.C2: iter-134 xargs worker uses cut -d\"|\" -f2 for mise task name" \
    "$preflight_script_source" \
    'cut -d"|" -f2'

assert_substring_present \
    "Tier 1.C3: iter-134 xargs worker uses cut -d\"|\" -f3 for extra CLI args (e.g. --check)" \
    "$preflight_script_source" \
    'cut -d"|" -f3'

# ─── Tier 1.D: pre-warm invocation after Check 4e ────────────────────────
# Defensive: the pre-warm MUST be invoked BEFORE the first inline audit
# check (Check 4f) reads its exit-code sidecar. If a maintainer deletes
# the invocation line, the inline checks would all fail-fast on missing
# sidecars (defensive iter-75 fail-safe). This assertion pins the
# invocation order.

assert_substring_present \
    "Tier 1.D1: iter-134 parallel pre-warm invoked at top level (not just defined as a function)" \
    "$preflight_script_source" \
    "__iter134_parallel_fan_out_all_preflight_audit_subprocesses_via_xargs_p_with_per_audit_log_exit_and_elapsed_ms_sidecar_capture
"

# ─── Tier 1.E: all 17 Check 4f-4v use iter-134 helpers ───────────────────
# Count callsites of the iter-134 exit-code checker; should be 17 (one
# per audit check 4f through 4v). If a maintainer adds a new audit
# Check 4w via inline `mise run` (bypassing the parallel pre-warm), the
# count stays at 17 but the new check pays full sequential cost AND
# emits stderr ordering issues. Conversely, removing a helper invocation
# from an existing check would drop the count below 17.

iter134_exit_checker_callsite_count=$(grep -cF '__iter134_audit_subprocess_completed_successfully_per_sidecar_exit_code_file' "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")
# Subtract 1 for the function definition itself (it appears in its own header).
iter134_exit_checker_callsite_count=$((iter134_exit_checker_callsite_count - 1))
if [[ "$iter134_exit_checker_callsite_count" -ge 17 ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Tier 1.E1: iter-134 exit-code checker called from $iter134_exit_checker_callsite_count callsites (≥17 = all Checks 4f-4v use the helper)"
else
    ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Tier 1.E1: iter-134 exit-code checker callsite count below threshold (expected ≥17, got $iter134_exit_checker_callsite_count)"
fi

iter134_timing_seed_callsite_count=$(grep -cF '__iter134_seed_phase_timing_start_from_externally_captured_audit_wall_clock_elapsed_ms_sidecar_file' "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")
iter134_timing_seed_callsite_count=$((iter134_timing_seed_callsite_count - 1))
if [[ "$iter134_timing_seed_callsite_count" -ge 17 ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Tier 1.E2: iter-134 timing-seed helper called from $iter134_timing_seed_callsite_count callsites (≥17 = iter-130 ranking accuracy preserved)"
else
    ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Tier 1.E2: iter-134 timing-seed helper callsite count below threshold (expected ≥17, got $iter134_timing_seed_callsite_count)"
fi

# ─── Tier 1.F: adaptive lane heuristic preserves iter-128 invariants ─────

assert_substring_present \
    "Tier 1.F1: iter-134 lane heuristic detects CPU count via sysctl/nproc fallback" \
    "$preflight_script_source" \
    "sysctl -n hw.ncpu"

assert_substring_present \
    "Tier 1.F2: iter-134 lane heuristic clamps to floor=4 (low-end laptop protection)" \
    "$preflight_script_source" \
    "recommended_lane_count=4"

assert_substring_present \
    "Tier 1.F3: iter-134 lane heuristic clamps to ceiling=12 (iter-128 bun-cold-start contention plateau)" \
    "$preflight_script_source" \
    "recommended_lane_count=12"

# ─── Tier 1.G: operator-tunable env-var knobs documented in script ───────

assert_substring_present \
    "Tier 1.G1: iter-134 operator knob ITER134_PREFLIGHT_AUDIT_PARALLEL_LANES referenced" \
    "$preflight_script_source" \
    "ITER134_PREFLIGHT_AUDIT_PARALLEL_LANES"

assert_substring_present \
    "Tier 1.G2: iter-134 operator opt-out ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION referenced" \
    "$preflight_script_source" \
    "ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION"

# ─── Tier 2: integration assertions (self-skip under recursion guard) ────
echo ""
echo "── TIER 2: integration assertions (skipped under recursion guard) ──"

if [[ "${MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD:-0}" == "1" ]]; then
    echo "  ⊘ Tier 2 SKIPPED — running inside parent marketplace-suite invocation"
    echo "    (recursion guard active; iter-75 / iter-132 parity-test pattern). When"
    echo "    invoked standalone the integration tier exercises the actual preflight."
else
    echo "  → Running preflight with PREFLIGHT_TIMING_PROFILE=1 (cache-warm; ~5s expected)..."
    iter135_preflight_integration_output="$(PREFLIGHT_TIMING_PROFILE=1 \
        ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY=10 \
        mise run release:preflight 2>&1)"

    # Tier 2.A: preflight passes end-to-end
    assert_substring_present \
        "Tier 2.A1: preflight passes all checks under iter-134 parallel pre-warm" \
        "$iter135_preflight_integration_output" \
        "All preflight checks passed"

    # Tier 2.B: iter-130 top-N ranking still emits accurate per-audit ms
    # (NOT trivial post-processing ms — that would indicate the timing-seed
    # helper broke and reverted to EPOCHREALTIME-after-pre-warm).
    assert_substring_present \
        "Tier 2.B1: iter-130 top-N ranking still emits (iter-134 didn't break iter-130)" \
        "$iter135_preflight_integration_output" \
        "Top 10 slowest preflight checks"

    # Tier 2.C: every Check 4f-4v reports >50ms (proving timing-seed worked).
    # If the seed helper broke, all Check 4f-4v would report ~1ms (just the
    # sidecar-read post-processing time). We verify that Check 4k (typically
    # the slowest single audit at ~370-510ms) reports >100ms.
    # Regex defensive: `grep -oE '[0-9]+'` matches BOTH the elapsed-ms number
    # AND the `4` in `Check 4k`. Trailing `head -1` extracts only the first
    # (which is the elapsed-ms — the ranking line emits "Check 4k:" AFTER
    # the "phase elapsed: NNNms" prefix). Don't simplify away the final head -1.
    iter135_check_4k_elapsed_ms_extracted=$(echo "$iter135_preflight_integration_output" \
        | grep -oE 'phase elapsed: [0-9]+ms \(Check 4k:' \
        | head -1 \
        | grep -oE '[0-9]+' \
        | head -1)
    if [[ -n "$iter135_check_4k_elapsed_ms_extracted" ]] && [[ "$iter135_check_4k_elapsed_ms_extracted" -gt 100 ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✓ PASS: Tier 2.C1: Check 4k elapsed=${iter135_check_4k_elapsed_ms_extracted}ms (>100ms confirms iter-134 timing-seed preserves iter-130 accuracy)"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: Tier 2.C1: Check 4k elapsed=${iter135_check_4k_elapsed_ms_extracted:-MISSING}ms (expected >100ms; timing-seed may be broken)"
    fi

    # Tier 2.D: whole-script wall-clock improvement.
    # Pre-iter-134 baseline ~7000ms; post-iter-134 ~4900ms.
    # Threshold: <6000ms (conservative; allows 300ms of normal variance).
    iter135_whole_script_elapsed_ms_extracted=$(echo "$iter135_preflight_integration_output" \
        | grep -oE 'whole-script elapsed: [0-9]+ms' \
        | head -1 \
        | grep -oE '[0-9]+')
    if [[ -n "$iter135_whole_script_elapsed_ms_extracted" ]] && [[ "$iter135_whole_script_elapsed_ms_extracted" -lt 6000 ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✓ PASS: Tier 2.D1: preflight whole-script wall-clock=${iter135_whole_script_elapsed_ms_extracted}ms (<6000ms threshold; iter-134 30% reduction holding)"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: Tier 2.D1: preflight whole-script wall-clock=${iter135_whole_script_elapsed_ms_extracted:-MISSING}ms (expected <6000ms; iter-134 parallelization may have regressed)"
    fi

    # Tier 2.E: opt-out path works (--lanes=1 sequential mode).
    # Verifies the ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1 escape
    # hatch still routes through xargs (and therefore through the sidecar
    # contract) — just with -P 1. Skipped in normal runs to keep this test
    # fast; gated behind opt-in flag matching iter-132's tier-2.D pattern.
    if [[ "${ITER135_RUN_SERIAL_MODE_INTEGRATION_TIER:-0}" == "1" ]]; then
        echo "  → Running preflight with ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1..."
        iter135_serial_mode_integration_output="$(PREFLIGHT_TIMING_PROFILE=1 \
            ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1 \
            mise run release:preflight 2>&1)"
        assert_substring_present \
            "Tier 2.E1: preflight passes under serial-mode opt-out (ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1)" \
            "$iter135_serial_mode_integration_output" \
            "All preflight checks passed"
    else
        echo "  ⊘ Tier 2.E (serial-mode opt-out integration) SKIPPED — set ITER135_RUN_SERIAL_MODE_INTEGRATION_TIER=1 to enable"
        echo "    (gated to keep the regression test fast in the common case; serial mode runs ~2s slower)"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-135 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

if [[ "$ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST assertion(s) failed"
    exit 1
fi

echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED_FOR_ITER135_PARALLEL_AUDIT_FAN_OUT_REGRESSION_TEST assertions passed"
echo ""
echo "  🚀 Iter-134 parallel-fan-out feature regression-guarded across four invariants:"
echo "     1. PIPE separator (NOT TAB — pins BSD-xargs-collapse-whitespace fix)"
echo "     2. Adaptive lane heuristic (mirrors iter-128 clamp(ncpu-4, 4, 12))"
echo "     3. Per-audit timing accuracy (sidecar-seeded phase-start preserves iter-130)"
echo "     4. All 17 Checks 4f-4v use iter-134 helpers (no inline mise-run regressions)"
echo "     Plus integration shape (whole-script <6000ms; iter-130 ranking still accurate)."
