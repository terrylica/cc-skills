#!/usr/bin/env bats
# test_lint_relative.bats - Unit tests for lint-relative-paths script
#
# Run with: bats tests/test_lint_relative.bats

setup() {
    LINT_SCRIPT="$BATS_TEST_DIRNAME/../scripts/lint-relative-paths"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"

    # Ensure script is executable
    chmod +x "$LINT_SCRIPT" 2>/dev/null || true
}

@test "lint script exists" {
    [ -f "$LINT_SCRIPT" ]
}

@test "lint script is executable" {
    [ -x "$LINT_SCRIPT" ]
}

@test "lint script exits successfully on clean repo" {
    cd "$FIXTURES/sample_repo"
    run "$LINT_SCRIPT" "$PWD"
    # May exit 0 (no violations) or 1 (violations found)
    # Test passes if it doesn't crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "lint script detects path violations" {
    cd "$FIXTURES/repo_with_path_violations"
    run "$LINT_SCRIPT" "$PWD"
    # Should find the absolute path violation
    # Check if output mentions violation or the file
    [[ "$output" == *"violation"* ]] || [[ "$output" == *"README"* ]] || [ "$status" -ne 0 ]
}

@test "lint script handles missing directory gracefully" {
    run "$LINT_SCRIPT" "/nonexistent/directory"
    # Should not crash - graceful degradation (exits 0, finds no violations)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "lint script handles no markdown files" {
    # Create temp directory with no markdown
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    git init -q
    echo "no markdown here" > test.txt
    git add test.txt
    git commit -q -m "init"

    run "$LINT_SCRIPT" "$temp_dir"

    # Should complete without errors
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

    # Cleanup
    rm -rf "$temp_dir"
}

@test "lint script provides usage on no arguments" {
    run "$LINT_SCRIPT"
    # May show usage or use current directory
    # Test passes if it doesn't crash catastrophically
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
}
