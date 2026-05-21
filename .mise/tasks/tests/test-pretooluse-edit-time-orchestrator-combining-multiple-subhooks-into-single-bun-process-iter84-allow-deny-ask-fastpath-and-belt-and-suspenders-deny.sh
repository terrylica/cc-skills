#!/usr/bin/env bash
#MISE description="Iter-84 regression test for pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts. Asserts: (1) non-Write/Edit fastpath returns allow, (2) Write under threshold returns allow, (3) Write over block threshold triggers belt-and-suspenders deny (stdout JSON deny + stderr diagnostic + exit 2 per iter-78/GitHub #37210), (4) FILE-SIZE-OK escape hatch is honored, (5) the orchestrator-emitted reason includes the orchestrator diagnostic prefix to distinguish it from a standalone subhook call."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# Generate N copies of a fixed line, joined by literal newlines. Bash
# loop avoids the `yes | head` SIGPIPE-141 hazard under `set -o pipefail`.
generate_n_repeated_lines_for_oversized_fixture() {
    local line_count="$1"
    local line_text="$2"
    local i
    for ((i = 0; i < line_count; i++)); do
        printf '%s\n' "$line_text"
    done
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCHESTRATOR_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"

if [[ ! -f "$ORCHESTRATOR_HOOK_PATH" ]]; then
    echo "FAIL: Orchestrator hook not found at $ORCHESTRATOR_HOOK_PATH"
    exit 1
fi

ASSERTION_COUNT_PASSED=0
ASSERTION_COUNT_FAILED=0

assert_passes() {
    ASSERTION_COUNT_PASSED=$((ASSERTION_COUNT_PASSED + 1))
    echo "  ✓ PASS: $1"
}
assert_fails() {
    ASSERTION_COUNT_FAILED=$((ASSERTION_COUNT_FAILED + 1))
    echo "  ✗ FAIL: $1"
}

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Iter-84 PreToolUse Edit-Time Orchestrator — Regression Test"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: non-Write/Edit fastpath returns allow ───────────────────────────
case1_payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/anything"}}'
case1_stdout=$(echo "$case1_payload" | bun "$ORCHESTRATOR_HOOK_PATH" 2>/dev/null || true)
if [[ "$case1_stdout" == *'"permissionDecision":"allow"'* ]]; then
    assert_passes "Case 1: non-Write/Edit (tool=Read) → allow"
else
    assert_fails "Case 1: non-Write/Edit fastpath; stdout=$case1_stdout"
fi

# ─── Case 2: small Write under warn threshold → allow ────────────────────────
case2_content="// small\nconst x = 1;\n"
case2_payload=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter84-small.ts","content":"%s"}}' "$case2_content")
case2_stdout=$(echo "$case2_payload" | bun "$ORCHESTRATOR_HOOK_PATH" 2>/dev/null || true)
if [[ "$case2_stdout" == *'"permissionDecision":"allow"'* ]]; then
    assert_passes "Case 2: small Write under threshold → allow"
else
    assert_fails "Case 2: small Write; stdout=$case2_stdout"
fi

# ─── Case 3: large Write over BLOCK threshold → belt-and-suspenders deny ──────
# 1500-line .ts file (block threshold = 1000). Expect:
#   stdout: JSON with permissionDecision=deny + orchestrator prefix in reason
#   stderr: diagnostic line containing "DENY from subhook=file-size-guard"
#   exit code: 2
case3_content=$(generate_n_repeated_lines_for_oversized_fixture 1500 "export const x = 1;" | tr "\n" "@")
case3_content_escaped=${case3_content//@/\\n}
case3_payload_file=$(mktemp -t iter84-orch-test-case3.XXXXXX.json)
trap 'rm -f "$case3_payload_file"' EXIT
printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter84-bigfile.ts","content":"%s"}}' "$case3_content_escaped" > "$case3_payload_file"
case3_stderr_file=$(mktemp -t iter84-orch-test-case3-stderr.XXXXXX.txt)
trap 'rm -f "$case3_payload_file" "$case3_stderr_file"' EXIT
set +e
case3_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case3_payload_file" 2>"$case3_stderr_file")
case3_exit=$?
set -e
case3_stderr=$(cat "$case3_stderr_file")

# (3a) stdout JSON deny
if [[ "$case3_stdout" == *'"permissionDecision":"deny"'* ]]; then
    assert_passes "Case 3a: large Write → stdout JSON permissionDecision=deny"
else
    assert_fails "Case 3a: stdout missing deny; stdout=$case3_stdout"
fi

# (3b) stdout reason includes orchestrator prefix
if [[ "$case3_stdout" == *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 3b: deny reason includes orchestrator diagnostic prefix"
else
    assert_fails "Case 3b: stdout missing orchestrator prefix; stdout=$case3_stdout"
fi

# (3c) stdout reason includes subhook name
if [[ "$case3_stdout" == *'file-size-guard → DENY'* ]]; then
    assert_passes "Case 3c: deny reason includes subhook name (file-size-guard)"
else
    assert_fails "Case 3c: stdout missing subhook attribution; stdout=$case3_stdout"
fi

# (3d) stderr diagnostic line
if [[ "$case3_stderr" == *'DENY from subhook=file-size-guard'* ]]; then
    assert_passes "Case 3d: stderr diagnostic line emitted (belt-and-suspenders)"
else
    assert_fails "Case 3d: stderr missing diagnostic; stderr=$case3_stderr"
fi

# (3e) exit code 2
if [[ "$case3_exit" == "2" ]]; then
    assert_passes "Case 3e: exit code = 2 (belt-and-suspenders per GH #37210)"
else
    assert_fails "Case 3e: exit code = $case3_exit, expected 2"
fi

# ─── Case 4: FILE-SIZE-OK escape hatch in large file → allow ─────────────────
case4_content_with_escape=$(printf "// FILE-SIZE-OK\n%s" "$(generate_n_repeated_lines_for_oversized_fixture 1500 "export const x = 1;" | tr "\n" "@")")
case4_content_with_escape_escaped=${case4_content_with_escape//@/\\n}
case4_payload_file=$(mktemp -t iter84-orch-test-case4.XXXXXX.json)
trap 'rm -f "$case3_payload_file" "$case3_stderr_file" "$case4_payload_file"' EXIT
printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter84-bigfile-escape.ts","content":"%s"}}' "$case4_content_with_escape_escaped" > "$case4_payload_file"
set +e
case4_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case4_payload_file" 2>/dev/null)
case4_exit=$?
set -e
if [[ "$case4_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case4_exit" == "0" ]]; then
    assert_passes "Case 4: large Write with FILE-SIZE-OK escape hatch → allow + exit 0"
else
    assert_fails "Case 4: escape hatch not honored; exit=$case4_exit stdout=$case4_stdout"
fi

# ─── Case 5: standalone file-size-guard still works (backward-compat) ────────
STANDALONE_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
set +e
case5_stdout=$(bun "$STANDALONE_HOOK_PATH" < "$case3_payload_file" 2>/dev/null)
case5_exit=$?
set -e
if [[ "$case5_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case5_exit" == "0" ]]; then
    assert_passes "Case 5: standalone file-size-guard still emits deny + exit 0 (no orchestrator-prefix)"
else
    assert_fails "Case 5: standalone backward-compat broken; exit=$case5_exit"
fi

# (5b) standalone reason does NOT include orchestrator prefix
if [[ "$case5_stdout" != *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 5b: standalone reason does NOT include orchestrator prefix (distinguishable)"
else
    assert_fails "Case 5b: standalone leaked orchestrator prefix"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Iter-84 PreToolUse Edit-Time Orchestrator — Regression Test Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
