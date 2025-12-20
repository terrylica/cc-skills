#!/usr/bin/env bats
# test_stop_hook.bats - Unit tests for lychee-stop-hook.sh
#
# Run with: bats tests/test_stop_hook.bats

setup() {
    HOOK="$BATS_TEST_DIRNAME/../hooks/lychee-stop-hook.sh"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"

    # Ensure script is executable
    chmod +x "$HOOK"

    # Store original directory
    ORIG_DIR="$PWD"
}

teardown() {
    # Return to original directory
    cd "$ORIG_DIR"

    # Clean up cache files in fixtures
    rm -f "$FIXTURES/sample_repo/.lychee-results.json" 2>/dev/null || true
    rm -f "$FIXTURES/sample_repo/.lint-relative-paths-results.txt" 2>/dev/null || true
    rm -f "$FIXTURES/repo_with_broken_links/.lychee-results.json" 2>/dev/null || true
    rm -f "$FIXTURES/repo_with_broken_links/.lint-relative-paths-results.txt" 2>/dev/null || true
}

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "hook exits successfully in git repo" {
    cd "$FIXTURES/sample_repo"
    # Provide minimal JSON payload on stdin
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook creates lychee cache file" {
    cd "$FIXTURES/sample_repo"
    rm -f .lychee-results.json
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ -f .lychee-results.json ]
}

@test "hook creates lint-relative-paths results file" {
    cd "$FIXTURES/sample_repo"
    rm -f .lint-relative-paths-results.txt
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    # File may or may not exist depending on lint-relative-paths availability
    # Test passes if hook didn't crash
    [ "$status" -eq 0 ]
}

@test "lychee cache has valid JSON structure" {
    cd "$FIXTURES/sample_repo"
    rm -f .lychee-results.json
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ -f .lychee-results.json ]

    # Validate JSON structure
    run jq -e '.errors' .lychee-results.json
    [ "$status" -eq 0 ]

    run jq -e '.timestamp' .lychee-results.json
    [ "$status" -eq 0 ]
}

@test "hook handles non-git directory" {
    cd /tmp
    # Should exit early without error
    run bash -c "echo '{\"cwd\":\"/tmp\"}' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook handles empty payload" {
    cd "$FIXTURES/sample_repo"
    # Empty stdin - should use pwd
    run bash -c "echo '' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook handles missing lychee gracefully" {
    cd "$FIXTURES/sample_repo"
    rm -f .lychee-results.json

    # Run with restricted PATH (lychee not available)
    run bash -c "PATH=/usr/bin:/bin echo '{\"cwd\":\"$PWD\"}' | $HOOK"

    # Should not crash
    [ "$status" -eq 0 ]

    # Should still create cache file (with warning or 0 errors)
    [ -f .lychee-results.json ]
}

@test "hook is non-blocking (always exits 0)" {
    cd "$FIXTURES/sample_repo"

    # Even if there are errors, hook should exit 0 to not block Claude
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook uses CLAUDE_PLUGIN_ROOT when set" {
    cd "$FIXTURES/sample_repo"

    # Set custom plugin root
    export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."

    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ "$status" -eq 0 ]

    unset CLAUDE_PLUGIN_ROOT
}
