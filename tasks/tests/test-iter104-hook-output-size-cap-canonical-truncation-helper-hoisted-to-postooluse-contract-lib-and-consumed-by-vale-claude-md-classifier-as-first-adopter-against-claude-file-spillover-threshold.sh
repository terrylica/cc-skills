#!/usr/bin/env bash
#MISE description="Iter-104 regression test for the hook-output-size-cap canonical truncation helper. Verifies MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER constant + truncateHookOutputToStayBelowClaudeFileSpilloverThreshold helper exist in PostToolUse contract lib, helper returns input verbatim under threshold + truncates with explicit marker over threshold, posttooluse-vale-claude-md.ts (first adopter) consumes the helper for its unbounded vale-findings reason emission, no output ever exceeds 10000 chars when emitted via the helper, fast-path return-verbatim semantics preserved for typical small reasons."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
# Iter-104-original location (now a re-export bridge per iter-106). Kept as a
# variable because Case 1 still verifies the symbol's presence here via the
# backward-compat re-export — that re-export is the contract by which the
# iter-104 API surface remains stable for external consumers.
POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
# Iter-106 canonical home for the iter-104 helper + constant + marker suffix.
# Iter-106 relocated the literal `export const` / `export function` definitions
# to a dedicated cross-Pre/PostToolUse shared lib to eliminate the iter-105
# cross-lib import awkwardness. Cases that inspect literal source text (Cases
# 2, 3, 8) read FROM this shared-lib location.
ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts"
VALE_CLAUDE_MD_CLASSIFIER_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts"

for required_file in "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH" "$VALE_CLAUDE_MD_CLASSIFIER_ABSOLUTE_PATH"; do
    if [[ ! -f "$required_file" ]]; then
        echo "FAIL: required file not found: $required_file"
        exit 1
    fi
done

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-104 hook-output size-cap truncation helper regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: canonical constant + helper exist in contract lib ───────────────
if grep -q "MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -q "truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 1: canonical constant + truncation helper exist in PostToolUse contract lib"
else
    assert_fails "Case 1: canonical constant or truncation helper missing from contract lib"
fi

# ─── Case 2: helper threshold constant is 9000 (1000-char margin below 10K) ──
# Iter-106 update: the literal `export const ...` definition moved to the
# iter-106 shared lib; the PostToolUse contract lib only re-exports. Inspect
# the canonical home for the literal value.
case2_threshold_value=$(grep -E "^export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH" | grep -oE '[0-9]+' | head -1 || echo "?")
if [[ "$case2_threshold_value" == "9000" ]]; then
    assert_passes "Case 2: threshold constant = 9000 chars (1000-char safety margin below Anthropic-documented 10000 spillover threshold) — verified at iter-106 shared-lib canonical home"
else
    assert_fails "Case 2: threshold constant = $case2_threshold_value, expected 9000"
fi

# ─── Case 3: marker suffix mentions 10,000 + spillover + ctrl-R + Claude awareness ──
# The marker text MUST be Claude-actionable: explain WHY truncation happened
# (10K threshold), WHERE the full content is (operator transcript via Ctrl-R),
# and WHAT Claude should do (act on visible findings, assume more may exist).
# Iter-106 update: the literal marker constant moved to the iter-106 shared lib.
case3_marker_block=$(awk '/^export const HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS/,/;$/' "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH" | head -5)
case3_has_threshold_cite=0
case3_has_ctrl_r_cite=0
case3_has_claude_action=0
[[ "$case3_marker_block" == *"10,000"* ]] && case3_has_threshold_cite=1
[[ "$case3_marker_block" == *"Ctrl-R"* ]] && case3_has_ctrl_r_cite=1
[[ "$case3_marker_block" == *"Claude:"* ]] && case3_has_claude_action=1
if [[ "$case3_has_threshold_cite" == "1" ]] && [[ "$case3_has_ctrl_r_cite" == "1" ]] && [[ "$case3_has_claude_action" == "1" ]]; then
    assert_passes "Case 3: marker suffix is Claude-actionable (cites 10K threshold + Ctrl-R operator transcript + Claude:-prefixed instruction)"
