#!/usr/bin/env bash
#MISE description="Iter-100 regression test: orchestrator matcher broadened Write|Edit to Write|Edit|MultiEdit per 2026 Anthropic + community best-practice web research. Verifies hooks.json matcher includes MultiEdit, canonical contract helper exists + consumed by classifiers, end-to-end MultiEdit payload fires expected subhooks (memory-efficiency + ssot-principles on .py + .ts edits), iter-99 audit scope refined to exclude lib helpers, marketplace-wide invariants preserved."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
CONTRACT_LIB_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"
ITER99_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-raw-stdout-emission-in-posttooluse-typescript-hooks-because-anthropic-schema-routes-non-json-stdout-to-operator-transcript-only-and-silently-drops-it-from-claude-context.sh"

for required_file in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$CONTRACT_LIB_ABSOLUTE_PATH" \
    "$HOOKS_JSON_ABSOLUTE_PATH" \
    "$ITER99_AUDIT_TASK_ABSOLUTE_PATH"; do
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
echo "  Iter-100 MultiEdit-matcher-broadening regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: hooks.json orchestrator matcher includes MultiEdit ──────────────
case1_orchestrator_matcher=$(jq -r '.hooks.PostToolUse[] | select(.hooks[].command | test("posttooluse-edit-time-orchestrator-aggregating")) | .matcher' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case1_orchestrator_matcher" == *"MultiEdit"* ]]; then
    assert_passes "Case 1: hooks.json orchestrator matcher includes MultiEdit (current matcher: '$case1_orchestrator_matcher')"
else
    assert_fails "Case 1: hooks.json orchestrator matcher does NOT include MultiEdit (current: '$case1_orchestrator_matcher') — iter-100 coverage gap reopened"
fi

# ─── Case 2: canonical contract helper exists in lib ─────────────────────────
if grep -q "FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS" "$CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -q "isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook" "$CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 2: canonical contract helper + allowlist constant exist in lib (iter-100 centralization)"
else
    assert_fails "Case 2: canonical contract helper or allowlist constant missing from lib"
fi

# ─── Case 3: allowlist constant contains all three tool names ────────────────
case3_allowlist_block=$(awk '/FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS/,/\);/' "$CONTRACT_LIB_ABSOLUTE_PATH" | head -10)
case3_has_write=0
case3_has_edit=0
case3_has_multiedit=0
[[ "$case3_allowlist_block" == *'"Write"'* ]] && case3_has_write=1
[[ "$case3_allowlist_block" == *'"Edit"'* ]] && case3_has_edit=1
[[ "$case3_allowlist_block" == *'"MultiEdit"'* ]] && case3_has_multiedit=1
if [[ "$case3_has_write" == "1" ]] && [[ "$case3_has_edit" == "1" ]] && [[ "$case3_has_multiedit" == "1" ]]; then
    assert_passes "Case 3: allowlist constant contains Write + Edit + MultiEdit"
else
    assert_fails "Case 3: allowlist constant missing entries (write=$case3_has_write edit=$case3_has_edit multiedit=$case3_has_multiedit)"
fi

# ─── Case 4: classifiers with explicit tool_name guards use canonical helper ──
# Pre-iter-100 these 3 classifiers had hand-rolled Write||Edit equality checks
# that silently rejected MultiEdit. Post-iter-100 they should import + call
# the canonical helper.
declare -a CLASSIFIERS_REQUIRING_CANONICAL_HELPER=(
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ssot-principles.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-memory-efficiency-reminder.ts"
)
case4_canonical_helper_consumers_count=0
for classifier in "${CLASSIFIERS_REQUIRING_CANONICAL_HELPER[@]}"; do
    if grep -q "isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook" "$classifier"; then
        case4_canonical_helper_consumers_count=$((case4_canonical_helper_consumers_count + 1))
    fi
done
if [[ "$case4_canonical_helper_consumers_count" == "3" ]]; then
    assert_passes "Case 4: all 3 classifiers with tool_name guards (vale, ssot, memory-eff) consume canonical helper"
else
    assert_fails "Case 4: only $case4_canonical_helper_consumers_count/3 classifiers use the canonical helper — iter-100 migration incomplete"
fi

# ─── Case 5: legacy `toolName !== "Write" && toolName !== "Edit"` guards removed ──
# Pre-iter-100 the silent-reject-MultiEdit pattern. Post-iter-100 these
# emission-pattern checks must find 0 occurrences (escape: prose mentions
# in comments/JSDoc are skipped).
legacy_guard_emissions=0
for classifier in "${CLASSIFIERS_REQUIRING_CANONICAL_HELPER[@]}"; do
    matches=$(grep -nE 'toolName.*!==.*"Write".*&&.*toolName.*!==.*"Edit"' "$classifier" 2>/dev/null \
        | grep -vE ':[[:space:]]*\*' \
        | grep -vE ':[[:space:]]*//' \
        || true)
    if [[ -n "$matches" ]]; then
        legacy_guard_emissions=$((legacy_guard_emissions + 1))
    fi
done
if [[ "$legacy_guard_emissions" == "0" ]]; then
    assert_passes "Case 5: legacy Write||Edit-only equality guards removed from all 3 classifiers"
else
    assert_fails "Case 5: $legacy_guard_emissions classifier(s) still have legacy Write||Edit-only guards — would silently reject MultiEdit"
fi

# ─── Case 6: end-to-end MultiEdit payload on .py fires expected subhooks ────
TEMP_E2E_DIR=$(mktemp -d -t iter100-e2e.XXXXXX)
trap 'rm -rf "$TEMP_E2E_DIR"' EXIT
TEMP_PY_FILE="$TEMP_E2E_DIR/sample.py"
cat > "$TEMP_PY_FILE" <<'PY'
import os
def get_mode():
    return os.environ.get("MODE", "default")
PY
TEMP_PAYLOAD_FILE="$TEMP_E2E_DIR/payload.json"
UNIQUE_SESSION_ID_FOR_E2E="iter100-e2e-$(date +%s%N)"
cat > "$TEMP_PAYLOAD_FILE" <<JSON
{"tool_name":"MultiEdit","session_id":"$UNIQUE_SESSION_ID_FOR_E2E","tool_input":{"file_path":"$TEMP_PY_FILE","edits":[{"old_string":"return os.environ.get(\"MODE\", \"default\")","new_string":"return os.environ.get(\"MODE\", \"default\")  # post-MultiEdit"}]}}
JSON
set +e
case6_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$TEMP_PAYLOAD_FILE" 2>/dev/null)
case6_exit=$?
set -e
case6_has_memeff=0
case6_has_ssot=0
case6_has_provenance_prefix=0
case6_has_decision_block=0
[[ "$case6_stdout" == *'MEMORY-EFFICIENCY'* ]] && case6_has_memeff=1
[[ "$case6_stdout" == *'SSoT-PRINCIPLES'* ]] && case6_has_ssot=1
[[ "$case6_stdout" == *'[orchestrator-subhook: memory-efficiency-reminder]'* ]] && case6_has_provenance_prefix=1
[[ "$case6_stdout" == *'"decision":"block"'* ]] && case6_has_decision_block=1
if [[ "$case6_exit" == "0" ]] && \
   [[ "$case6_has_memeff" == "1" ]] && \
   [[ "$case6_has_ssot" == "1" ]] && \
   [[ "$case6_has_provenance_prefix" == "1" ]] && \
   [[ "$case6_has_decision_block" == "1" ]]; then
    assert_passes "Case 6: e2e MultiEdit on .py fires both memory-efficiency + ssot-principles with conditional [orchestrator-subhook:<name>] provenance prefix"
else
    assert_fails "Case 6: MultiEdit fan-out broken (exit=$case6_exit, memeff=$case6_has_memeff, ssot=$case6_has_ssot, prefix=$case6_has_provenance_prefix, decision=$case6_has_decision_block)"
fi

# ─── Case 7: pre-iter-100 silent-allow on MultiEdit is now closed ────────────
# Verify the orchestrator EMITS something on MultiEdit (pre-iter-100 baseline
# was completely silent stdout). Reuse the same payload from Case 6 with a
# fresh session-id so the once-per-session gates can re-fire.
UNIQUE_SESSION_ID_FOR_REGRESSION="iter100-regression-$(date +%s%N)"
TEMP_PAYLOAD_REGRESSION_FILE="$TEMP_E2E_DIR/payload-regression.json"
cat > "$TEMP_PAYLOAD_REGRESSION_FILE" <<JSON
{"tool_name":"MultiEdit","session_id":"$UNIQUE_SESSION_ID_FOR_REGRESSION","tool_input":{"file_path":"$TEMP_PY_FILE","edits":[{"old_string":"return os.environ.get(\"MODE\", \"default\")","new_string":"return os.environ.get(\"MODE\", \"default\")  # 2nd MultiEdit"}]}}
JSON
set +e
case7_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$TEMP_PAYLOAD_REGRESSION_FILE" 2>/dev/null)
case7_exit=$?
set -e
if [[ "$case7_exit" == "0" ]] && [[ -n "$case7_stdout" ]]; then
    assert_passes "Case 7: pre-iter-100 silent-allow regression — orchestrator now emits non-empty stdout on MultiEdit (was empty pre-iter-100)"
else
    assert_fails "Case 7: orchestrator still silently allowing MultiEdit (exit=$case7_exit, stdout-len=${#case7_stdout})"
fi

# ─── Case 8: iter-99 audit scope refined — lib/ excluded ─────────────────────
# Source-level check (not dynamic-invocation) because the iter-99 test injects
# a temporary bad-pattern fixture into the marketplace and runs concurrently
# via xargs -P; dynamically invoking the iter-99 audit here would race against
# that fixture and produce false-negative AUDIT-FAILED output. Verifying the
# audit's source for the lib-exclusion pattern is race-free + correctness-
# preserving (the audit's behavior is determined by its source, not its
# concurrent invocation state).
if grep -qE "not -path[[:space:]]+['\"]?\*/hooks/lib/\*['\"]?" "$ITER99_AUDIT_TASK_ABSOLUTE_PATH"; then
    assert_passes "Case 8: iter-99 audit task source excludes */hooks/lib/* path (iter-100 scope refinement applied — race-free static verification)"
else
    assert_fails "Case 8: iter-99 audit task source does NOT exclude */hooks/lib/* — iter-100 scope refinement missing"
fi

# ─── Case 9: backward compatibility — Write payloads still fire correctly ────
# Iter-100 must NOT break the existing Write|Edit behavior.
TEMP_BC_DIR=$(mktemp -d -t iter100-bc.XXXXXX)
TEMP_BC_PY_FILE="$TEMP_BC_DIR/sample.py"
cat > "$TEMP_BC_PY_FILE" <<'PY'
import os
def x():
    return os.environ.get("X", "1")
PY
TEMP_BC_PAYLOAD_FILE="$TEMP_BC_DIR/payload.json"
UNIQUE_SESSION_ID_BC="iter100-bc-$(date +%s%N)"
cat > "$TEMP_BC_PAYLOAD_FILE" <<JSON
{"tool_name":"Write","session_id":"$UNIQUE_SESSION_ID_BC","tool_input":{"file_path":"$TEMP_BC_PY_FILE","content":"import os\ndef x():\n    return os.environ.get('X', '1')\n"}}
JSON
set +e
case9_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$TEMP_BC_PAYLOAD_FILE" 2>/dev/null)
case9_exit=$?
set -e
rm -rf "$TEMP_BC_DIR"
if [[ "$case9_exit" == "0" ]] && [[ "$case9_stdout" == *'"decision":"block"'* ]]; then
    assert_passes "Case 9: backward-compat — Write payloads still fire correctly post-iter-100 (no regression in legacy matcher path)"
else
    assert_fails "Case 9: Write payload BROKEN post-iter-100 (exit=$case9_exit, stdout-head='${case9_stdout:0:200}')"
fi

# ─── Case 10: orchestrator description records iter-100 milestone ───────────
case10_inlined_count=$(jq -r '.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-edit-time-orchestrator-aggregating")) | .description' "$HOOKS_JSON_ABSOLUTE_PATH" 2>/dev/null | grep -oE 'iter-100' | head -1 || echo "")
if [[ -n "$case10_inlined_count" ]]; then
    assert_passes "Case 10: hooks.json orchestrator description records iter-100 milestone (MultiEdit-matcher-broadening)"
else
    assert_fails "Case 10: orchestrator description does not record iter-100 milestone"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-100 regression — Summary"
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
echo "  🚀 Iter-100 MILESTONE — orchestrator matcher broadened Write|Edit → Write|Edit|MultiEdit per 2026 best-practice web research."
echo "  🚀 Iter-100 canonical contract helper isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook centralizes the allow-set (3 classifier migrations)."
echo "  🚀 Iter-100 iter-99 audit scope refined — lib/ helpers excluded (precision improvement, no behavior change)."
echo "  🚀 Iter-100 e2e MultiEdit fan-out verified — coverage gap closed: pre-iter-100 silent-allow → post-iter-100 fires expected subhooks with conditional provenance prefix."
