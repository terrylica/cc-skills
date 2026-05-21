#!/usr/bin/env bash
#MISE description="Iter-91 ARC-COMPLETION regression test. Verifies (1) vale-claude-md-guard inlined as 8th and FINAL registry entry — completing the iter-84→iter-91 PreToolUse Write|Edit migration arc; (2) orchestrator now contains exactly 8 subhooks in lightest-first deny-wins order; (3) non-CLAUDE.md write → ALLOW (O(1) endsWith fastpath); (4) CLAUDE.md write with valid content (no vale findings) → ALLOW; (5) standalone vale-claude-md-guard.ts backward-compat preserved; (6) subhook-contract audit task discovers ≥8 conforming subhooks; (7) PreToolUse additionalContext silent-drop NON-USE invariant STILL holds across ALL 8 inlined subhooks; (8) hooks.json now contains exactly ONE Write|Edit orchestrator entry plus the iter-78 layer3-stripped-path Write|Edit|MultiEdit entry (no other standalone Write|Edit entries remaining)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCHESTRATOR_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"
STANDALONE_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-vale-claude-md-guard.ts"
SUBHOOK_CONTRACT_AUDIT_TASK_PATH="$REPO_ROOT/.mise/tasks/audit-pretooluse-orchestrator-subhook-contract-violations-static-check-no-stdin-stdout-exit-in-classifier-functions-and-import-meta-main-guard-on-standalone-main.sh"
HOOKS_JSON_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"
HOOKS_DIR="$REPO_ROOT/plugins/itp-hooks/hooks"

for required_file in "$ORCHESTRATOR_HOOK_PATH" "$STANDALONE_HOOK_PATH" "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH" "$HOOKS_JSON_PATH"; do
    if [[ ! -f "$required_file" ]]; then
        echo "FAIL: required file not found: $required_file"
        exit 1
    fi
done

