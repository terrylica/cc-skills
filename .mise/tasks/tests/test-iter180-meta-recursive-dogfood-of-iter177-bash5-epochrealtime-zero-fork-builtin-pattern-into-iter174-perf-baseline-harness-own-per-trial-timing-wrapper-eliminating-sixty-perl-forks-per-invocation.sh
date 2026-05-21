#!/usr/bin/env bash
#MISE description="Iter-180 regression test pinning the meta-recursive dogfood of the iter-177 bash 5+ \${EPOCHREALTIME} zero-fork builtin pattern into the iter-174 perf-baseline harness's OWN per-trial timing wrapper. Pre-iter-180 the harness designed to detect regressions in OTHER scripts still used 2 perl-MTime::HiRes forks per trial × 5 trials × 6 scenarios = 60 perl forks per commits:perf-baseline invocation, contributing ~300ms of harness self-overhead (~5% of total wall-clock) — ironic since iter-177 had just applied this exact optimization to iter-160 doctor. Iter-180 closes this meta-recursive dogfood gap: the perf-baseline tool now eats its own perf-optimization dogfood. Test asserts (a) timing function renamed to encode bash5_epochrealtime_zero_fork_builtin idiom with perl_time_hires_graceful_fallback suffix, (b) BASH_VERSINFO[0] gate dispatching between bash5+ builtin and perl fallback, (c) \${EPOCHREALTIME} reads present in both before/after positions of the per-trial timing block, (d) perl Time::HiRes fallback path preserved for bash<5 compatibility, (e) docstring cites iter-177 dogfood provenance + meta-recursive nature, (f) end-to-end harness invocation still emits banner + 6 PASS verdicts (regression-safe), (g) --json envelope still parses cleanly with 6 scenario records + iter174_schema_version=1 (regression-safe), (h) iter-156 dispatcher QUALITY + PERFORMANCE section cites iter-180 dogfood entry, (i) bash -n + shellcheck clean."
set -euo pipefail

ITER180_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER180_REPO_ROOT"

ITER180_ITER174_HARNESS_ABSOLUTE_PATH="$ITER180_REPO_ROOT/.mise/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"
ITER180_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER180_REPO_ROOT/.mise/tasks/commits/_default"

ITER180_TOTAL_ASSERTIONS_EVALUATED=0
ITER180_TOTAL_ASSERTIONS_FAILED=0

iter180_assert_substring_present_in_harness_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$ITER180_ITER174_HARNESS_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter180_assert_substring_present_in_dispatcher_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$ITER180_ITER156_DISPATCHER_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-180 META-RECURSIVE EPOCHREALTIME DOGFOOD REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: timing function renamed to encode the bash5 + perl-fallback idiom ───
echo ""
echo "GROUP A (2 assertions): timing function renamed to encode bash5 EPOCHREALTIME zero-fork builtin idiom with perl Time::HiRes graceful fallback"

iter180_assert_substring_present_in_harness_with_human_readable_label \
    "A1: timing function name encodes bash5_epochrealtime_zero_fork_builtin idiom" \
    "iter174_measure_median_wall_clock_in_milliseconds_across_n_trials_using_bash5_epochrealtime_zero_fork_builtin_with_perl_time_hires_graceful_fallback_for_bash4_or_older"

ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
if ! grep -qF "iter174_measure_median_wall_clock_in_milliseconds_across_n_trials_using_perl_time_hires_nanosecond_precision" "$ITER180_ITER174_HARNESS_ABSOLUTE_PATH"; then
    echo "  ✓ A2: old perl_time_hires_nanosecond_precision function name FULLY removed (no lingering references)"
else
    echo "  ✗ A2: old function name still present — rename incomplete"
    ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group B: BASH_VERSINFO dispatch + EPOCHREALTIME reads + perl fallback present ───
echo ""
echo "GROUP B (4 assertions): structural — BASH_VERSINFO gate + EPOCHREALTIME builtin reads + perl fallback path preserved"

iter180_assert_substring_present_in_harness_with_human_readable_label \
    "B1: BASH_VERSINFO[0] >= 5 dispatch gate (selects builtin vs perl-fallback path)" \
    "BASH_VERSINFO[0] >= 5"

# Single-quoted literal-dollar-sign search strings are intentional — we grep
# for literal ${EPOCHREALTIME} source-text substrings, not shell expansions.
# Shellcheck SC2016 false-positive in this context.
# shellcheck disable=SC2016
iter180_assert_substring_present_in_harness_with_human_readable_label \
    'B2: ${EPOCHREALTIME} read in before-invocation position' \
    'before_invocation_epoch_realtime="$EPOCHREALTIME"'

# shellcheck disable=SC2016
iter180_assert_substring_present_in_harness_with_human_readable_label \
    'B3: ${EPOCHREALTIME} read in after-invocation position' \
    'after_invocation_epoch_realtime="$EPOCHREALTIME"'

# shellcheck disable=SC2016
iter180_assert_substring_present_in_harness_with_human_readable_label \
    "B4: perl Time::HiRes fallback path preserved for bash<5 compatibility" \
    'perl -MTime::HiRes=time -e '"'"'printf "%.6f", time()'"'"''

# ─── Group C: docstring cites iter-177 dogfood provenance + meta-recursive nature ───
echo ""
echo "GROUP C (2 assertions): iter-174 source cites iter-177 dogfood provenance + meta-recursive framing"

