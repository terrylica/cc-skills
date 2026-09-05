#!/usr/bin/env bash
# Iter-180 regression test pinning the meta-recursive dogfood of the iter-177 bash 5+ EPOCHREALTIME zero-fork builtin pattern into the iter-174 perf-baseline harness's OWN per-trial timing wrapper. Pre-iter-180 the harness designed to detect regressions in OTHER scripts still used 2 perl-MTime::HiRes forks per trial × 5 trials × 6 scenarios = 60 perl forks per commits:perf-baseline invocation, contributing ~300ms of harness self-overhead (~5% of total wall-clock) — ironic since iter-177 had just applied this exact optimization to iter-160 doctor. Iter-180 closes this meta-recursive dogfood gap: the perf-baseline tool now eats its own perf-optimization dogfood. Test asserts (a) timing function renamed to encode bash5_epochrealtime_zero_fork_builtin idiom with perl_time_hires_graceful_fallback suffix, (b) BASH_VERSINFO[0] gate dispatching between bash5+ builtin and perl fallback, (c) EPOCHREALTIME reads present in both before/after positions of the per-trial timing block, (d) perl Time::HiRes fallback path preserved for bash<5 compatibility, (e) docstring cites iter-177 dogfood provenance + meta-recursive nature, (f) end-to-end harness invocation still emits banner + 6 PASS verdicts (regression-safe), (g) --json envelope still parses cleanly with 6 scenario records + iter174_schema_version=1 (regression-safe), (h) iter-156 dispatcher QUALITY + PERFORMANCE section cites iter-180 dogfood entry, (i) bash -n + shellcheck clean.
set -euo pipefail

ITER180_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER180_REPO_ROOT"

ITER180_ITER174_HARNESS_ABSOLUTE_PATH="$ITER180_REPO_ROOT/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"
ITER180_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER180_REPO_ROOT/tasks/commits/_default"

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

# ─── Failure-diagnosis helpers (observability only; no gate is relaxed) ──────
#
# WHY: E2 below compares TWO SEPARATE invocations of the iter-174 harness. When
# a load-sensitive scenario gate fails in one invocation and not the other, the
# assertion is correct to fire — but its message named MODE DISPATCH as the
# cause, which the check never established. On 2026-09-03 four red suite runs
# had to be triaged by hand for exactly that reason: the message asserted a
# cause, and the evidence needed to disprove it was never printed.
#
# These helpers print WHICH clause failed and WHICH scenario failed, and emit a
# stable machine-readable token so log triage reads a fact instead of inferring
# one from prose. They are called ONLY from else-branches; every condition in
# this file is byte-for-byte unchanged.

# ── NEGATIVE CONTROL for this diagnostic (run before trusting it) ───────────
#
# BOTH halves are required. "Still fails" alone proves nothing was loosened but
# not that the capture works; "names the cause" alone proves the capture works
# but not that the gate still bites. Either half on its own is the shape of a
# check that passes for the wrong reason.
#
#   HALF 1 — the gate still bites, and now says why.
#     Temporarily pin an impossible cap on one scenario in the iter-174 harness
#     (e.g. set the A5 backlog-proportional cap expression to 1), then:
#         bash tasks/tests/test-iter180-...-sixty-perl-forks-per-invocation.sh
#     EXPECT: E2 still reports ✗ (nothing was relaxed), AND the output now
#     contains [HARNESS-SCENARIO-FAILURE] naming A5 with its median and cap.
#     Revert the pin.
#
#   HALF 2 — a defect with NO scenario failure is positively distinguished.
#     Temporarily make the harness echo the literal iter174_schema_version in
#     human mode, leaving every scenario passing, then run the iter-182 sibling:
#         bash tasks/tests/test-iter182-...-hyperfine-industry-gap.sh
#     EXPECT: C1 reports ✗ with "clause 3 FAILED", AND the output contains
#     [HARNESS-NO-SCENARIO-FAILURE] — proving a genuine leak is NOT reported as
#     contention. Revert the echo.
#
#   Then re-run both unmodified and confirm each returns to a full PASS, so the
#   controls are shown to be reversible rather than leaving a latent failure.

