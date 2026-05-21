#!/usr/bin/env bash
#MISE description="Iter-179 regression test pinning the dual-mode --json output added to the iter-174 perf-baseline regression harness. Pre-iter-179 the harness emitted only human-readable text — AI agents and CI pipelines consuming the regression-detection output had to regex-parse fragile UI strings (e.g., 'median=Xms ≤ cap=Yms (Z% headroom unused)'). Iter-179 closes this dual-mode gap by adding a stable JSON envelope with iter174_schema_version=1 under --json while preserving human-readable text under the default no-flag invocation. Schema records per-scenario {id, description, median_ms, cap_ms, headroom_pct_signed, verdict} plus aggregate {total_evaluated, total_failed, total_passed, overall_verdict}. Mirrors the iter-152 dashboard / iter-153 advisor / iter-160 doctor / iter-165 aggregator --json dual-mode pattern. Test asserts (a) iter-174 source contains iter-179 dual-mode doc block, (b) iter-179 output-mode selector constant + helper function defined, (c) --json arg dispatch parsing present, (d) human-mode invocation still emits banner header + per-scenario PASS lines (no JSON envelope, regression-safe), (e) --json mode invocation emits valid parseable JSON envelope with all 7 expected scenario records + summary block, (f) --json mode envelope contains required schema fields (iter174_schema_version, results array, summary with overall_verdict), (g) bash -n + shellcheck clean."
set -euo pipefail

ITER179_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER179_REPO_ROOT"

ITER179_ITER174_HARNESS_ABSOLUTE_PATH="$ITER179_REPO_ROOT/.mise/tasks/tests/test-iter174-empirical-wall-clock-perf-baseline-regression-harness-for-conventional-commits-toolkit-pinning-current-median-latencies-of-iter150-iter152-iter153-iter165-with-regression-detection-against-three-x-headroom-cap.sh"

ITER179_TOTAL_ASSERTIONS_EVALUATED=0
ITER179_TOTAL_ASSERTIONS_FAILED=0

iter179_assert_substring_present_in_harness_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER179_ITER174_HARNESS_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-179 PERF-BASELINE HARNESS DUAL-MODE --json OUTPUT REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: iter-174 source contains iter-179 dual-mode doc block ─────────
echo ""
echo "GROUP A (3 assertions): iter-174 source documents iter-179 dual-mode rationale"

iter179_assert_substring_present_in_harness_with_human_readable_label \
    "A1: iter-174 contains 'ITER-179 DUAL-MODE OUTPUT' banner header" \
    "ITER-179 DUAL-MODE OUTPUT: HUMAN-READABLE DEFAULT OR --json FOR AI AGENTS"

iter179_assert_substring_present_in_harness_with_human_readable_label \
    "A2: iter-174 documents the iter-152/153/160/165 dual-mode pattern provenance" \
    "Mirrors the iter-152 dashboard / iter-153 advisor / iter-160 doctor"

iter179_assert_substring_present_in_harness_with_human_readable_label \
    "A3: iter-174 cites stable iter174_schema_version=1 contract for AI-agent consumers" \
    "iter174_schema_version=1"

# ─── Group B: iter-179 selector constant + helper function defined ─────────
echo ""
echo "GROUP B (2 assertions): iter-179 output-mode selector + text-suppression helper function declared"

iter179_assert_substring_present_in_harness_with_human_readable_label \
    "B1: iter-179 output-mode selector constant declared with verbose self-explanatory name + default human" \
    "ITER179_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION=\"human\""

iter179_assert_substring_present_in_harness_with_human_readable_label \
    "B2: iter-179 text-suppression helper function declared (suppresses banner echos in --json mode)" \
    "iter179_emit_text_only_in_human_readable_mode_suppress_in_json_mode_to_keep_stdout_parse_clean()"

# ─── Group C: --json arg dispatch parsing ──────────────────────────────────
echo ""
echo "GROUP C (1 assertion): --json arg parsed via case dispatch at script entry"

iter179_assert_substring_present_in_harness_with_human_readable_label \
    "C1: --json arg parsed via for-loop + case dispatch (allows positional arg ordering flexibility)" \
    "ITER179_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION=\"json\""

# ─── Group D: human-mode invocation preserves pre-iter-179 behavior ────────
echo ""
echo "GROUP D (2 assertions): human-mode invocation preserves pre-iter-179 banner + per-scenario PASS line behavior (regression-safe)"

