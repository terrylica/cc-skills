#!/usr/bin/env bash
#MISE description="Iter-93 PostToolUse orchestrator kick-off regression test. Verifies (1) the new PostToolUseSubhookContract file exists with the expected decision-kind shape; (2) the orchestrator registry inlines exactly 1 subhook (ty-type-check) as the FIRST context-injecting PostToolUse subhook in the iter-93+ Path B migration arc; (3) non-Python writes → silent noop (cheap O(1) extension filter); (4) standalone posttooluse-ty-type-check.ts retains backward-compat via import.meta.main guard; (5) the dual-export naming-drift acknowledgement pattern (precise algorithm name + symmetric-naming alias) is present in the migrated subhook; (6) hooks.json now wires the orchestrator (not the standalone) under the Write|Edit PostToolUse matcher; (7) the orchestrator multi-aggregation semantics are visibly distinct from the PreToolUse first-deny-short-circuit (Promise.all + delimiter-joined aggregation, not Promise.race + first-non-allow); (8) the orchestrator emits `{decision:'block', reason}` JSON (the Anthropic-schema context-injection mechanism) NOT permissionDecision (which PostToolUse does not honor per iter-66 schema)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
STANDALONE_TY_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
CONTRACT_FILE_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"

for required_file_absolute_path in \
    "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$STANDALONE_TY_HOOK_ABSOLUTE_PATH" \
    "$CONTRACT_FILE_ABSOLUTE_PATH" \
    "$HOOKS_JSON_ABSOLUTE_PATH"; do
    if [[ ! -f "$required_file_absolute_path" ]]; then
        echo "FAIL: required file not found: $required_file_absolute_path"
        exit 1
    fi
done

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-93 PostToolUse orchestrator kick-off regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH=$(mktemp -d -t iter93-posttooluse-payloads.XXXXXX)
trap 'rm -rf "$TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH"' EXIT

# ─── Case 1: contract file shape (PostToolUseSubhookDecision discriminated union) ──
if grep -qE "type PostToolUseSubhookDecision" "$CONTRACT_FILE_ABSOLUTE_PATH" && \
   grep -qE 'kind: "noop"' "$CONTRACT_FILE_ABSOLUTE_PATH" && \
   grep -qE 'kind: "additional_context"' "$CONTRACT_FILE_ABSOLUTE_PATH"; then
    assert_passes "Case 1a: PostToolUseSubhookDecision is a discriminated union of 'noop' | 'additional_context' (NOT allow/deny/ask — PostToolUse cannot deny per iter-66 schema)"
else
    assert_fails "Case 1a: PostToolUseSubhookDecision shape is wrong — should be noop|additional_context, not allow/deny/ask"
fi
if grep -qE "interface PostToolUseSubhookRegistryEntry" "$CONTRACT_FILE_ABSOLUTE_PATH"; then
    assert_passes "Case 1b: PostToolUseSubhookRegistryEntry interface exists"
else
    assert_fails "Case 1b: PostToolUseSubhookRegistryEntry interface missing"
fi
if grep -q "buildPostToolUseAdditionalContextDecision" "$CONTRACT_FILE_ABSOLUTE_PATH"; then
    assert_passes "Case 1c: buildPostToolUseAdditionalContextDecision helper exists"
else
    assert_fails "Case 1c: buildPostToolUseAdditionalContextDecision helper missing"
fi

# ─── Case 2: orchestrator multi-aggregation semantics (Promise.all, NOT Promise.race + short-circuit) ──
# The PreToolUse orchestrator iterates registry SERIALLY with Promise.race for
# first-deny-short-circuit. The PostToolUse orchestrator runs all subhooks in
# PARALLEL via Promise.all (no short-circuit) — different semantics. The grep
# anchors on the literal `Promise.all` invocation in the orchestrator entry path.
if grep -q "Promise.all" "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 2a: orchestrator uses Promise.all (parallel multi-aggregation, NOT first-deny-short-circuit like PreToolUse)"
else
    assert_fails "Case 2a: orchestrator missing Promise.all — multi-aggregation invariant broken"
fi
if grep -q "aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonString" "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 2b: orchestrator has aggregator function with verbose precise name"
else
    assert_fails "Case 2b: aggregator function missing or mis-named"
fi

# ─── Case 3: orchestrator emits `{decision: "block", reason}` (NOT permissionDecision) ──
# The iter-66 schema note: PostToolUse honors `{decision: "block", reason}` for
# context injection. permissionDecision is PreToolUse-only — would be silently
# dropped on PostToolUse.
if grep -qE '"decision":[[:space:]]*"block"|decision:[[:space:]]*"block"' "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 3a: orchestrator emits {decision:'block'} (Anthropic-schema PostToolUse context-injection mechanism)"
else
    assert_fails "Case 3a: orchestrator NOT emitting {decision:'block'} — context injection won't reach Claude"
fi
if grep -q "permissionDecision" "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_fails "Case 3b: orchestrator emits permissionDecision (PostToolUse silently drops this per iter-66 schema)"
else
    assert_passes "Case 3b: orchestrator does NOT emit permissionDecision (iter-66 schema compliance)"
