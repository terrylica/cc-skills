#!/usr/bin/env bash
#MISE description="Iter-78 regression test for pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts. Synthesizes 7 PreToolUse stdin payloads covering every classification branch (allowlisted-Write, stripped-Write, same-line-escape, preceding-escape, short-reason-Write, MultiEdit, no-CLAUDE_PLUGIN_ROOT-keyword-fastpath) and asserts that the hook exits with the documented belt-and-suspenders defense (per GitHub issue #37210): exit code 2 + stdout permissionDecision deny + stderr diagnostic on violations; exit code 0 + stdout permissionDecision allow on clean payloads. Catches regressions in the edit-time gate BEFORE release publishes a tag that would allow an iter-76-class silent-failure bug to be introduced by a future edit."

# Iter-78 regression test for the edit-time L3-stripped-path PreToolUse hook.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts"

if [[ ! -f "$HOOK_PATH" ]]; then
    echo "FAIL: Hook not found at $HOOK_PATH"
    exit 1
fi

ASSERTION_COUNT_PASSED=0
ASSERTION_COUNT_FAILED=0

assert_equal_with_diagnostic() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ASSERTION_COUNT_PASSED=$((ASSERTION_COUNT_PASSED + 1))
    else
        echo "  ✗ $label"
        echo "      expected: [$expected]"
        echo "      actual:   [$actual]"
        ASSERTION_COUNT_FAILED=$((ASSERTION_COUNT_FAILED + 1))
    fi
}

# Invoke hook with given stdin payload; capture stdout, stderr, exit code.
# Returns three fields tab-separated: <exit-code>\t<has-deny-in-stdout>\t<has-blocked-in-stderr>
invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics() {
    local stdin_payload="$1"
    local stdout_text stderr_text exit_code
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    if echo "$stdin_payload" | bun "$HOOK_PATH" >"$stdout_file" 2>"$stderr_file"; then
        exit_code=0
    else
        exit_code=$?
    fi
    stdout_text=$(cat "$stdout_file")
    stderr_text=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"
    local has_deny_in_stdout="no"
    local has_blocked_in_stderr="no"
    if echo "$stdout_text" | grep -q '"permissionDecision":"deny"'; then
        has_deny_in_stdout="yes"
    fi
    if echo "$stdout_text" | grep -q '"permissionDecision":"allow"'; then
        has_deny_in_stdout="allow"
    fi
    if echo "$stderr_text" | grep -q "BLOCKED"; then
        has_blocked_in_stderr="yes"
    fi
    printf "%s\t%s\t%s" "$exit_code" "$has_deny_in_stdout" "$has_blocked_in_stderr"
}

echo "═══════════════════════════════════════════════════════════"
echo "  Iter-78 L3-Stripped-Path Edit-Time Guard — Regression Test"
echo "═══════════════════════════════════════════════════════════"

# Case 1: Write with ONLY allowlisted segments — must ALLOW
case1_payload=$(cat <<'EOF_CASE_1'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/case1.sh","content":"#!/bin/bash\nHELPER=\"${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh\"\nSKILL=\"${CLAUDE_PLUGIN_ROOT}/skills/foo/SKILL.md\"\nMANIFEST=\"${CLAUDE_PLUGIN_ROOT}/plugin.json\"\n"}}
EOF_CASE_1
)
result1=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case1_payload")
assert_equal_with_diagnostic "Case 1 (Write allowlisted only)" "0	allow	no" "$result1"

# Case 2: Write with STRIPPED segment (scripts/) and NO escape hatch — must DENY (belt-and-suspenders)
case2_payload=$(cat <<'EOF_CASE_2'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/case2.sh","content":"#!/bin/bash\nLIB=\"${CLAUDE_PLUGIN_ROOT}/scripts/helper.sh\"\nsource \"$LIB\"\n"}}
EOF_CASE_2
)
result2=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case2_payload")
assert_equal_with_diagnostic "Case 2 (Write stripped + no escape — belt-and-suspenders deny)" "2	yes	yes" "$result2"

# Case 3: Write with STRIPPED segment + valid SAME-LINE escape hatch — must ALLOW
case3_payload=$(cat <<'EOF_CASE_3'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/case3.sh","content":"#!/bin/bash\nDEV=\"${CLAUDE_PLUGIN_ROOT}/docs/notes.md\"  # LAYER3-STRIPPED-PATH-OK: dev-time L2 mirror probe only\n"}}
EOF_CASE_3
)
result3=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case3_payload")
assert_equal_with_diagnostic "Case 3 (Write stripped + same-line escape)" "0	allow	no" "$result3"

# Case 4: Write with STRIPPED segment + valid PRECEDING-LINE escape hatch (within 3 lines) — must ALLOW
case4_payload=$(cat <<'EOF_CASE_4'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/case4.sh","content":"#!/bin/bash\n# LAYER3-STRIPPED-PATH-OK: intentional dev-tooling escape hatch reason\nSCHEMA=\"${CLAUDE_PLUGIN_ROOT}/schemas/validation.json\"\n"}}
EOF_CASE_4
)
result4=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case4_payload")
assert_equal_with_diagnostic "Case 4 (Write stripped + preceding-line escape)" "0	allow	no" "$result4"

# Case 5: Write with STRIPPED segment + TOO-SHORT escape-hatch reason (< 10 chars) — must DENY
case5_payload=$(cat <<'EOF_CASE_5'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/case5.sh","content":"#!/bin/bash\nTEMPLATE=\"${CLAUDE_PLUGIN_ROOT}/templates/x.html\"  # LAYER3-STRIPPED-PATH-OK: ok\n"}}
EOF_CASE_5
)
result5=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case5_payload")
assert_equal_with_diagnostic "Case 5 (Write stripped + too-short reason — still deny)" "2	yes	yes" "$result5"

# Case 6: MultiEdit with one edit containing STRIPPED segment — must DENY
case6_payload=$(cat <<'EOF_CASE_6'
{"tool_name":"MultiEdit","tool_input":{"file_path":"/tmp/case6.sh","edits":[{"old_string":"x","new_string":"HELPER=\"${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh\""},{"old_string":"y","new_string":"CFG=\"${CLAUDE_PLUGIN_ROOT}/config/foo.toml\""}]}}
EOF_CASE_6
)
result6=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case6_payload")
assert_equal_with_diagnostic "Case 6 (MultiEdit with one stripped reference)" "2	yes	yes" "$result6"

# Case 7: Write with content that contains NO CLAUDE_PLUGIN_ROOT keyword — pre-JSON-parse fastpath bails to ALLOW
case7_payload=$(cat <<'EOF_CASE_7'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/case7.txt","content":"plain text, no plugin references at all"}}
EOF_CASE_7
)
result7=$(invoke_hook_and_classify_response_with_belt_and_suspenders_diagnostics "$case7_payload")
assert_equal_with_diagnostic "Case 7 (Write — no plugin-root keyword, fastpath bail)" "0	allow	no" "$result7"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Iter-78 regression test results"
echo "═══════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
