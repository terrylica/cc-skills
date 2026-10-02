#!/usr/bin/env bash
# Iter-102 regression test for PreToolUse canonical-helper hoist (mirrors iter-100's PostToolUse-side helper hoist). Verifies the FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS allowlist + isFileEditToolNameHonoredByPreToolUseBlockingSubhook helper exist in the contract lib, the allow-set is exactly Write + Edit (the two file-content tools in the Claude Code tools reference), all 8 inlined classifiers import + use the canonical helper, the legacy hardcoded tool_name !== Write && tool_name !== Edit guard pattern is removed from all 8, and the orchestrator lets a tool name outside the allow-set through without a deny.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
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

# ─── Case 2: allowlist constant is exactly Write + Edit ─────────────────────
if grep -qF 'FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS' "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -qF 'ReadonlySet<string> = new Set(["Write", "Edit"]);' "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 2: PreToolUse allowlist constant is exactly Write + Edit"
else
    assert_fails "Case 2: PreToolUse allowlist constant is not exactly new Set([\"Write\", \"Edit\"])"
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

# ─── Case 5: helper accepts Write/Edit and rejects every other tool name ─────
set +e
case5_helper_verdicts=$(cd "$REPO_ROOT" && bun -e '
import { isFileEditToolNameHonoredByPreToolUseBlockingSubhook as h } from "./plugins/itp-hooks/hooks/lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
console.log(["Write", "Edit", "NotebookEdit", "Bash", ""].map((t) => h(t)).join(","));
' 2>/dev/null)
set -e
if [[ "$case5_helper_verdicts" == "true,true,false,false,false" ]]; then
    assert_passes "Case 5: helper honors Write + Edit and rejects NotebookEdit, Bash and an empty name"
else
    assert_fails "Case 5: helper verdicts for Write,Edit,NotebookEdit,Bash,'' were '$case5_helper_verdicts' (expected true,true,false,false,false)"
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

# ─── Case 7: e2e — a tool name outside the allow-set is allowed through ─────
# The orchestrator's fastpath returns allow for anything but Write/Edit, so a
# NotebookEdit payload (a notebook cell, not file content) must exit 0 with no
# deny even when the target path would trip a classifier for a Write.
if [[ -f "$PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH" ]]; then
    TEMP_OTHER_TOOL_PAYLOAD_FILE="$TEMP_E2E_DIR/payload-other-tool.json"
    cat > "$TEMP_OTHER_TOOL_PAYLOAD_FILE" <<JSON
{"tool_name":"NotebookEdit","session_id":"iter102-other-tool-$(date +%s%N)","tool_input":{"notebook_path":"$TEMP_E2E_DIR/sample.ipynb","new_source":"x = 1"}}
JSON
    set +e
    case7_stdout=$(bun "$PRETOOLUSE_ORCHESTRATOR_ABSOLUTE_PATH" < "$TEMP_OTHER_TOOL_PAYLOAD_FILE" 2>/dev/null)
    case7_exit=$?
    set -e
    case7_has_deny=0
    [[ "$case7_stdout" == *'"permissionDecision":"deny"'* ]] && case7_has_deny=1
    if [[ "$case7_exit" == "0" ]] && [[ "$case7_has_deny" == "0" ]]; then
        assert_passes "Case 7: tool name outside the allow-set (NotebookEdit) passes the orchestrator with no deny"
    else
        assert_fails "Case 7: non-file-edit tool path broken (exit=$case7_exit, has_deny=$case7_has_deny, stdout-head='${case7_stdout:0:200}')"
    fi
fi

# ─── Case 8: lib documents the allow-set source + NotebookEdit exclusion ─────
# Documentation invariant: the helper comment must cite the upstream tools
# reference the allow-set is derived from, and say why NotebookEdit is out.
if grep -q "code.claude.com/docs/en/tools-reference" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   grep -q "NotebookEdit" "$PRETOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 8: contract lib cites the tools reference + documents NotebookEdit non-acceptance"
else
    assert_fails "Case 8: contract lib missing the tools-reference citation or the NotebookEdit rationale"
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