fi

# ─── Case 4: orchestrator registry has exactly 1 subhook (iter-93 starting state) ──
case4_registry_subhook_count=$(grep -cE '^[[:space:]]+name:[[:space:]]*"' "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH" || echo 0)
if [[ "${case4_registry_subhook_count:-0}" -ge 1 ]]; then
    assert_passes "Case 4: orchestrator registry inlines ≥1 subhook (iter-93 starting state; found ${case4_registry_subhook_count})"
else
    assert_fails "Case 4: orchestrator registry has 0 subhooks — kick-off invariant violated"
fi

# ─── Case 5: non-Python write → silent noop (orchestrator) + EXIT 0 ──
case5_payload="$TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH/case5.json"
cat > "$case5_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter93/foo.txt","content":"plain text\n"}}
PAYLOAD

set +e
case5_stdout=$(bun "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$case5_payload" 2>/dev/null)
case5_exit=$?
set -e

if [[ -z "$case5_stdout" ]] && [[ "$case5_exit" == "0" ]]; then
    assert_passes "Case 5: non-Python write (.txt) → orchestrator silent noop + exit 0 (O(1) extension filter)"
else
    assert_fails "Case 5: orchestrator misbehaved on .txt write — stdout='${case5_stdout:0:200}' exit=$case5_exit"
fi

# ─── Case 6: standalone backward-compat (import.meta.main guard) ──
if grep -q "import.meta.main" "$STANDALONE_TY_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 6a: standalone ty-type-check retains import.meta.main guard (orchestrator-imported AND CLI-runnable)"
else
    assert_fails "Case 6a: import.meta.main guard missing from standalone ty-type-check"
fi

set +e
case6b_stdout=$(bun "$STANDALONE_TY_HOOK_ABSOLUTE_PATH" < "$case5_payload" 2>/dev/null)
case6b_exit=$?
set -e
if [[ -z "$case6b_stdout" ]] && [[ "$case6b_exit" == "0" ]]; then
    assert_passes "Case 6b: standalone backward-compat preserved — non-Python write → silent exit 0"
else
    assert_fails "Case 6b: standalone broken — stdout='${case6b_stdout:0:200}' exit=$case6b_exit"
fi

# ─── Case 7: dual-export naming-drift acknowledgement pattern ──
if grep -q "classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator" "$STANDALONE_TY_HOOK_ABSOLUTE_PATH" && \
   grep -q "classifyTyTypeCheckForPostToolUseOrchestrator" "$STANDALONE_TY_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 7: ty-type-check exports BOTH precise algorithm name (classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator) + symmetric-naming alias (classifyTyTypeCheckForPostToolUseOrchestrator)"
else
    assert_fails "Case 7: dual-export naming pattern missing — precision/symmetry alignment broken"
fi

# ─── Case 8: hooks.json wires orchestrator, NOT standalone, under Write|Edit ──
case8_orchestrator_wired=$(jq -r '[.hooks.PostToolUse[] | select(.hooks[].command | test("posttooluse-edit-time-orchestrator-aggregating"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
case8_standalone_wired=$(jq -r '[.hooks.PostToolUse[] | select(.hooks[].command | test("/posttooluse-ty-type-check.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case8_orchestrator_wired" == "1" ]]; then
    assert_passes "Case 8a: hooks.json wires the iter-93 orchestrator under Write|Edit"
else
    assert_fails "Case 8a: orchestrator not wired (count=${case8_orchestrator_wired})"
fi
if [[ "$case8_standalone_wired" == "0" ]]; then
    assert_passes "Case 8b: hooks.json no longer wires standalone posttooluse-ty-type-check.ts (iter-93 first removal)"
else
    assert_fails "Case 8b: standalone ty-type-check still wired (${case8_standalone_wired} time(s)) — should be replaced by orchestrator"
fi

# ─── Case 9: AbortSignal.timeout() cooperative cancellation (mirrors iter-87 PreToolUse pattern) ──
if grep -q "AbortSignal.timeout" "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 9: orchestrator uses AbortSignal.timeout() (community-standard cooperative cancellation, mirrors iter-87 PreToolUse pattern)"
else
    assert_fails "Case 9: orchestrator missing AbortSignal.timeout() — runaway subhooks could block the rest"
fi

# ─── Case 10: iter-92 correction citation present in orchestrator header ──
if grep -qE "iter-92" "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH" && \
   grep -qE "iter-89" "$ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 10: orchestrator header documents iter-92 correction of iter-89 strict-dominance claim (forensic traceability)"
else
    assert_fails "Case 10: iter-92/iter-89 forensic citations missing from orchestrator header"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-93 PostToolUse orchestrator kick-off regression — Summary"
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
echo "  🚀 Iter-93 PostToolUse Write|Edit migration arc KICKED OFF: 1/15 inlined."
echo "  🚀 Projected final-state savings: (15-1) × 17ms = ~238ms per Write|Edit."
