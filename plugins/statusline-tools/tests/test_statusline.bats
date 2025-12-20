#!/usr/bin/env bats
# test_statusline.bats - Unit tests for custom-statusline.sh
#
# Run with: bats tests/test_statusline.bats

setup() {
    STATUSLINE="$BATS_TEST_DIRNAME/../statusline/custom-statusline.sh"
    TEST_INPUT='{"model":{"name":"opus-4"},"session_id":"test123"}'
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"

    # Ensure script is executable
    chmod +x "$STATUSLINE"
}

@test "statusline script exists and is executable" {
    [ -x "$STATUSLINE" ]
}

@test "statusline handles valid JSON input" {
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Should not contain error messages
    [[ "$output" != *"error"* ]] || [[ "$output" != *"Error"* ]]
}

@test "statusline handles empty JSON input" {
    run bash -c "echo '{}' | $STATUSLINE"
    [ "$status" -eq 0 ]
}

@test "statusline handles minimal input" {
    run bash -c "echo '{\"model\":{}}' | $STATUSLINE"
    [ "$status" -eq 0 ]
}

@test "statusline shows git status indicators in git repo" {
    cd "$FIXTURES/sample_repo"
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Should contain at least one git status indicator (M, D, S, or U)
    [[ "$output" == *"M:"* ]] || [[ "$output" == *"U:"* ]] || [[ "$output" == *"S:"* ]] || [[ "$output" == *"D:"* ]]
}

@test "statusline shows branch name" {
    cd "$FIXTURES/sample_repo"
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Default branch should be main or master
    [[ "$output" == *"main"* ]] || [[ "$output" == *"master"* ]]
}

@test "statusline handles missing lychee cache gracefully" {
    cd "$FIXTURES/sample_repo"
    rm -f .lychee-results.json 2>/dev/null || true
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # L indicator should show 0 errors when no cache
    [[ "$output" == *"L:0"* ]]
}

@test "statusline handles corrupted lychee cache gracefully" {
    cd "$FIXTURES/sample_repo"
    echo "invalid json" > .lychee-results.json
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Should not crash
    rm -f .lychee-results.json
}

@test "statusline handles valid lychee cache" {
    cd "$FIXTURES/sample_repo"
    echo '{"errors": 3, "timestamp": "2025-01-01T00:00:00Z"}' > .lychee-results.json
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # L indicator should show the error count
    [[ "$output" == *"L:3"* ]]
    rm -f .lychee-results.json
}

@test "statusline handles non-git directory" {
    cd /tmp
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Should show some output, possibly "no git" indicator
}

@test "statusline shows path violations indicator" {
    cd "$FIXTURES/sample_repo"
    rm -f .lint-relative-paths-results.txt 2>/dev/null || true
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # P indicator should be present (may be 0)
    [[ "$output" == *"P:"* ]]
}

@test "statusline shows conflict indicator" {
    cd "$FIXTURES/sample_repo"
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Conflict indicator should be present (0 when no conflicts)
    [[ "$output" == *"⚠:"* ]] || [[ "$output" == *"⚠:0"* ]]
}

@test "statusline shows stash indicator" {
    cd "$FIXTURES/sample_repo"
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Stash indicator should be present
    [[ "$output" == *"≡:"* ]]
}
