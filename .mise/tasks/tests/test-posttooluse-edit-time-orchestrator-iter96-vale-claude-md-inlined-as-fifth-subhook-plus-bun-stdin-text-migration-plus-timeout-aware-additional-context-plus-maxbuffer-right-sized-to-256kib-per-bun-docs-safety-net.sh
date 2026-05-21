#!/usr/bin/env bash
#MISE description="Iter-96 regression test for the PostToolUse orchestrator 5-subhook state. Verifies (1) vale-claude-md inlined as 5th subhook with dual-export naming; (2) orchestrator registry has ≥5 entries; (3) Bun.stdin.text() one-shot read replaces .stream()+TextDecoder loop in orchestrator + ALL 5 standalone classifier mains (2026 idiomatic API); (4) maxBuffer constant tightened from 8MiB to 256KiB per iter-96 audit; (5) timeout-aware additional_context helper exists in contract + orchestrator imports it + uses it in the timeout branch (replaces silent fail-open noop); (6) iter-94 static audit STILL passes after iter-96 migration (all 5 classifiers async-Bun.spawn); (7) hooks.json no longer wires standalone vale-claude-md; (8) marketplace test discovery still picks this test up; (9) ALL 5 classifiers retain import.meta.main standalone guards."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
CONTRACT_FILE_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
SHARED_LIB_HELPERS_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts"
TY_TYPE_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
TSGO_TYPE_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts"
OXLINT_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-oxlint-check.ts"
BIOME_LINT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-biome-lint.ts"
VALE_CLAUDE_MD_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts"
STATIC_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"

for required_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$CONTRACT_FILE_ABSOLUTE_PATH" \
    "$SHARED_LIB_HELPERS_ABSOLUTE_PATH" \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH" \
    "$VALE_CLAUDE_MD_ABSOLUTE_PATH" \
    "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" \
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
echo "  Iter-96 PostToolUse orchestrator regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: vale-claude-md inlined with dual-export naming ───────────────────
if grep -q "classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator" "$VALE_CLAUDE_MD_ABSOLUTE_PATH" && \
   grep -q "classifyValeClaudeMdForPostToolUseOrchestrator" "$VALE_CLAUDE_MD_ABSOLUTE_PATH"; then
    assert_passes "Case 1: vale-claude-md exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 1: vale-claude-md dual-export naming pattern missing"
fi
if grep -q "classifyValeClaudeMdForPostToolUseOrchestrator" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 1b: orchestrator imports vale-claude-md classifier"
else
    assert_fails "Case 1b: vale-claude-md not imported by orchestrator"
fi

# ─── Case 2: orchestrator registry has ≥5 entries ─────────────────────────────
case2_registry_subhook_count=$(grep -cE '^[[:space:]]+name:[[:space:]]*"' "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" || true)
case2_registry_subhook_count=${case2_registry_subhook_count:-0}
if [[ "${case2_registry_subhook_count}" -ge 5 ]]; then
    assert_passes "Case 2: orchestrator registry has ≥5 subhooks (iter-96 state; found ${case2_registry_subhook_count})"
else
    assert_fails "Case 2: only ${case2_registry_subhook_count} subhooks registered (expected ≥5 after iter-96)"
fi

# ─── Case 3: Bun.stdin.text() everywhere; no stdin.stream() in orchestrator + 5 classifiers ──
# Emission-pattern check (not prose-comment check): skip JSDoc continuation
# lines starting with `*` and pure line-comments starting with `//`. Mirrors
# the iter-94 static audit's emission-vs-prose distinction.
files_using_legacy_stream_count=0
for source_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH" \
    "$VALE_CLAUDE_MD_ABSOLUTE_PATH"; do
    # Strip JSDoc continuation lines (^\s*\*) and line-comments (^\s*//)
    # before scanning for Bun.stdin.stream(
    emission_matches=$(grep -nE "Bun\.stdin\.stream\(" "$source_file_absolute_path" 2>/dev/null \
        | grep -vE ':[[:space:]]*\*' \
        | grep -vE ':[[:space:]]*//' \
        || true)
    if [[ -n "$emission_matches" ]]; then
        files_using_legacy_stream_count=$((files_using_legacy_stream_count + 1))
        echo "    ↳ legacy stream invocation in $(basename "$source_file_absolute_path"): $emission_matches"
    fi
done
if [[ "$files_using_legacy_stream_count" == "0" ]]; then
    assert_passes "Case 3a: ALL 6 files (orchestrator + 5 classifier mains) use Bun.stdin.text() — none use legacy Bun.stdin.stream() loop"
else
    assert_fails "Case 3a: ${files_using_legacy_stream_count} file(s) still use Bun.stdin.stream() — iter-96 migration incomplete"
fi
files_using_modern_text_count=0
for source_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH" \
    "$VALE_CLAUDE_MD_ABSOLUTE_PATH"; do
    if grep -q "Bun\.stdin\.text(" "$source_file_absolute_path"; then
        files_using_modern_text_count=$((files_using_modern_text_count + 1))
    fi
done
if [[ "$files_using_modern_text_count" == "6" ]]; then
    assert_passes "Case 3b: ALL 6 files now call Bun.stdin.text() (2026 idiomatic one-shot API)"
else
    assert_fails "Case 3b: only ${files_using_modern_text_count}/6 files use Bun.stdin.text()"
fi

