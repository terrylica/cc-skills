#!/usr/bin/env bats
# test_posttooluseerror_handler.bats - Tests for PostToolUseError handler
#
# Run with: bats plugins/itp-hooks/tests/test_posttooluseerror_handler.bats
#
# PostToolUseError fires when Bash commands FAIL (non-zero exit).
# PostToolUse does NOT fire for failed commands - this is Claude Code behavior.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../hooks/posttooluseerror-handler.sh"
    chmod +x "$HOOK"
}

# =============================================================================
# BASIC TESTS
# =============================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "hook exits 0 with empty input" {
    run bash -c "echo '' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook ignores non-Bash errors" {
    INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/test"},"error":{"exit_code":1}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"UV-REMINDER"* ]]
}

# =============================================================================
# UV REMINDER TESTS
# =============================================================================

@test "detects pip install failure and suggests uv" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"pip install requests"},"error":{"type":"ProcessError","exit_code":1,"stderr":"error occurred"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UV-REMINDER"* ]]
    [[ "$output" == *"uv add"* ]]
}

@test "detects pip3 install failure" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"pip3 install numpy"},"error":{"type":"ProcessError","exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UV-REMINDER"* ]]
}

@test "detects pip in ssh command" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"ssh server \"pip3 install pyarrow\""},"error":{"type":"ProcessError","exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UV-REMINDER"* ]]
}

@test "detects PEP 668 externally-managed error" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"pip3 install pkg"},"error":{"type":"ProcessError","exit_code":1,"stderr":"error: externally-managed-environment"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PEP 668"* ]]
    [[ "$output" == *"externally managed"* ]]
}

@test "ignores uv commands (already using uv)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"uv pip install requests"},"error":{"type":"ProcessError","exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"UV-REMINDER"* ]]
}

@test "ignores pip freeze (lock file operation)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"pip freeze > requirements.txt"},"error":{"type":"ProcessError","exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"UV-REMINDER"* ]]
}

# =============================================================================
# SILENT FAILURE GUIDANCE
# =============================================================================

@test "provides error guidance for non-pip failures" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"npm run build"},"error":{"type":"ProcessError","exit_code":1,"stderr":"Build failed"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BASH-ERROR"* ]]
    [[ "$output" == *"Build failed"* ]]
}

@test "truncates long stderr" {
    LONG_STDERR=$(printf 'x%.0s' {1..600})
    INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"fail\"},\"error\":{\"type\":\"ProcessError\",\"exit_code\":1,\"stderr\":\"$LONG_STDERR\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"..."* ]]
}

# =============================================================================
# JSON OUTPUT FORMAT
# =============================================================================

@test "outputs valid JSON with decision:block" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"pip install x"},"error":{"type":"ProcessError","exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision' >/dev/null 2>&1
    [[ "$output" == *'"block"'* ]]
}

@test "always exits 0 (non-blocking)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"any command"},"error":{"type":"ProcessError","exit_code":127,"stderr":"not found"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
}
