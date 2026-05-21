#!/usr/bin/env bash
#MISE description="Iter-102 regression test for PreToolUse canonical-helper hoist (mirrors iter-100's PostToolUse-side helper hoist). Verifies the FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS allowlist + isFileEditToolNameHonoredByPreToolUseBlockingSubhook helper exist in the contract lib, all 8 inlined classifiers import + use the canonical helper, the legacy hardcoded tool_name !== Write && tool_name !== Edit guard pattern is removed from all 8, and the iter-102 staged-migration MultiEdit short-circuit preserves status quo (preventing false-positives until iter-103+ per-classifier MultiEdit content-extraction work)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts"

declare -a EIGHT_INLINED_PRETOOLUSE_CLASSIFIER_ABSOLUTE_PATHS=(
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-vale-claude-md-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-version-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-hoisted-deps-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-mise-hygiene-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-pyi-stub-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-native-binary-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-gpu-optimization-guard.ts"
)

for required_file in "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" "${EIGHT_INLINED_PRETOOLUSE_CLASSIFIER_ABSOLUTE_PATHS[@]}"; do
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
echo "  Iter-102 PreToolUse canonical-helper hoist regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: canonical allowlist constant + helper exist in contract lib ─────
if grep -q "FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -q "isFileEditToolNameHonoredByPreToolUseBlockingSubhook" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 1: canonical allowlist constant + helper exist in PreToolUse contract lib"
else
    assert_fails "Case 1: canonical allowlist constant or helper missing from PreToolUse contract lib"
fi

# ─── Case 2: allowlist constant contains all 3 file-edit tool names ──────────
case2_allowlist_block=$(awk '/FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS/,/\);/' "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" | head -10)
case2_has_write=0
case2_has_edit=0
case2_has_multiedit=0
[[ "$case2_allowlist_block" == *'"Write"'* ]] && case2_has_write=1
[[ "$case2_allowlist_block" == *'"Edit"'* ]] && case2_has_edit=1
[[ "$case2_allowlist_block" == *'"MultiEdit"'* ]] && case2_has_multiedit=1
if [[ "$case2_has_write" == "1" ]] && [[ "$case2_has_edit" == "1" ]] && [[ "$case2_has_multiedit" == "1" ]]; then
    assert_passes "Case 2: PreToolUse allowlist constant contains Write + Edit + MultiEdit"
else
    assert_fails "Case 2: PreToolUse allowlist constant missing entries (write=$case2_has_write edit=$case2_has_edit multiedit=$case2_has_multiedit)"
fi

# ─── Case 3: all 8 inlined classifiers import the canonical helper ───────────
case3_classifiers_consuming_helper_count=0
for classifier_path in "${EIGHT_INLINED_PRETOOLUSE_CLASSIFIER_ABSOLUTE_PATHS[@]}"; do
    if grep -q "isFileEditToolNameHonoredByPreToolUseBlockingSubhook" "$classifier_path"; then
        case3_classifiers_consuming_helper_count=$((case3_classifiers_consuming_helper_count + 1))
    fi
done
if [[ "$case3_classifiers_consuming_helper_count" == "8" ]]; then
    assert_passes "Case 3: all 8 inlined PreToolUse classifiers import + consume the canonical helper"
else
    assert_fails "Case 3: only $case3_classifiers_consuming_helper_count/8 inlined classifiers consume the canonical helper — iter-102 migration incomplete"
fi

# ─── Case 4: legacy hardcoded tool_name guard removed from all 8 classifiers ──
# Pre-iter-102 each classifier had its own `tool_name !== "Write" && tool_name !== "Edit"`
# (or `toolName !==` variant) guard. Post-iter-102 these must be 0.
# Emission-pattern grep (not prose-comment grep): skip lines whose first
# non-whitespace character is `*` (JSDoc continuation) or `//` (line comment).
case4_classifiers_with_legacy_guard_count=0
for classifier_path in "${EIGHT_INLINED_PRETOOLUSE_CLASSIFIER_ABSOLUTE_PATHS[@]}"; do
    matches=$(grep -nE '(tool_name|toolName).*!==.*"Write".*&&.*(tool_name|toolName).*!==.*"Edit"' "$classifier_path" 2>/dev/null \
        | grep -vE ':[[:space:]]*\*' \
        | grep -vE ':[[:space:]]*//' \
        || true)
    if [[ -n "$matches" ]]; then
        case4_classifiers_with_legacy_guard_count=$((case4_classifiers_with_legacy_guard_count + 1))
    fi
done
if [[ "$case4_classifiers_with_legacy_guard_count" == "0" ]]; then
    assert_passes "Case 4: legacy hardcoded tool_name guard removed from all 8 classifiers"
else
    assert_fails "Case 4: $case4_classifiers_with_legacy_guard_count/8 classifiers still have legacy hardcoded tool_name guard"
fi

# ─── Case 5: iter-102 staged-migration MultiEdit short-circuit present ───────
# Each classifier should have the explicit `if (tool_name === "MultiEdit") return ALLOW_DECISION;`
# placeholder to preserve status quo until iter-103+ per-classifier MultiEdit
# content extraction lands.
case5_classifiers_with_multiedit_short_circuit_count=0
for classifier_path in "${EIGHT_INLINED_PRETOOLUSE_CLASSIFIER_ABSOLUTE_PATHS[@]}"; do
    if grep -qE '(tool_name|toolName).*===.*"MultiEdit"' "$classifier_path"; then
        case5_classifiers_with_multiedit_short_circuit_count=$((case5_classifiers_with_multiedit_short_circuit_count + 1))
    fi
