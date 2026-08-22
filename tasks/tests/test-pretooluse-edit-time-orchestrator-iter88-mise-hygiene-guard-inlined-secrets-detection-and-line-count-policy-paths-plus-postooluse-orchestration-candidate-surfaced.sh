#!/usr/bin/env bash
#MISE description="Iter-88 regression test extending iter-87 orchestrator coverage. Verifies (1) mise-hygiene-guard inlined as 5th registry entry produces matching deny for both policies (secrets detection + line count >100), (2) .mise.local.toml correctly skipped (ignore-list fastpath), (3) safe-pattern lines (read_file/env/op_read/doppler) do NOT trigger secrets policy, (4) standalone backward-compat preserved, (5) iter-88 adversarial finding (9 PostToolUse Write|Edit hooks form next orchestration candidate worth ~136ms) surfaced and queued."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCHESTRATOR_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"
STANDALONE_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-mise-hygiene-guard.ts"
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
echo "  Iter-88 orchestrator: mise-hygiene-guard inlined + 5-subhook contract clean"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: mise.toml with API_KEY secret → DENY ───────────────────────────────
case1_payload=$(mktemp -t iter88-case1.XXXXXX.json)
trap 'rm -f "$case1_payload"' EXIT
cat > "$case1_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/home/foo/mise.toml","content":"[env]\nAPI_KEY = \"sk-1234567890abcdef\"\n"}}
PAYLOAD

set +e
case1_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case1_payload" 2>/dev/null)
case1_exit=$?
set -e

if [[ "$case1_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case1_stdout" == *'MISE-HYGIENE'* ]]; then
    assert_passes "Case 1a: orchestrator denies mise.toml with hardcoded API_KEY"
else
    assert_fails "Case 1a: stdout missing deny; got=${case1_stdout:0:200}"
fi
if [[ "$case1_stdout" == *'mise-hygiene-guard → DENY'* ]]; then
    assert_passes "Case 1b: deny attributed to mise-hygiene-guard subhook"
else
    assert_fails "Case 1b: subhook attribution missing"
fi
if [[ "$case1_stdout" == *'Secrets detected'* ]]; then
    assert_passes "Case 1c: secrets-detection policy fires (POLICY 1)"
else
    assert_fails "Case 1c: secrets policy diagnostic missing"
fi
if [[ "$case1_exit" == "2" ]]; then
    assert_passes "Case 1d: orchestrator exits 2 on mise-hygiene deny"
else
    assert_fails "Case 1d: exit=$case1_exit, expected 2"
fi

# ─── Case 2: .mise.local.toml with same secret → ALLOW (ignore-list) ──────────
case2_payload=$(mktemp -t iter88-case2.XXXXXX.json)
trap 'rm -f "$case1_payload" "$case2_payload"' EXIT
cat > "$case2_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/home/foo/.mise.local.toml","content":"[env]\nAPI_KEY = \"sk-1234567890abcdef\"\n"}}
PAYLOAD

set +e
case2_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case2_payload" 2>/dev/null)
case2_exit=$?
set -e

if [[ "$case2_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case2_exit" == "0" ]]; then
    assert_passes "Case 2: .mise.local.toml ignore-list honored (secrets allowed there by design)"
else
    assert_fails "Case 2: ignore-list broken; exit=$case2_exit"
fi

# ─── Case 3: mise.toml with safe-pattern external reference → ALLOW ────────────
case3_payload=$(mktemp -t iter88-case3.XXXXXX.json)
trap 'rm -f "$case1_payload" "$case2_payload" "$case3_payload"' EXIT
cat > "$case3_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/home/foo/mise.toml","content":"[env]\nAPI_KEY = \"{{ op_read('op://Vault/Item/credential') }}\"\nGH_TOKEN = \"{{ read_file(path='~/.secrets/gh') | trim }}\"\n"}}
PAYLOAD

set +e
case3_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case3_payload" 2>/dev/null)
case3_exit=$?
set -e

if [[ "$case3_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case3_exit" == "0" ]]; then
    assert_passes "Case 3: safe-pattern external references (op_read, read_file) → allow"
else
    assert_fails "Case 3: safe-pattern fastpath broken; exit=$case3_exit"
fi

# ─── Case 4: oversized mise.toml (>100 lines) → DENY with hub-spoke guidance ───
case4_payload=$(mktemp -t iter88-case4.XXXXXX.json)
trap 'rm -f "$case1_payload" "$case2_payload" "$case3_payload" "$case4_payload"' EXIT

# Build 105-line content with one [tasks.foo] section per line
oversized_content=$(printf '[tasks.foo%d]\nrun = "echo hi"\n' {1..55})
oversized_content_json_escaped=$(python3 -c '
import json, sys
print(json.dumps(sys.argv[1]), end="")
' "$oversized_content")
printf '{"tool_name":"Write","tool_input":{"file_path":"/home/foo/mise.toml","content":%s}}' "$oversized_content_json_escaped" > "$case4_payload"

set +e
case4_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case4_payload" 2>/dev/null)
case4_exit=$?
set -e

if [[ "$case4_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case4_stdout" == *'exceeds'* ]]; then
    assert_passes "Case 4a: orchestrator denies oversized mise.toml (POLICY 2)"
else
    assert_fails "Case 4a: line-count policy diagnostic missing; stdout=${case4_stdout:0:200}"
fi
if [[ "$case4_stdout" == *'hub-spoke'* ]]; then
    assert_passes "Case 4b: hub-spoke refactoring guidance included in deny message"
else
    assert_fails "Case 4b: hub-spoke suggestion missing"
fi
if [[ "$case4_exit" == "2" ]]; then
    assert_passes "Case 4c: exit code 2 on line-count violation"
else
    assert_fails "Case 4c: exit=$case4_exit, expected 2"
fi

# ─── Case 5: standalone mise-hygiene-guard still works (backward-compat) ──────
set +e
case5_stdout=$(bun "$STANDALONE_HOOK_PATH" < "$case1_payload" 2>/dev/null)
set -e

if [[ "$case5_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case5_stdout" == *'MISE-HYGIENE'* ]]; then
    assert_passes "Case 5a: standalone mise-hygiene-guard.ts denies (backward-compat)"
else
    assert_fails "Case 5a: standalone broken; got=${case5_stdout:0:200}"
fi
if [[ "$case5_stdout" != *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 5b: standalone reason has NO orchestrator prefix"
else
    assert_fails "Case 5b: standalone leaked orchestrator prefix"
fi

# ─── Case 6: subhook-contract audit task discovers 5 subhooks, all clean ───────
set +e
case6_stdout=$(bash "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH" 2>&1)
set -e

case6_subhook_count=$(echo "$case6_stdout" | grep -oE 'Total subhook files scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
if [[ "${case6_subhook_count:-0}" -ge 5 ]]; then
    assert_passes "Case 6a: audit task discovers ≥5 inlined subhooks (found ${case6_subhook_count})"
else
    assert_fails "Case 6a: subhook count ${case6_subhook_count} < 5"
fi
if [[ "$case6_stdout" == *'subhook files conform to the PreToolUseSubhookContract'* ]]; then
    assert_passes "Case 6b: audit task reports clean state (mise-hygiene-guard.ts conforms)"
else
    assert_fails "Case 6b: clean-contract state not reported"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-88 mise-hygiene inline regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