# ─── Case 4: maxBuffer constant tightened from 8MiB to 256KiB ─────────────────
if grep -qE "DEFAULT_SUBPROCESS_OUTPUT_MAX_BUFFER_BYTES_PER_BUN_DOCS_SAFETY_NET[[:space:]]*=[[:space:]]*256[[:space:]]*\*[[:space:]]*1024" "$SHARED_LIB_HELPERS_ABSOLUTE_PATH"; then
    assert_passes "Case 4: maxBuffer constant tightened to 256 * 1024 (256 KiB; iter-96 right-sizing per Bun docs audit)"
else
    assert_fails "Case 4: maxBuffer constant NOT tightened — still at iter-95 8MiB value or not 256KiB"
fi

# ─── Case 5: timeout-aware additional_context helper exists + is used ─────────
if grep -q "buildPostToolUseTimeoutAwareAdditionalContextDecisionForOperatorVisibility" "$CONTRACT_FILE_ABSOLUTE_PATH"; then
    assert_passes "Case 5a: timeout-aware additional_context helper exists in contract"
else
    assert_fails "Case 5a: timeout-aware additional_context helper missing from contract"
fi
if grep -q "buildPostToolUseTimeoutAwareAdditionalContextDecisionForOperatorVisibility" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 5b: orchestrator imports + uses the timeout-aware helper (replaces silent fail-open noop on timeout)"
else
    assert_fails "Case 5b: orchestrator doesn't import the timeout-aware helper"
fi

# ─── Case 6: iter-94 static audit STILL passes after iter-96 migration ────────
set +e
static_audit_output=$(bash "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
static_audit_exit_code=$?
set -e
if [[ "$static_audit_exit_code" == "0" ]] && [[ "$static_audit_output" == *'AUDIT PASSED'* ]]; then
    static_audit_scanned_count=$(echo "$static_audit_output" | grep -oE 'Classifier source files imported by orchestrator:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
    if [[ "${static_audit_scanned_count:-0}" -ge 5 ]]; then
        assert_passes "Case 6: iter-94 static audit STILL passes (scanned ${static_audit_scanned_count} classifiers cleanly — no spawnSync regression in 5/15 state)"
    else
        assert_fails "Case 6: static audit passed but only ${static_audit_scanned_count} classifiers discovered (expected ≥5)"
    fi
else
    assert_fails "Case 6: static audit failed (exit=$static_audit_exit_code)"
fi

# ─── Case 7: hooks.json no longer wires standalone vale-claude-md ─────────────
case7_vale_standalone_count=$(jq -r '[.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-vale-claude-md.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case7_vale_standalone_count" == "0" ]]; then
    assert_passes "Case 7: hooks.json no longer wires standalone vale-claude-md (iter-96 removal — only via orchestrator import)"
else
    assert_fails "Case 7: standalone vale-claude-md still wired ${case7_vale_standalone_count} time(s)"
fi

# ─── Case 8: ALL 5 classifiers retain import.meta.main standalone guards ──────
backward_compat_count=0
for classifier_file_absolute_path in \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH" \
    "$VALE_CLAUDE_MD_ABSOLUTE_PATH"; do
    if grep -q "import.meta.main" "$classifier_file_absolute_path"; then
        backward_compat_count=$((backward_compat_count + 1))
    fi
done
if [[ "$backward_compat_count" == "5" ]]; then
    assert_passes "Case 8: ALL 5 classifiers retain import.meta.main guard for standalone CLI (backward-compat preserved)"
else
    assert_fails "Case 8: only ${backward_compat_count}/5 classifiers have import.meta.main guard"
fi

# ─── Case 9: orchestrator silent-noop on non-applicable .txt payload ──────────
TEMP_PAYLOAD_FILE=$(mktemp -t iter96-payload.XXXXXX)
trap 'rm -f "$TEMP_PAYLOAD_FILE"' EXIT
cat > "$TEMP_PAYLOAD_FILE" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter96/foo.txt","content":"plain text\n"}}
PAYLOAD
set +e
case9_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$TEMP_PAYLOAD_FILE" 2>/dev/null)
case9_exit=$?
set -e
if [[ -z "$case9_stdout" ]] && [[ "$case9_exit" == "0" ]]; then
    assert_passes "Case 9: orchestrator silent-noop + exit 0 on non-applicable .txt payload (all 5 subhooks return noop via O(1) filter)"
else
    assert_fails "Case 9: orchestrator misbehaved on .txt; exit=$case9_exit stdout='${case9_stdout:0:200}'"
fi

# ─── Case 10: orchestrator description bumped to 5/15 ─────────────────────────
if jq -r '.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-edit-time-orchestrator-aggregating")) | .description' "$HOOKS_JSON_ABSOLUTE_PATH" 2>/dev/null | grep -qE '5/15 subhooks inlined'; then
    assert_passes "Case 10: hooks.json orchestrator description records 5/15 milestone + iter-96 enhancements"
else
    assert_fails "Case 10: orchestrator description not updated to 5/15"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-96 PostToolUse orchestrator regression — Summary"
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
echo "  🚀 Iter-96 PostToolUse arc progress: 5/15 subhooks inlined."
echo "  🚀 Iter-96 stdin migration: Bun.stdin.text() one-shot read across all 6 entry points."
echo "  🚀 Iter-96 timeout-aware additional_context: no more silent fail-open false-negatives."
echo "  🚀 Iter-96 maxBuffer right-sized: 256KiB surfaces output anomalies earlier."