# Print the harness's own failing scenario lines from a human-mode capture.
iter180_name_failing_harness_scenarios_in_human_mode_capture() {
    local harness_output_capture="$1"
    local failing_scenario_lines
    # `|| true`: grep exits 1 on no-match, and `set -e` would treat that as fatal.
    failing_scenario_lines=$(printf '%s\n' "$harness_output_capture" | grep -E '^[[:space:]]*✗ A[0-9]+:' || true)
    if [[ -z "$failing_scenario_lines" ]]; then
        echo "      [HARNESS-NO-SCENARIO-FAILURE] human-mode: no '✗ A<n>' line — every scenario"
        echo "        passed, so this is NOT a scenario regression and mode dispatch is a real suspect."
        return 0
    fi
    echo "      [HARNESS-SCENARIO-FAILURE] human-mode: a scenario gate failed, so the mode"
    echo "        disagreement is a SYMPTOM of that failure, not evidence of a dispatch regression:"
    # `awk`, never `head`: `head` closes the pipe and kills `grep` with SIGPIPE,
    # which `pipefail` promotes into a silent abort. The iter-182 sibling
    # documents this exact trap in its own iter-186 fix comment.
    printf '%s\n' "$failing_scenario_lines" | awk 'NR<=5 { print "        " $0 }'
}

# Same intent for a --json capture. Deliberately schema-light: the envelope's
# per-scenario record shape is under active iter-186 edit, so this greps for the
# verdict string rather than parsing fields that may be renamed tomorrow.
iter180_name_failing_harness_scenarios_in_json_mode_capture() {
    local harness_output_capture="$1"
    local regress_lines
    regress_lines=$(printf '%s\n' "$harness_output_capture" | grep -F 'REGRESS' || true)
    if [[ -z "$regress_lines" ]]; then
        echo "      [HARNESS-NO-SCENARIO-FAILURE] --json: no REGRESS verdict in the envelope —"
        echo "        the envelope may be malformed or truncated rather than reporting a regression."
        return 0
    fi
    echo "      [HARNESS-SCENARIO-FAILURE] --json: the envelope reports a regression; the"
    echo "        per-scenario verdicts live in its results[] array:"
    printf '%s\n' "$regress_lines" | awk 'NR<=5 { print "        " $0 }'
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-180 META-RECURSIVE EPOCHREALTIME DOGFOOD REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: timing function renamed to encode the bash5 + perl-fallback idiom ───
echo ""
echo "GROUP A (2 assertions): timing function renamed to encode bash5 EPOCHREALTIME zero-fork builtin idiom with perl Time::HiRes graceful fallback"

iter180_assert_substring_present_in_harness_with_human_readable_label \
    "A1: timing function name encodes bash5_epochrealtime_zero_fork_builtin idiom (suffix-pin absorbs iter-183 function rename)" \
    "bash5_epochrealtime_zero_fork_builtin_with_perl_time_hires_graceful_fallback_for_bash4_or_older"

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
    echo "  ✗ E2: human-mode + --json mode verdict inconsistency"
    # Name the clause that actually failed. The previous single-line message
    # asserted "mode dispatch may have regressed" for BOTH clauses, which is a
    # cause this check never establishes — the two clauses read two separate
    # harness invocations, and either can fail on its own.
    if [[ "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE" != *"7/7 assertions PASSED"* ]]; then
        echo "      clause 1 FAILED: human-mode capture did not contain '7/7 assertions PASSED'"
    fi
    if [[ "$ITER180_HARNESS_JSON_MODE_OUTPUT_CAPTURE" != *'"overall_verdict": "PASS"'* ]]; then
        echo "      clause 2 FAILED: --json capture did not contain overall_verdict PASS"
    fi
    # Both helpers run UNCONDITIONALLY, so exactly one token is emitted per
    # invocation whichever clause failed. Calling them only inside the failing
    # clause left a real hole: a defect that trips a clause WITHOUT any scenario
    # failing would emit no token at all, and a log reader keying on the tokens
    # would fall back to "probable contention" for what is a genuine defect —
    # the precise misdiagnosis this whole change exists to remove.
    iter180_name_failing_harness_scenarios_in_human_mode_capture "$ITER180_HARNESS_HUMAN_MODE_OUTPUT_CAPTURE"
    iter180_name_failing_harness_scenarios_in_json_mode_capture "$ITER180_HARNESS_JSON_MODE_OUTPUT_CAPTURE"
    echo "      NOTE: these are two SEPARATE invocations of the harness. A load-sensitive"
    echo "        scenario gate failing in one and not the other produces this disagreement"
    echo "        without any dispatch bug existing."
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