else
    assert_fails "Case 3: marker suffix missing actionability fields (threshold=$case3_has_threshold_cite, ctrl-r=$case3_has_ctrl_r_cite, claude-action=$case3_has_claude_action)"
fi

# ─── Case 4: vale-claude-md.ts (first adopter) imports + uses the helper ────
if grep -q "truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$VALE_CLAUDE_MD_CLASSIFIER_ABSOLUTE_PATH"; then
    case4_usage_count=$(grep -c "truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$VALE_CLAUDE_MD_CLASSIFIER_ABSOLUTE_PATH")
    if [[ "$case4_usage_count" -ge "2" ]]; then
        assert_passes "Case 4: vale-claude-md.ts imports + applies truncation helper ($case4_usage_count occurrences = import + emission-site usage)"
    else
        assert_fails "Case 4: vale-claude-md.ts has only $case4_usage_count occurrence(s) of helper — expected ≥2 (import + usage)"
    fi
else
    assert_fails "Case 4: vale-claude-md.ts does NOT import the truncation helper"
fi

# ─── Case 5: bun runtime test — helper returns input verbatim under threshold ──
# Verify the fast-path: small inputs (< 9000 chars) are returned unchanged with
# no marker appended. This is the dominant case (most hook reasons are short).
TEMP_E2E_DIR=$(mktemp -d -t iter104-e2e.XXXXXX)
trap 'rm -rf "$TEMP_E2E_DIR"' EXIT
TEMP_TS_FAST_PATH_TEST_FILE="$TEMP_E2E_DIR/test-fast-path.ts"
cat > "$TEMP_TS_FAST_PATH_TEST_FILE" <<'TS'
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "/Users/terryli/eon/cc-skills/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

const smallReason = "[VALE] Found 1 error: Line 5: [ERROR] terminology mismatch";
const result = truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(smallReason);
if (result === smallReason) {
  console.log("FAST-PATH-OK");
} else {
  console.log("FAST-PATH-BROKEN: result-len=" + result.length + " input-len=" + smallReason.length);
}
TS
set +e
case5_fast_path_output=$(bun "$TEMP_TS_FAST_PATH_TEST_FILE" 2>&1)
case5_fast_path_exit=$?
set -e
if [[ "$case5_fast_path_exit" == "0" ]] && [[ "$case5_fast_path_output" == *"FAST-PATH-OK"* ]]; then
    assert_passes "Case 5: fast-path return-verbatim semantics preserved (small reasons returned unchanged with NO marker appended)"
else
    assert_fails "Case 5: fast-path broken (exit=$case5_fast_path_exit, output=$case5_fast_path_output)"
fi

# ─── Case 6: bun runtime test — helper truncates over-threshold input + appends marker ──
TEMP_TS_TRUNCATION_TEST_FILE="$TEMP_E2E_DIR/test-truncation.ts"
cat > "$TEMP_TS_TRUNCATION_TEST_FILE" <<'TS'
import {
  MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER,
  truncateHookOutputToStayBelowClaudeFileSpilloverThreshold,
} from "/Users/terryli/eon/cc-skills/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// Synthesize an over-threshold input (12,000 chars of 'A' to definitively
// exceed the 9000 safe threshold; would silently file-spill without truncation).
const overThresholdInput = "A".repeat(12000);
const result = truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(overThresholdInput);

// Result MUST be at or below the safe threshold (no spillover triggered)
const isBelowThreshold = result.length <= MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER;
// Marker MUST be present so Claude knows truncation occurred
const hasMarker = result.includes("[... output truncated to stay below Claude's 10,000-character");

if (isBelowThreshold && hasMarker) {
  console.log("TRUNCATION-OK result-len=" + result.length + " threshold=" + MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER);
} else {
  console.log("TRUNCATION-BROKEN result-len=" + result.length + " below-threshold=" + isBelowThreshold + " has-marker=" + hasMarker);
}
TS
set +e
case6_truncation_output=$(bun "$TEMP_TS_TRUNCATION_TEST_FILE" 2>&1)
case6_truncation_exit=$?
set -e
if [[ "$case6_truncation_exit" == "0" ]] && [[ "$case6_truncation_output" == *"TRUNCATION-OK"* ]]; then
    assert_passes "Case 6: over-threshold input truncated to ≤9000 chars + Claude-actionable marker appended (no silent file-spillover)"