ITER179_HUMAN_MODE_OUTPUT_CAPTURE=$(bash "$ITER179_ITER174_HARNESS_ABSOLUTE_PATH" 2>&1 || true)

ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER179_HUMAN_MODE_OUTPUT_CAPTURE" == *"ITER-174 EMPIRICAL WALL-CLOCK PERF-BASELINE REGRESSION HARNESS"* ]] && \
   [[ "$ITER179_HUMAN_MODE_OUTPUT_CAPTURE" == *"GROUP A (5 assertions)"* ]] && \
   [[ "$ITER179_HUMAN_MODE_OUTPUT_CAPTURE" == *"headroom unused"* ]]; then
    echo "  ✓ D1: human-mode emits banner header + GROUP A line + headroom-unused signature (text mode unchanged)"
else
    echo "  ✗ D1: human-mode missing banner / GROUP header / headroom-unused signature — pre-iter-179 behavior regressed"
    ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Assert human-mode output does NOT contain JSON envelope opening — the
# two modes must be cleanly separated.
ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER179_HUMAN_MODE_OUTPUT_CAPTURE" != *'"iter174_schema_version"'* ]]; then
    echo "  ✓ D2: human-mode output does NOT contain JSON envelope (clean mode separation, no cross-contamination)"
else
    echo "  ✗ D2: human-mode output LEAKED JSON envelope — mode dispatch broken"
    ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: --json mode emits valid parseable JSON envelope ──────────────
echo ""
echo "GROUP E (4 assertions): --json mode emits valid parseable JSON envelope with expected schema shape"

ITER179_JSON_MODE_OUTPUT_CAPTURE=$(bash "$ITER179_ITER174_HARNESS_ABSOLUTE_PATH" --json 2>/dev/null || true)

# E1: JSON envelope opens with iter174_schema_version=1 field.
iter179_assert_substring_present_in_json_capture_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$ITER179_JSON_MODE_OUTPUT_CAPTURE" == *"$expected_substring"* ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing from --json output: ${expected_substring:0:60})"
        ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter179_assert_substring_present_in_json_capture_with_human_readable_label \
    "E1: --json envelope has iter174_schema_version=1 contract field" \
    '"iter174_schema_version": 1'

iter179_assert_substring_present_in_json_capture_with_human_readable_label \
    "E2: --json envelope has results array containing scenario A1 (iter-150 renderer)" \
    '"id": "A1"'

iter179_assert_substring_present_in_json_capture_with_human_readable_label \
    "E3: --json envelope has summary block with overall_verdict field" \
    '"overall_verdict"'

# E4: end-to-end JSON validity — try parsing with python3 (universally available macOS).
ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v python3 >/dev/null 2>&1; then
    if echo "$ITER179_JSON_MODE_OUTPUT_CAPTURE" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["iter174_schema_version"]==1; assert len(d["results"])>=6; assert d["summary"]["overall_verdict"] in ("PASS","REGRESS")' 2>/dev/null; then
        echo "  ✓ E4: --json envelope parses as valid JSON via python3 + schema_version==1 + results-array-length≥6 + overall_verdict in {PASS,REGRESS}"
    else
        echo "  ✗ E4: --json envelope FAILS python3 JSON parse OR schema assertion"
        echo "      (envelope head: $(echo "$ITER179_JSON_MODE_OUTPUT_CAPTURE" | head -3))"
        ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E4: python3 not available — SKIPPED (assertion uncounted)"
    ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group F: bash -n + shellcheck ─────────────────────────────────────────
echo ""
echo "GROUP F (2 assertions): iter-174 harness passes bash -n + shellcheck after iter-179 dual-mode refactor"

ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER179_ITER174_HARNESS_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ F1: iter-174 passes bash -n syntax check after iter-179 dual-mode refactor"
else
    echo "  ✗ F1: iter-174 FAILS bash -n syntax check after iter-179 dual-mode refactor"
    ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER179_ITER174_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ F2: iter-174 passes shellcheck zero-warning after iter-179 dual-mode refactor"
    else
        echo "  ✗ F2: iter-174 has shellcheck warnings after iter-179 dual-mode refactor"
        ITER179_TOTAL_ASSERTIONS_FAILED=$((ITER179_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ F2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER179_TOTAL_ASSERTIONS_EVALUATED=$((ITER179_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER179_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-179 REGRESSION TEST: ${ITER179_TOTAL_ASSERTIONS_EVALUATED}/${ITER179_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-179 REGRESSION TEST: $((ITER179_TOTAL_ASSERTIONS_EVALUATED - ITER179_TOTAL_ASSERTIONS_FAILED))/${ITER179_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER179_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
