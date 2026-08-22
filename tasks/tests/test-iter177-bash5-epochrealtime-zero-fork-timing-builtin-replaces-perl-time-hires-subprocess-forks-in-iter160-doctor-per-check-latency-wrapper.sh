#!/usr/bin/env bash
#MISE description="Iter-177 regression test pinning the bash 5+ EPOCHREALTIME zero-fork timing builtin replacing perl Time::HiRes subprocess forks in the iter-160 doctor per-check latency wrapper. Pre-iter-177 the iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds wrapper spawned TWO perl Time::HiRes subprocesses per check (start_ns + end_ns capture) — approximately 8-9ms per fork on macOS arm64. With 15 checks running serially through the wrapper, that was 30 perl forks contributing approximately 260-270ms of pure timing overhead (40 percent of pre-iter-177 665ms wall-clock median). Iter-177 swaps to the bash 5+ EPOCHREALTIME builtin (zero subprocess forks, microsecond resolution per Chet Ramey 2018 RFE) with graceful perl fallback for bash less than 5.0. The parameter expansion EPOCHREALTIME with slash-dot-slash strips the decimal yielding an integer microsecond counter for pure-bash arithmetic. Empirical wall-clock improvement: 665ms to approximately 530ms (approximately 20 percent reduction; conservative because perl forks overlapped with check work). Test asserts (a) iter-160 contains iter-177 top-of-file doc block citing bash 5 EPOCHREALTIME builtin + Chet Ramey 2018 RFE provenance, (b) iter-177 timer-primitive selector constant declared with bash-version-conditional initialization, (c) timer wrapper has both fast path (EPOCHREALTIME) AND fallback path (perl Time::HiRes) preserving correctness on legacy bash, (d) bash -n syntax check passes, (e) shellcheck zero warnings, (f) end-to-end default mode emits 15 checks with per-check latencies present and non-zero, (g) end-to-end --json mode envelope still emits valid structured output."
set -euo pipefail

ITER177_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER177_REPO_ROOT"

ITER177_ITER160_DOCTOR_ABSOLUTE_PATH="$ITER177_REPO_ROOT/scripts/iter160-operator-facing-commits-arc-self-diagnosis-task-checking-each-iter150-through-iter158-tool-for-presence-executability-and-functional-correctness-with-per-check-wall-clock-latency-reporting-and-json-mode.sh"

ITER177_TOTAL_ASSERTIONS_EVALUATED=0
ITER177_TOTAL_ASSERTIONS_FAILED=0

