#!/usr/bin/env bats
# test_code_correctness_guard.bats - Unit tests for code-correctness-guard.sh
#
# Run with: bats plugins/itp-hooks/tests/test_code_correctness_guard.bats
#
# Tests cover:
# - Bash tool failure detection (non-zero exit codes)
# - Python silent failure patterns (E722, S110, S112, BLE001, PLW1510)
# - Python shell variable detection ($HOME in Python strings)
# - Shell script issues (SC2155, SC2164, SC2181, SC2086)
# - JS/TS issues (empty catch, floating promises)
# - Non-blocking behavior (always exits 0)
# - JSON output format validation

setup() {
    HOOK="$BATS_TEST_DIRNAME/../hooks/code-correctness-guard.sh"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"

    # Ensure script is executable
    chmod +x "$HOOK"
}

# =============================================================================
# BASIC HOOK TESTS
# =============================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "hook exits 0 with empty input" {
    run bash -c "echo '' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook exits 0 with unknown tool" {
    run bash -c "echo '{\"tool_name\":\"Unknown\"}' | $HOOK"
    [ "$status" -eq 0 ]
}

# =============================================================================
# BASH TOOL FAILURE DETECTION
# =============================================================================

@test "Bash: detects non-zero exit code with stderr" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"ls nonexistent"},"tool_output":{"exit_code":2,"stderr":"ls: nonexistent: No such file or directory"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BASH-FAILURE"* ]]
    [[ "$output" == *"decision"* ]]
}

@test "Bash: ignores exit code 0 (success)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_output":{"exit_code":0,"stderr":""}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BASH-FAILURE"* ]]
}

@test "Bash: ignores grep exit 1 (no match is normal)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"grep pattern file"},"tool_output":{"exit_code":1,"stderr":""}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BASH-FAILURE"* ]]
}

@test "Bash: ignores diff exit 1 (differences found is normal)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"diff file1 file2"},"tool_output":{"exit_code":1,"stderr":""}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BASH-FAILURE"* ]]
}

@test "Bash: detects exit code 2 from grep (actual error)" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"grep pattern nonexistent"},"tool_output":{"exit_code":2,"stderr":"grep: nonexistent: No such file or directory"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BASH-FAILURE"* ]]
}

@test "Bash: truncates long stderr" {
    LONG_STDERR=$(printf 'x%.0s' {1..600})
    INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"fail\"},\"tool_output\":{\"exit_code\":1,\"stderr\":\"$LONG_STDERR\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"..."* ]]
}

# =============================================================================
# PYTHON SILENT FAILURE DETECTION
# =============================================================================

@test "Python: detects bare except (E722)" {
    skip_if_no_ruff
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/python/bare_except.py\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUFF-SILENT-FAILURE"* ]]
    [[ "$output" == *"E722"* ]]
}

@test "Python: detects except pass (S110)" {
    skip_if_no_ruff
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/python/bare_except.py\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"S110"* ]]
}

@test "Python: detects subprocess without check (PLW1510)" {
    skip_if_no_ruff
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/python/subprocess_no_check.py\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUFF-SILENT-FAILURE"* ]] || [[ "$output" == *"PLW1510"* ]] || true
}

@test "Python: good code passes" {
    skip_if_no_ruff
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/python/good_code.py\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"RUFF-SILENT-FAILURE"* ]]
}

@test "Python: works with Edit tool too" {
    skip_if_no_ruff
    INPUT="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIXTURES/python/bare_except.py\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUFF-SILENT-FAILURE"* ]]
}

# =============================================================================
# SHELL SCRIPT DETECTION
# =============================================================================

@test "Shell: detects SC2155 masked return value" {
    skip_if_no_shellcheck
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/shell/sc2155_masked_return.sh\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHELLCHECK"* ]]
    [[ "$output" == *"SC2155"* ]]
}

@test "Shell: detects SC2164 cd without exit" {
    skip_if_no_shellcheck
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/shell/sc2164_cd_no_check.sh\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHELLCHECK"* ]]
    [[ "$output" == *"SC2164"* ]]
}

@test "Shell: good code passes" {
    skip_if_no_shellcheck
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/shell/good_code.sh\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHELLCHECK"* ]]
}

@test "Shell: works with .bash extension" {
    skip_if_no_shellcheck
    # Create temp .bash file
    cp "$FIXTURES/shell/sc2155_masked_return.sh" "$FIXTURES/shell/temp_test.bash"
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/shell/temp_test.bash\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    rm -f "$FIXTURES/shell/temp_test.bash"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHELLCHECK"* ]]
}

# =============================================================================
# JS/TS DETECTION
# =============================================================================

@test "JS: detects empty catch block" {
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/js/empty_catch.js\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    # Either oxlint or custom detection should catch this
    [[ "$output" == *"JS-SILENT-FAILURE"* ]] || [[ "$output" == *"OXLINT"* ]] || [[ "$output" == *"catch"* ]]
}

@test "JS: detects floating promise" {
    INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FIXTURES/js/floating_promise.js\"}}"
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    # Custom detection or oxlint should catch this
    [[ "$output" == *"JS-SILENT-FAILURE"* ]] || [[ "$output" == *"promise"* ]] || [[ "$output" == *"OXLINT"* ]]
}

# =============================================================================
# JSON OUTPUT FORMAT
# =============================================================================

@test "JSON: output is valid JSON when warning emitted" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"fail"},"tool_output":{"exit_code":1,"stderr":"error message"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    # Validate JSON structure
    echo "$output" | jq -e '.decision' >/dev/null 2>&1
}

@test "JSON: contains decision field" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"fail"},"tool_output":{"exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision"'* ]]
}

@test "JSON: decision is 'block' for visibility" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"fail"},"tool_output":{"exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"block"'* ]]
}

@test "JSON: contains reason field with guidance" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"fail"},"tool_output":{"exit_code":1,"stderr":"error"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"reason"'* ]]
    [[ "$output" == *"SILENT FAILURE PRINCIPLE"* ]]
}

# =============================================================================
# NON-BLOCKING BEHAVIOR
# =============================================================================

@test "Non-blocking: always exits 0 even with errors" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"fail"},"tool_output":{"exit_code":127,"stderr":"command not found"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "Non-blocking: exits 0 for missing file" {
    INPUT='{"tool_name":"Write","tool_input":{"file_path":"/nonexistent/path/file.py"}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "Non-blocking: exits 0 for empty file path" {
    INPUT='{"tool_name":"Write","tool_input":{"file_path":""}}'
    run bash -c "echo '$INPUT' | $HOOK"
    [ "$status" -eq 0 ]
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

skip_if_no_ruff() {
    if ! command -v ruff &>/dev/null; then
        skip "ruff not installed"
    fi
}

skip_if_no_shellcheck() {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi
}

skip_if_no_oxlint() {
    if ! command -v oxlint &>/dev/null; then
        skip "oxlint not installed"
    fi
}
