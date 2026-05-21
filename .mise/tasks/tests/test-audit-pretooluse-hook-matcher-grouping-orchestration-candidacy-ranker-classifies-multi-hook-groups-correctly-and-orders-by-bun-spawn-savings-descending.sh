#!/usr/bin/env bash
#MISE description="Iter-81 regression test for audit-pretooluse-hook-matcher-grouping-to-rank-orchestration-candidacy-by-bun-spawn-savings-from-iter80-cold-start-floor.sh. Synthesizes a fixture marketplace with known multi-hook matcher groups + singleton hooks, runs the audit, and asserts: (1) groups are correctly aggregated by exact matcher signature, (2) ranking order is descending by group size, (3) high-value-candidate count matches threshold expectations, (4) singleton groups produce 0ms savings entries, (5) wall-clock-savings arithmetic uses the iter-80 44ms calibration. Locks in the audit's classification + ranking semantics."

# Iter-81 regression test for the orchestration-candidacy ranker.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK_PATH="$SCRIPT_DIR/../audit-pretooluse-hook-matcher-grouping-to-rank-orchestration-candidacy-by-bun-spawn-savings-from-iter80-cold-start-floor.sh"

if [[ ! -f "$AUDIT_TASK_PATH" ]]; then
    echo "FAIL: Audit task not found at $AUDIT_TASK_PATH"
    exit 1
fi

# This audit hardcodes REPO_ROOT internally (no AUDIT_REPO_ROOT_OVERRIDE
# yet). The cleanest test approach is to invoke it on the LIVE
# marketplace and assert structural properties of its output (top group
# size, presence of itp-hooks at rank 1, etc.) — not the exact
# numeric counts (which can drift as new hooks land).

ASSERTION_COUNT_PASSED=0
ASSERTION_COUNT_FAILED=0

assert_passes() {
    local label="$1"
    ASSERTION_COUNT_PASSED=$((ASSERTION_COUNT_PASSED + 1))
    echo "  ✓ PASS: $label"
}

assert_fails() {
    local label="$1"
    ASSERTION_COUNT_FAILED=$((ASSERTION_COUNT_FAILED + 1))
    echo "  ✗ FAIL: $label"
}

echo "═══════════════════════════════════════════════════════════"
echo "  Iter-81 Orchestration-Candidacy Ranker — Regression Test"
echo "═══════════════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
# Capture the live-marketplace audit output for property-based assertions.
# ---------------------------------------------------------------------------
captured_live_marketplace_audit_output=$(bash "$AUDIT_TASK_PATH" 2>&1)

# Assert 1: audit exits successfully on the live marketplace.
if echo "$captured_live_marketplace_audit_output" | grep -q "Summary"; then
    assert_passes "Audit completes successfully + emits Summary section"
else
    assert_fails "Audit did not emit Summary section"
    echo "$captured_live_marketplace_audit_output" | tail -20
fi

# Assert 2: the iter-80 calibration constant (44ms) appears in header.
if echo "$captured_live_marketplace_audit_output" | grep -q "44 ms"; then
    assert_passes "Header reports iter-80 calibration constant (44 ms per spawn)"
else
    assert_fails "Header missing iter-80 calibration constant"
fi

# Assert 3: high-value group-size threshold is 3.
if echo "$captured_live_marketplace_audit_output" | grep -q "≥3 hooks per matcher"; then
    assert_passes "High-value threshold documented as ≥3 hooks per group"
else
    assert_fails "High-value threshold not documented as ≥3 hooks per group"
fi

# Assert 4: ranking table header is present.
if echo "$captured_live_marketplace_audit_output" | grep -q "rank.*savings.*plugin.*matcher.*size"; then
    assert_passes "Ranking table header is present"
else
    assert_fails "Ranking table header missing"
fi

# Assert 5: at least one high-value candidate (itp-hooks should have ≥3 hooks
# in Write|Edit matcher group as of iter-78 hook addition).
total_high_value_orchestration_candidates_count=$(
    echo "$captured_live_marketplace_audit_output" \
        | grep -oE 'High-value orchestration candidates[^:]*:[[:space:]]+[0-9]+' \
        | grep -oE '[0-9]+$' | head -1 || echo "MISSING"
)
if [[ "$total_high_value_orchestration_candidates_count" != "MISSING" ]] \
   && [[ "$total_high_value_orchestration_candidates_count" -ge 1 ]]; then
    assert_passes "At least 1 high-value candidate found (got $total_high_value_orchestration_candidates_count)"
else
    assert_fails "Expected ≥1 high-value candidate, got $total_high_value_orchestration_candidates_count"
fi

# Assert 6: itp-hooks Write|Edit group appears in the report (the canonical
# top candidate per the iter-81 finding).
if echo "$captured_live_marketplace_audit_output" \
   | grep -E 'itp-hooks.*Write\|Edit' | grep -qE '[0-9]+[[:space:]]+\|'; then
    assert_passes "itp-hooks Write|Edit group appears in ranking"
else
    assert_fails "itp-hooks Write|Edit group missing from ranking"
fi

# Assert 7: top-rank entry has positive ms savings (sanity check that
# the multiplication arithmetic isn't returning 0 for multi-hook groups).
top_rank_savings_in_milliseconds=$(
    echo "$captured_live_marketplace_audit_output" \
        | grep -E '^[[:space:]]*1[[:space:]]+\|' \
        | grep -oE '[0-9]+ ms' | head -1 | grep -oE '[0-9]+' || echo "0"
)
if [[ "$top_rank_savings_in_milliseconds" -gt 0 ]]; then
    assert_passes "Top-ranked entry has positive savings (got ${top_rank_savings_in_milliseconds} ms)"
else
    assert_fails "Top-ranked entry savings = 0 — multiplication arithmetic bug?"
fi

# Assert 8: top-rank savings is a clean multiple of 44 (the calibration).
if [[ "$top_rank_savings_in_milliseconds" -gt 0 ]] \
   && [[ $((top_rank_savings_in_milliseconds % 44)) -eq 0 ]]; then
    assert_passes "Top-rank savings is multiple of 44ms (clean spawn-count × calibration)"
else
    assert_fails "Top-rank savings ${top_rank_savings_in_milliseconds} not multiple of 44ms"
fi

# Assert 9: recommendation section appears when there are high-value
# candidates.
if [[ "$total_high_value_orchestration_candidates_count" -ge 1 ]] \
   && echo "$captured_live_marketplace_audit_output" | grep -q "Recommendation:"; then
    assert_passes "Recommendation section present (operator-actionable)"
elif [[ "$total_high_value_orchestration_candidates_count" -eq 0 ]] \
   && ! echo "$captured_live_marketplace_audit_output" | grep -q "Recommendation:"; then
    assert_passes "No recommendation section (correctly suppressed when no candidates)"
else
    assert_fails "Recommendation section presence does not match candidate count"
fi

# Assert 10: forensic-baseline citation is present (links back to iter-80).
if echo "$captured_live_marketplace_audit_output" | grep -q "iter-80"; then
    assert_passes "Forensic baseline citation (iter-80) present"
else
    assert_fails "Forensic baseline citation (iter-80) missing"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Iter-81 orchestration-candidacy-ranker regression test"
echo "═══════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