iter180_assert_substring_present_in_harness_with_human_readable_label \
    "C1: iter-174 cites iter-180 dogfood of iter-177 pattern provenance" \
    "Iter-180 dogfood of iter-177 pattern"

iter180_assert_substring_present_in_harness_with_human_readable_label \
    "C2: iter-174 cites meta-recursive framing (perf-baseline tool eats own perf-optimization dogfood)" \
    "eats its own perf-optimization"

# ─── Group D: end-to-end harness invocation still emits banner + PASS verdicts ───
echo ""
echo "GROUP D (2 assertions): end-to-end harness invocation behavior preserved (regression-safe)"

ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE=$(bash "$ITER180_ITER174_HARNESS_ABSOLUTE_PATH" 2>&1 || true)

ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE" == *"ITER-174 EMPIRICAL WALL-CLOCK PERF-BASELINE REGRESSION HARNESS"* ]] && \
   [[ "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE" == *"GROUP A (5 assertions)"* ]] && \
   [[ "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE" == *"headroom unused"* ]]; then
    echo "  ✓ D1: human-mode emits banner header + GROUP A line + headroom-unused signature (iter-180 refactor regression-safe)"
else
    echo "  ✗ D1: human-mode missing expected output signatures — iter-180 refactor broke pre-existing behavior"
    ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Count the per-scenario PASS verdicts ('✓ A' prefix) — must be 6 (A1-A6).
ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER180_PASS_VERDICT_COUNT=$(echo "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE" | grep -cE '^\s*✓ A[1-6]:' || true)
if (( ITER180_PASS_VERDICT_COUNT == 6 )); then
    echo "  ✓ D2: human-mode emits exactly 6 PASS verdicts (A1-A6) — every toolkit script measured + within cap post-iter-180"
else
    echo "  ✗ D2: human-mode emits $ITER180_PASS_VERDICT_COUNT PASS verdicts (expected 6) — iter-180 refactor may have broken measurement loop"
    ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: --json envelope still parses cleanly (regression-safe) ───────
echo ""
echo "GROUP E (2 assertions): --json envelope still parses cleanly after iter-180 refactor (iter-179 dual-mode preserved)"

ITER180_HARNESS_JSON_MODE_OUTPUT_CAPTURE=$(bash "$ITER180_ITER174_HARNESS_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    if echo "$ITER180_HARNESS_JSON_MODE_OUTPUT_CAPTURE" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["iter174_schema_version"]==1; assert len(d["results"])==6; assert d["summary"]["overall_verdict"] in ("PASS","REGRESS"); assert all(isinstance(r["median_ms"], int) and r["median_ms"] >= 0 for r in d["results"])' 2>/dev/null; then
        echo "  ✓ E1: --json envelope parses cleanly post-iter-180 + schema_version==1 + exactly 6 results + every median_ms is non-negative integer"
    else
        echo "  ✗ E1: --json envelope FAILS python3 schema assertion after iter-180 refactor"
        echo "      (envelope head: $(echo "$ITER180_HARNESS_JSON_MODE_OUTPUT_CAPTURE" | head -3))"
        ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E1: python3 not available — SKIPPED (assertion uncounted)"
    ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# E2: human-mode and --json mode must yield consistent verdict (both PASS or both REGRESS).
ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE" == *"7/7 assertions PASSED"* ]] && \
   [[ "$ITER180_HARNESS_JSON_MODE_OUTPUT_CAPTURE" == *'"overall_verdict": "PASS"'* ]]; then
    echo "  ✓ E2: human-mode and --json mode yield consistent PASS verdict (no mode-divergence regression)"
else
    echo "  ✗ E2: human-mode + --json mode verdict inconsistency — mode dispatch may have regressed"
    ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: iter-156 dispatcher QUALITY + PERFORMANCE section cites iter-180 ───
echo ""
echo "GROUP F (1 assertion): iter-156 dispatcher banner QUALITY + PERFORMANCE section cites iter-180 dogfood entry"

iter180_assert_substring_present_in_dispatcher_with_human_readable_label \
    "F1: iter-156 dispatcher has iter-180 EPOCHREALTIME meta-recursive dogfood entry under QUALITY + PERFORMANCE" \
    "iter-180 iter-174 perf-baseline harness EPOCHREALTIME zero-fork dogfood"

# ─── Group G: bash -n + shellcheck clean ───────────────────────────────────
echo ""
echo "GROUP G (2 assertions): iter-174 harness passes bash -n + shellcheck after iter-180 dogfood refactor"

ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER180_ITER174_HARNESS_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ G1: iter-174 passes bash -n syntax check after iter-180 dogfood refactor"
else
    echo "  ✗ G1: iter-174 FAILS bash -n syntax check after iter-180 dogfood refactor"
    ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER180_ITER174_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ G2: iter-174 passes shellcheck zero-warning after iter-180 dogfood refactor"
    else
        echo "  ✗ G2: iter-174 has shellcheck warnings after iter-180 dogfood refactor"
        ITER180_TOTAL_ASSERTIONS_FAILED=$((ITER180_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ G2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER180_TOTAL_ASSERTIONS_EVALUATED=$((ITER180_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER180_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-180 REGRESSION TEST: ${ITER180_TOTAL_ASSERTIONS_EVALUATED}/${ITER180_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-180 REGRESSION TEST: $((ITER180_TOTAL_ASSERTIONS_EVALUATED - ITER180_TOTAL_ASSERTIONS_FAILED))/${ITER180_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER180_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