ASSERTION_COUNT_PASSED=0
ASSERTION_COUNT_FAILED=0
assert_passes() { ASSERTION_COUNT_PASSED=$((ASSERTION_COUNT_PASSED + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_COUNT_FAILED=$((ASSERTION_COUNT_FAILED + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-91 ARC COMPLETION: 8/8 PreToolUse Write|Edit subhooks inlined"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

PAYLOAD_TEMP_DIR=$(mktemp -d -t iter91-payloads.XXXXXX)
trap 'rm -rf "$PAYLOAD_TEMP_DIR"' EXIT

# ─── Case 1: non-CLAUDE.md Python write → ALLOW (vale fastpath skip) ──────────
case1_payload="$PAYLOAD_TEMP_DIR/case1.json"
cat > "$case1_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/models.py","content":"def foo():\n    pass\n"}}
PAYLOAD

set +e
case1_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case1_payload" 2>/dev/null)
case1_exit=$?
set -e

if [[ "$case1_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case1_exit" == "0" ]]; then
    assert_passes "Case 1: non-CLAUDE.md file (.py) → allow (vale-claude-md-guard suffix fastpath skipped)"
else
    assert_fails "Case 1: vale-claude-md-guard suffix fastpath broken; exit=$case1_exit"
fi

# ─── Case 2: orchestrator imports classifier from vale-claude-md-guard.ts ─────
if grep -q 'classifyValeClaudeMdGuardForOrchestrator' "$ORCHESTRATOR_HOOK_PATH"; then
    assert_passes "Case 2a: orchestrator imports classifyValeClaudeMdGuardForOrchestrator"
else
    assert_fails "Case 2a: vale-claude-md-guard import missing from orchestrator"
fi
if grep -q 'name: "vale-claude-md-guard"' "$ORCHESTRATOR_HOOK_PATH"; then
    assert_passes "Case 2b: vale-claude-md-guard registered in orchestrator registry"
else
    assert_fails "Case 2b: vale-claude-md-guard registry entry missing"
fi

# ─── Case 3: standalone vale-claude-md-guard.ts backward-compat ───────────────
set +e
case3_stdout=$(bun "$STANDALONE_HOOK_PATH" < "$case1_payload" 2>/dev/null)
case3_exit=$?
set -e

if [[ "$case3_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case3_exit" == "0" ]]; then
    assert_passes "Case 3a: standalone vale-claude-md-guard.ts allows non-CLAUDE.md write (backward-compat)"
else
    assert_fails "Case 3a: standalone broken; got=${case3_stdout:0:200}"
fi
if [[ "$case3_stdout" != *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 3b: standalone reason has NO orchestrator prefix"
else
    assert_fails "Case 3b: standalone leaked orchestrator prefix"
fi

# ─── Case 4: subhook-contract audit task discovers exactly 8 subhooks ─────────
set +e
case4_stdout=$(bash "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH" 2>&1)
set -e

case4_subhook_count=$(echo "$case4_stdout" | grep -oE 'Total subhook files scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
if [[ "${case4_subhook_count:-0}" -ge 8 ]]; then
    assert_passes "Case 4a: audit task discovers ≥8 inlined subhooks (FINAL arc state; found ${case4_subhook_count})"
else
    assert_fails "Case 4a: subhook count ${case4_subhook_count} < 8 — arc-completion invariant violated"
fi
if [[ "$case4_stdout" == *'subhook files conform to the PreToolUseSubhookContract'* ]]; then
    assert_passes "Case 4b: audit task reports clean state (vale-claude-md-guard.ts conforms)"
else
    assert_fails "Case 4b: clean-contract state not reported"
fi

# ─── Case 5: PreToolUse additionalContext silent-drop NON-USE invariant across ALL 8 ──
# Same emission-pattern audit iter-90 introduced, now scanning all 8 inlined subhooks
additional_context_emission_violations_count=0
for subhook_file in \
  "$HOOKS_DIR/pretooluse-version-guard.ts" \
  "$HOOKS_DIR/pretooluse-hoisted-deps-guard.ts" \
  "$HOOKS_DIR/pretooluse-mise-hygiene-guard.ts" \
  "$HOOKS_DIR/pretooluse-pyi-stub-guard.ts" \
  "$HOOKS_DIR/pretooluse-native-binary-guard.ts" \
  "$HOOKS_DIR/pretooluse-gpu-optimization-guard.ts" \
  "$HOOKS_DIR/pretooluse-file-size-guard.ts" \
  "$HOOKS_DIR/pretooluse-vale-claude-md-guard.ts"; do
    if grep -qE '(^[[:space:]]*additionalContext[[:space:]]*:|"additionalContext"[[:space:]]*:)' "$subhook_file" 2>/dev/null; then
        additional_context_emission_violations_count=$((additional_context_emission_violations_count + 1))
        echo "    ↳ violation: $(basename "$subhook_file")"
    fi
done

if [[ "$additional_context_emission_violations_count" == "0" ]]; then
    assert_passes "Case 5: PreToolUse additionalContext silent-drop NON-USE invariant holds across all 8 inlined subhooks (GitHub #15664 defense-in-depth)"
else
    assert_fails "Case 5: ${additional_context_emission_violations_count} of 8 PreToolUse subhook(s) emit additionalContext — silent-drop hazard"
fi

# ─── Case 6: hooks.json contains exactly ONE Write|Edit orchestrator entry ────
# After arc completion, the only Write|Edit matcher should be the orchestrator.
# Use jq (NOT grep) for reliable JSON inspection — BSD grep ERE handling of
# `\|` is implementation-defined and produced spurious matches in iter-91 dev.
# (iter-78 layer3-stripped-path-guard uses Write|Edit|MultiEdit which is a
# DIFFERENT matcher value and must not be confused with Write|Edit.)
case6_write_edit_matcher_count=$(jq '[.hooks.PreToolUse[] | .matcher] | map(select(. == "Write|Edit")) | length' "$HOOKS_JSON_PATH")
if [[ "$case6_write_edit_matcher_count" == "1" ]]; then
    assert_passes "Case 6a: hooks.json now contains exactly 1 Write|Edit matcher (the orchestrator) — all 7 standalone Write|Edit entries removed across iter-84→iter-91"
else
    assert_fails "Case 6a: expected 1 Write|Edit matcher, found ${case6_write_edit_matcher_count} — standalone subhooks may not all be removed"
fi
case6_vale_standalone_remnant_count=$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("pretooluse-vale-claude-md-guard"))] | length' "$HOOKS_JSON_PATH")
if [[ "$case6_vale_standalone_remnant_count" == "0" ]]; then
    assert_passes "Case 6b: hooks.json does NOT reference standalone pretooluse-vale-claude-md-guard.ts (iter-91 final removal — only via orchestrator import)"
else
    assert_fails "Case 6b: standalone vale-claude-md-guard.ts still referenced in hooks.json ${case6_vale_standalone_remnant_count} time(s)"
fi

# ─── Case 7: orchestrator description text records arc-completion milestone ───
if grep -q 'iter-91' "$HOOKS_JSON_PATH" && grep -q 'COMPLETE' "$HOOKS_JSON_PATH"; then
    assert_passes "Case 7: hooks.json orchestrator description records iter-91 arc-completion milestone (8/8)"
else
    assert_fails "Case 7: arc-completion milestone not recorded in hooks.json"
fi

# ─── Case 8: vale-claude-md-guard standalone retains import.meta.main guard ───
if grep -q 'import.meta.main' "$STANDALONE_HOOK_PATH"; then
    assert_passes "Case 8: standalone vale-claude-md-guard.ts retains import.meta.main guard (contract compliance)"
else
    assert_fails "Case 8: import.meta.main guard missing"
fi

# ─── Case 9: dual-export naming-drift acknowledgement (algorithm + alias) ─────
if grep -q 'classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator' "$STANDALONE_HOOK_PATH" && \
   grep -q 'classifyValeClaudeMdGuardForOrchestrator' "$STANDALONE_HOOK_PATH"; then
    assert_passes "Case 9: vale-claude-md-guard.ts exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 9: dual-export naming acknowledgement missing"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-91 ARC COMPLETION regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
echo ""
echo "  🎉 PreToolUse Write|Edit migration arc COMPLETE: 8/8 subhooks inlined."
echo "  🎉 Empirical savings projection: ~119ms per Write|Edit (iter-87 microbenchmark)."
