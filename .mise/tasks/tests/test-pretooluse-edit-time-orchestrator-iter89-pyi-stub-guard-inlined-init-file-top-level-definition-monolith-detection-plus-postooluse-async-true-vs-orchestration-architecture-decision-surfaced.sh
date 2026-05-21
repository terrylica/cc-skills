#!/usr/bin/env bash
#MISE description="Iter-89 regression test extending iter-88 orchestrator coverage. Verifies (1) pyi-stub-guard inlined as 6th registry entry — classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator + classifyPyiStubGuardForOrchestrator alias both denyable, (2) __init__.py with top-level class def → DENY, (3) __init__.pyi with top-level def → DENY (stricter PEP 561 rules), (4) non-init Python file → ALLOW (O(1) suffix fastpath skip), (5) escape-hatch # INIT-MONOLITH-OK honored → ALLOW, (6) re-export-dominated Write (≥70% imports) → ALLOW, (7) standalone backward-compat preserved, (8) subhook-contract audit task discovers ≥6 conforming subhooks, (9) iter-89 adversarial finding surfaced: PostToolUse Write|Edit consolidation (task #96) MUST also evaluate Anthropic's Jan-2026 async:true non-blocking primitive as an architecture-decision alternative before committing to a full orchestrator (web research finding: async:true provides zero-blocking PostToolUse runtime cost without per-hook contract-design effort)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCHESTRATOR_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"
STANDALONE_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-pyi-stub-guard.ts"
SUBHOOK_CONTRACT_AUDIT_TASK_PATH="$REPO_ROOT/.mise/tasks/audit-pretooluse-orchestrator-subhook-contract-violations-static-check-no-stdin-stdout-exit-in-classifier-functions-and-import-meta-main-guard-on-standalone-main.sh"

for required_file in "$ORCHESTRATOR_HOOK_PATH" "$STANDALONE_HOOK_PATH" "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH"; do
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
echo "  Iter-89 orchestrator: pyi-stub-guard inlined + 6-subhook contract clean"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

PAYLOAD_TEMP_DIR=$(mktemp -d -t iter89-payloads.XXXXXX)
trap 'rm -rf "$PAYLOAD_TEMP_DIR"' EXIT

# ─── Case 1: __init__.py with top-level class definition → DENY ────────────────
case1_payload="$PAYLOAD_TEMP_DIR/case1.json"
cat > "$case1_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/__init__.py","content":"class Foo:\n    pass\n"}}
PAYLOAD

set +e
case1_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case1_payload" 2>/dev/null)
case1_exit=$?
set -e

if [[ "$case1_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case1_stdout" == *'INIT-STRUCTURE-GUARD'* ]]; then
    assert_passes "Case 1a: orchestrator denies __init__.py with top-level class def"
else
    assert_fails "Case 1a: stdout missing deny; got=${case1_stdout:0:200}"
fi
if [[ "$case1_stdout" == *'pyi-stub-guard → DENY'* ]]; then
    assert_passes "Case 1b: deny attributed to pyi-stub-guard subhook"
else
    assert_fails "Case 1b: subhook attribution missing"
fi
if [[ "$case1_stdout" == *'class definition'* ]]; then
    assert_passes "Case 1c: violation label includes 'class definition'"
else
    assert_fails "Case 1c: violation label missing"
fi
if [[ "$case1_exit" == "2" ]]; then
    assert_passes "Case 1d: orchestrator exits 2 on pyi-stub-guard deny (belt-and-suspenders)"
else
    assert_fails "Case 1d: exit=$case1_exit, expected 2"
fi

# ─── Case 2: __init__.pyi with top-level def → DENY (stricter PEP 561) ────────
case2_payload="$PAYLOAD_TEMP_DIR/case2.json"
cat > "$case2_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/__init__.pyi","content":"def some_helper(x: int) -> int:\n    ...\n"}}
PAYLOAD

set +e
case2_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case2_payload" 2>/dev/null)
case2_exit=$?
set -e

if [[ "$case2_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case2_stdout" == *'PEP 561'* ]]; then
    assert_passes "Case 2a: orchestrator denies __init__.pyi with top-level def (PEP 561 stricter guidance)"
else
    assert_fails "Case 2a: __init__.pyi PEP 561 guidance missing; got=${case2_stdout:0:200}"
fi
if [[ "$case2_exit" == "2" ]]; then
    assert_passes "Case 2b: exit 2 on .pyi deny"
else
    assert_fails "Case 2b: exit=$case2_exit, expected 2"
fi

