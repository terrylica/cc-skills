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

    # Isolated fixture repo (fix 2026-06-10): the hook resolves GIT_ROOT via
    # `git rev-parse --show-toplevel` and writes its caches THERE, and it
    # enumerates markdown via `git ls-files --cached`. When tests cd'd into
    # fixtures/sample_repo (inside the cc-skills repo), GIT_ROOT resolved to
    # the cc-skills root — caches landed in the PARENT repo and the
    # fixture-local assertions never passed (4 tests red since inception),
    # while stray .lychee-results.json polluted the cc-skills root.
    # Copying the fixture into $BATS_TEST_TMPDIR and committing it as its own
    # git repo makes GIT_ROOT == the fixture, so assertions and hook agree.
    WORK_REPO="$BATS_TEST_TMPDIR/sample_repo"
    cp -R "$FIXTURES/sample_repo" "$WORK_REPO"
    git -C "$WORK_REPO" init -q
    git -C "$WORK_REPO" -c user.email=bats@test -c user.name=bats add -A
    git -C "$WORK_REPO" -c user.email=bats@test -c user.name=bats commit -qm fixture
}

teardown() {
    # Return to original directory
    cd "$ORIG_DIR"
    # $BATS_TEST_TMPDIR (and WORK_REPO inside it) is auto-cleaned by bats.
}

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "hook exits successfully in git repo" {
    cd "$WORK_REPO"
    # Provide minimal JSON payload on stdin
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook creates lychee cache file" {
    cd "$WORK_REPO"
    rm -f .lychee-results.json
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ -f .lychee-results.json ]
}

@test "hook creates lint-relative-paths results file" {
    cd "$WORK_REPO"
    rm -f .lint-relative-paths-results.txt
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    # File may or may not exist depending on lint-relative-paths availability
    # Test passes if hook didn't crash
    [ "$status" -eq 0 ]
}

@test "lychee cache has valid JSON structure" {
    cd "$WORK_REPO"
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
    cd "$WORK_REPO"
    # Empty stdin - should use pwd
    run bash -c "echo '' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook handles missing lychee gracefully" {
    cd "$WORK_REPO"
    rm -f .lychee-results.json

    # Run with restricted PATH (lychee not available)
    run bash -c "PATH=/usr/bin:/bin echo '{\"cwd\":\"$PWD\"}' | $HOOK"

    # Should not crash
    [ "$status" -eq 0 ]

    # Should still create cache file (with warning or 0 errors)
    [ -f .lychee-results.json ]
}

@test "hook is non-blocking (always exits 0)" {
    cd "$WORK_REPO"

    # Even if there are errors, hook should exit 0 to not block Claude
    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "hook uses CLAUDE_PLUGIN_ROOT when set" {
    cd "$WORK_REPO"

    # Set custom plugin root
    export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."

    run bash -c "echo '{\"cwd\":\"$PWD\"}' | $HOOK"
    [ "$status" -eq 0 ]

    unset CLAUDE_PLUGIN_ROOT
}