done
if [[ "$case5_classifiers_with_multiedit_short_circuit_count" == "8" ]]; then
    assert_passes "Case 5: iter-102 staged-migration MultiEdit short-circuit present in all 8 classifiers (preserves status quo until iter-103+)"
else
    assert_fails "Case 5: only $case5_classifiers_with_multiedit_short_circuit_count/8 classifiers have iter-102 MultiEdit short-circuit"
fi

# ─── Case 6: e2e — PreToolUse orchestrator on Write payload still works ─────
# Backward-compat: verify the orchestrator still emits a non-error result on a
# clean Write payload after the iter-102 migration. Synthesize a benign .py
# write that shouldn't trip any of the 8 guards.
PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"
if [[ ! -f "$PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH" ]]; then
    assert_fails "Case 6: PreToolUse orchestrator not found at $PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH"
else
    TEMP_E2E_DIR=$(mktemp -d -t iter102-e2e.XXXXXX)
    trap 'rm -rf "$TEMP_E2E_DIR"' EXIT
    TEMP_PAYLOAD_FILE="$TEMP_E2E_DIR/payload.json"
    TEMP_PY_FILE="$TEMP_E2E_DIR/sample.py"
    cat > "$TEMP_PAYLOAD_FILE" <<JSON
{"tool_name":"Write","session_id":"iter102-e2e-$(date +%s%N)","tool_input":{"file_path":"$TEMP_PY_FILE","content":"x = 1\n"}}
JSON
    set +e
    case6_stdout=$(bun "$PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH" < "$TEMP_PAYLOAD_FILE" 2>/dev/null)
    case6_exit=$?
    set -e
    # Clean Write should yield exit 0 (allow path emits empty stdout or an allow JSON)
    if [[ "$case6_exit" == "0" ]]; then
        assert_passes "Case 6: orchestrator backward-compat — clean Write payload still allows post-iter-102 migration (exit=0)"
    else
        assert_fails "Case 6: orchestrator broken on clean Write — exit=$case6_exit stdout='${case6_stdout:0:200}'"
    fi
fi

# ─── Case 7: e2e — MultiEdit payload routes through but classifiers no-op ────
# Iter-102 staged-migration behavior: orchestrator routes MultiEdit (iter-101
# matcher broadening) to each classifier, classifier hits canonical helper
# (passes) then MultiEdit short-circuit (returns ALLOW), net = silent allow.
# Verify orchestrator emits NO deny on a MultiEdit payload.
if [[ -f "$PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH" ]]; then
    TEMP_MULTIEDIT_PAYLOAD_FILE="$TEMP_E2E_DIR/payload-multiedit.json"
    TEMP_MULTIEDIT_PY_FILE="$TEMP_E2E_DIR/multiedit-sample.py"
    cat > "$TEMP_MULTIEDIT_PY_FILE" <<'PY'
import os
def x():
    return os.environ.get("X", "1")
PY
    cat > "$TEMP_MULTIEDIT_PAYLOAD_FILE" <<JSON
{"tool_name":"MultiEdit","session_id":"iter102-multiedit-$(date +%s%N)","tool_input":{"file_path":"$TEMP_MULTIEDIT_PY_FILE","edits":[{"old_string":"return os.environ.get(\"X\", \"1\")","new_string":"return os.environ.get(\"X\", \"1\")  # iter-102"}]}}
JSON
    set +e
    case7_stdout=$(bun "$PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH" < "$TEMP_MULTIEDIT_PAYLOAD_FILE" 2>/dev/null)
    case7_exit=$?
    set -e
    # iter-102 staged: classifiers self-skip on MultiEdit → no deny
    case7_has_deny=0
    [[ "$case7_stdout" == *'"permissionDecision":"deny"'* ]] && case7_has_deny=1
    if [[ "$case7_exit" == "0" ]] && [[ "$case7_has_deny" == "0" ]]; then
        assert_passes "Case 7: iter-102 staged-migration — MultiEdit routes through orchestrator + 8 classifiers self-skip (no false-positive deny)"
    else
        assert_fails "Case 7: MultiEdit path broken (exit=$case7_exit, has_deny=$case7_has_deny, stdout-head='${case7_stdout:0:200}')"
    fi
fi

# ─── Case 8: lib file contains iter-102 design rationale + iter-103 follow-up ──
# Documentation invariant: the helper hoist comment block must mention both
# (a) the iter-100 PostToolUse precedent + (b) the iter-103+ per-classifier
# MultiEdit content-extraction follow-up + (c) NotebookEdit non-acceptance
# rationale. These are NOT informational — they prevent future maintainers
# from re-discovering the same staged-migration decision points.
if grep -q "iter-100" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -q "iter-103" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -q "NotebookEdit" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 8: contract lib documents iter-100 precedent + iter-103 follow-up scope + NotebookEdit non-acceptance"
else
    assert_fails "Case 8: contract lib missing iter-102 design rationale sections"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-102 regression — Summary"
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
echo "  🚀 Iter-102 PreToolUse canonical-helper hoist complete — mirrors iter-100's"
echo "     PostToolUse-side work. FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_"
echo "     SUBHOOKS centralizes the file-edit tool allow-set across 8 inlined"
echo "     classifiers (file-size-guard, vale-claude-md-guard, version-guard,"
echo "     hoisted-deps-guard, mise-hygiene-guard, pyi-stub-guard, native-binary-"
echo "     guard, gpu-optimization-guard). Future Anthropic tool-name additions"
echo "     update ONE constant, not 8 classifier files."
echo "  🚀 Iter-102 staged-migration MultiEdit short-circuit preserves status quo"
echo "     until iter-103+ per-classifier MultiEdit content-extraction work."