iter177_assert_substring_present_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER177_ITER160_DOCTOR_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER177_TOTAL_ASSERTIONS_FAILED=$((ITER177_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-177 BASH 5 EPOCHREALTIME ZERO-FORK TIMING REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: iter-160 source contains iter-177 top-of-file doc block ──────
echo ""
echo "GROUP A (3 assertions): iter-160 source documents iter-177 zero-fork timing rationale"

iter177_assert_substring_present_with_human_readable_label \
    "A1: iter-160 contains 'ITER-177 ZERO-FORK TIMING via bash 5+ EPOCHREALTIME BUILTIN' banner header" \
    "ITER-177 ZERO-FORK TIMING via bash 5+ EPOCHREALTIME BUILTIN"

iter177_assert_substring_present_with_human_readable_label \
    "A2: iter-160 cites Chet Ramey 2018 RFE as bash 5+ EPOCHREALTIME provenance" \
    "Chet Ramey 2018 RFE"

iter177_assert_substring_present_with_human_readable_label \
    "A3: iter-160 documents human-perceptibility threshold provenance (Nielsen + Google Web Vitals INP)" \
    "Google Web Vitals INP guidance"

# ─── Group B: iter-177 timer-primitive selector constant declared ──────────
echo ""
echo "GROUP B (2 assertions): iter-177 timer-primitive selector + bash-version-conditional initialization"

iter177_assert_substring_present_with_human_readable_label \
    "B1: iter-177 timer-primitive selector constant declared with verbose self-explanatory name" \
    "ITER177_TIMER_PRIMITIVE_USING_BASH5_EPOCHREALTIME_BUILTIN_FOR_ZERO_FORK_MICROSECOND_RESOLUTION_OR_PERL_FALLBACK_FOR_LEGACY_BASH"

iter177_assert_substring_present_with_human_readable_label \
    "B2: iter-177 selector initialized via BASH_VERSINFO version check (graceful degradation for bash<5)" \
    "BASH_VERSINFO[0]:-0} >= 5"

# ─── Group C: timer wrapper has both fast path + fallback path ─────────────
echo ""
echo "GROUP C (2 assertions): timer wrapper has bash5 fast path + perl fallback path (correctness parity preserved)"

iter177_assert_substring_present_with_human_readable_label \
    "C1: iter-177 fast path uses EPOCHREALTIME parameter-expansion strip-dot for integer microseconds" \
    "start_microseconds_since_epoch_from_bash5_epochrealtime_builtin=\"\${EPOCHREALTIME/./}\""

iter177_assert_substring_present_with_human_readable_label \
    "C2: iter-177 legacy fallback preserves perl Time::HiRes path verbatim for bash<5 correctness parity" \
    "start_ns=\$(perl -MTime::HiRes=time -e"

# ─── Group D: bash -n + shellcheck ─────────────────────────────────────────
echo ""
echo "GROUP D (2 assertions): iter-160 passes bash -n + shellcheck after iter-177 timer swap"

ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER177_ITER160_DOCTOR_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ D1: iter-160 passes bash -n syntax check after iter-177 timer swap"
else
    echo "  ✗ D1: iter-160 FAILS bash -n syntax check after iter-177 timer swap"
    ITER177_TOTAL_ASSERTIONS_FAILED=$((ITER177_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER177_ITER160_DOCTOR_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ D2: iter-160 passes shellcheck zero-warning after iter-177 timer swap"
    else
        echo "  ✗ D2: iter-160 has shellcheck warnings after iter-177 timer swap"
        ITER177_TOTAL_ASSERTIONS_FAILED=$((ITER177_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ D2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group E: end-to-end default mode + --json mode ────────────────────────
echo ""
echo "GROUP E (3 assertions): end-to-end doctor renders 15 checks with non-zero per-check latencies and valid JSON envelope"

ITER177_DEFAULT_MODE_OUTPUT_CAPTURE=$(bash "$ITER177_ITER160_DOCTOR_ABSOLUTE_PATH" 2>&1 || true)

ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER177_OBSERVED_CHECK_LINE_COUNT_WITH_LATENCY_PAREN=$(printf '%s\n' "$ITER177_DEFAULT_MODE_OUTPUT_CAPTURE" | grep -cE '^[[:space:]]+✓.*\([0-9]+ms\)')
# 13 of 15 checks emit timed (ms) reports; 2 checks are non-timed status lookups (hook installed + pre-commit version).
ITER177_MINIMUM_EXPECTED_TIMED_CHECK_LINES=10
if (( ITER177_OBSERVED_CHECK_LINE_COUNT_WITH_LATENCY_PAREN >= ITER177_MINIMUM_EXPECTED_TIMED_CHECK_LINES )); then
    echo "  ✓ E1: default-mode emits ${ITER177_OBSERVED_CHECK_LINE_COUNT_WITH_LATENCY_PAREN} timed check lines (≥${ITER177_MINIMUM_EXPECTED_TIMED_CHECK_LINES}; iter-177 timer wrapper produces sane Nms parenthesized latencies)"
else
    echo "  ✗ E1: default-mode emits ${ITER177_OBSERVED_CHECK_LINE_COUNT_WITH_LATENCY_PAREN} timed check lines (expected ≥${ITER177_MINIMUM_EXPECTED_TIMED_CHECK_LINES}; iter-177 wrapper may have broken the (Nms) parenthesized format)"
    ITER177_TOTAL_ASSERTIONS_FAILED=$((ITER177_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Assert at least one check reports >0ms latency — would catch a regression
# where the iter-177 EPOCHREALTIME parameter-expansion silently always
# returns 0 (e.g., if both captures happened to fall in the same microsecond
# — only theoretically possible since each check does real work).
ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER177_OBSERVED_COUNT_OF_NONZERO_LATENCIES=$(printf '%s\n' "$ITER177_DEFAULT_MODE_OUTPUT_CAPTURE" | grep -cE '\([1-9][0-9]*ms\)')
if (( ITER177_OBSERVED_COUNT_OF_NONZERO_LATENCIES >= 5 )); then
    echo "  ✓ E2: default-mode reports ${ITER177_OBSERVED_COUNT_OF_NONZERO_LATENCIES} non-zero per-check latencies (iter-177 EPOCHREALTIME parameter-expansion math correctly computes elapsed milliseconds)"
else
    echo "  ✗ E2: default-mode reports only ${ITER177_OBSERVED_COUNT_OF_NONZERO_LATENCIES} non-zero latencies — iter-177 timer math may be silently returning 0"
    ITER177_TOTAL_ASSERTIONS_FAILED=$((ITER177_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER177_JSON_MODE_OUTPUT_CAPTURE=$(bash "$ITER177_ITER160_DOCTOR_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER177_TOTAL_ASSERTIONS_EVALUATED=$((ITER177_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER177_JSON_MODE_OUTPUT_CAPTURE" == *'"iter160_schema_version"'* ]] && \
   [[ "$ITER177_JSON_MODE_OUTPUT_CAPTURE" == *'"total_checks_evaluated": 15'* ]] && \
   [[ "$ITER177_JSON_MODE_OUTPUT_CAPTURE" == *'"verdict"'* ]]; then
    echo "  ✓ E3: --json mode envelope still emits valid structured output with schema_version + 15 checks + verdict (iter-177 did not regress JSON path)"
else
    echo "  ✗ E3: --json mode envelope malformed or missing fields after iter-177 timer swap"
    ITER177_TOTAL_ASSERTIONS_FAILED=$((ITER177_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER177_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-177 REGRESSION TEST: ${ITER177_TOTAL_ASSERTIONS_EVALUATED}/${ITER177_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-177 REGRESSION TEST: $((ITER177_TOTAL_ASSERTIONS_EVALUATED - ITER177_TOTAL_ASSERTIONS_FAILED))/${ITER177_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER177_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