else
    assert_fails "Case 6: truncation broken (exit=$case6_truncation_exit, output=$case6_truncation_output)"
fi

# ─── Case 7: e2e — vale-claude-md classifier produces bounded output ────────
# The static-code invariant: classifier's unbounded vale-findings reason
# string is wrapped in the canonical truncation helper BEFORE being passed
# to buildPostToolUseAdditionalContextDecision. Static-source verification
# is sufficient (dynamic invocation would require vale to actually run on
# a synthesized CLAUDE.md, which is independent of this invariant).
case7_emission_wrapped_in_helper=0
# Look for the canonical pattern: `reason` is assigned from the truncation
# helper, then passed to buildPostToolUseAdditionalContextDecision. Use a
# 10-line look-back window to accommodate intervening multiline-comments
# documenting the iter-104 rationale.
if grep -B10 "buildPostToolUseAdditionalContextDecision(reason)" "$VALE_CLAUDE_MD_CLASSIFIER_ABSOLUTE_PATH" 2>/dev/null \
       | grep -q "truncateHookOutputToStayBelowClaudeFileSpilloverThreshold"; then
    case7_emission_wrapped_in_helper=1
fi
if [[ "$case7_emission_wrapped_in_helper" == "1" ]]; then
    assert_passes "Case 7: vale-claude-md.ts wraps its unbounded reason in truncation helper BEFORE passing to buildPostToolUseAdditionalContextDecision (static-code invariant)"
else
    assert_fails "Case 7: vale-claude-md.ts emission site does NOT show the canonical wrap-then-emit pattern"
fi

# ─── Case 8: contract lib documents iter-104 design rationale ───────────────
# Future maintainers reading the lib MUST see (a) the 10K spillover finding's
# source citation, (b) the 9000 safety-margin rationale, (c) the iter-105
# follow-up marketplace-audit scope.
case8_has_anthropic_cite=0
case8_has_iter105_followup=0
case8_has_worst_offender_list=0
# Iter-106 update: design rationale comments moved to the iter-106 shared-lib
# canonical home along with the literal definitions. Inspect there.
grep -q "code.claude.com/docs/en/hooks" "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH" && case8_has_anthropic_cite=1
grep -qi "iter-105" "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH" && case8_has_iter105_followup=1
# Iter-106: shared lib documents the marketplace cohort via "Marketplace cohort
# hooks" header (replaces iter-104's "Worst-offender hooks" framing — same
# semantic content, more precise naming now that iter-105 generalized the cohort).
{ grep -q "Worst-offender" "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH" || \
  grep -q "Marketplace cohort hooks" "$ITER106_SHARED_TRUNCATION_LIB_ABSOLUTE_PATH"; } && case8_has_worst_offender_list=1
if [[ "$case8_has_anthropic_cite" == "1" ]] && [[ "$case8_has_iter105_followup" == "1" ]] && [[ "$case8_has_worst_offender_list" == "1" ]]; then
    assert_passes "Case 8: contract lib documents Anthropic-docs citation + iter-105 follow-up + worst-offender list"
else
    assert_fails "Case 8: contract lib missing iter-104 design rationale (anthropic-cite=$case8_has_anthropic_cite, iter105=$case8_has_iter105_followup, worst-offenders=$case8_has_worst_offender_list)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-104 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-104 establishes hook-output-size-cap canonical helper against the"
echo "     Claude-visible 10,000-character file-spillover threshold (web research"
echo "     finding from 2026 Anthropic Claude Code hook docs). First adopter:"
echo "     posttooluse-vale-claude-md.ts (highest finding-count classifier — CLAUDE.md"
echo "     edits can trigger 50-200+ vale findings → silent file-spillover risk)."
echo "  🚀 Iter-105+ scope: marketplace audit + apply to remaining 6 unbounded-output"
echo "     classifiers (ty, tsgo, oxlint, biome, ssot-principles, pretooluse-vale)."
echo "     Mirrors iter-100 → iter-101 single-hook-fix-then-marketplace-scale pattern."