# ─── Case 3: non-init Python file (models.py) → ALLOW (O(1) suffix fastpath) ──
case3_payload="$PAYLOAD_TEMP_DIR/case3.json"
cat > "$case3_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/models.py","content":"class Foo:\n    pass\n"}}
PAYLOAD

set +e
case3_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case3_payload" 2>/dev/null)
case3_exit=$?
set -e

if [[ "$case3_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case3_exit" == "0" ]]; then
    assert_passes "Case 3: non-init Python file (models.py) → allow (suffix fastpath skipped pyi-stub-guard)"
else
    assert_fails "Case 3: suffix fastpath broken; exit=$case3_exit"
fi

# ─── Case 4: __init__.py with escape-hatch # INIT-MONOLITH-OK → ALLOW ─────────
case4_payload="$PAYLOAD_TEMP_DIR/case4.json"
cat > "$case4_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/__init__.py","content":"# INIT-MONOLITH-OK: legacy adapter shim, refactor planned 2026-Q3\nclass Foo:\n    pass\n"}}
PAYLOAD

set +e
case4_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case4_payload" 2>/dev/null)
case4_exit=$?
set -e

if [[ "$case4_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case4_exit" == "0" ]]; then
    assert_passes "Case 4: # INIT-MONOLITH-OK escape-hatch honored → allow"
else
    assert_fails "Case 4: escape-hatch broken; exit=$case4_exit"
fi

# ─── Case 5: re-export-dominated Write (>70% imports) → ALLOW ─────────────────
# 5 imports + 1 incidental class → 5/6 = 83.3% imports, above the 70% threshold
case5_payload="$PAYLOAD_TEMP_DIR/case5.json"
cat > "$case5_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/__init__.py","content":"from .a import Alpha as Alpha\nfrom .b import Beta as Beta\nfrom .c import Gamma as Gamma\nfrom .d import Delta as Delta\nimport os\nclass _ReExportSentinel: pass\n"}}
PAYLOAD

set +e
case5_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case5_payload" 2>/dev/null)
case5_exit=$?
set -e

if [[ "$case5_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case5_exit" == "0" ]]; then
    assert_passes "Case 5: re-export-dominated Write (≥70% imports) → allow (heuristic exempts re-export index files)"
else
    assert_fails "Case 5: re-export-dominated heuristic broken; exit=$case5_exit; stdout=${case5_stdout:0:200}"
fi

# ─── Case 6: standalone pyi-stub-guard still works (backward-compat) ──────────
set +e
case6_stdout=$(bun "$STANDALONE_HOOK_PATH" < "$case1_payload" 2>/dev/null)
set -e

if [[ "$case6_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case6_stdout" == *'INIT-STRUCTURE-GUARD'* ]]; then
    assert_passes "Case 6a: standalone pyi-stub-guard.ts denies (backward-compat)"
else
    assert_fails "Case 6a: standalone broken; got=${case6_stdout:0:200}"
fi
if [[ "$case6_stdout" != *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 6b: standalone reason has NO orchestrator prefix"
else
    assert_fails "Case 6b: standalone leaked orchestrator prefix"
fi

# ─── Case 7: subhook-contract audit task discovers 6 subhooks, all clean ──────
set +e
case7_stdout=$(bash "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH" 2>&1)
set -e

case7_subhook_count=$(echo "$case7_stdout" | grep -oE 'Total subhook files scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
if [[ "${case7_subhook_count:-0}" -ge 6 ]]; then
    assert_passes "Case 7a: audit task discovers ≥6 inlined subhooks (found ${case7_subhook_count})"
else
    assert_fails "Case 7a: subhook count ${case7_subhook_count} < 6"
fi
if [[ "$case7_stdout" == *'subhook files conform to the PreToolUseSubhookContract'* ]]; then
    assert_passes "Case 7b: audit task reports clean state (pyi-stub-guard.ts conforms)"
else
    assert_fails "Case 7b: clean-contract state not reported"
fi

# ─── Case 8: function-name algorithm-encoding precision (adversarial-audit deliverable) ────
# Verify the classifier file exports BOTH the precise algorithm-encoding name
# (classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator) AND the
# symmetric-naming alias (classifyPyiStubGuardForOrchestrator) — this enforces
# the iter-89 adversarial finding that the filename-vs-algorithm naming drift
# is acknowledged via dual exports.
if grep -q 'classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator' "$STANDALONE_HOOK_PATH" && \
   grep -q 'classifyPyiStubGuardForOrchestrator' "$STANDALONE_HOOK_PATH"; then
    assert_passes "Case 8: pyi-stub-guard.ts exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 8: dual-export naming-drift acknowledgement missing"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-89 pyi-stub inline regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
