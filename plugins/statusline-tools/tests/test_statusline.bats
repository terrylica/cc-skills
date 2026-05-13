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

@test "statusline shows repo path and remote URL" {
    cd "$FIXTURES/sample_repo"
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sample_repo"* ]]
    [[ "$output" == *"https://github.com/"* ]]
}

@test "statusline handles missing lychee cache gracefully" {
    cd "$FIXTURES/sample_repo"
    rm -f .lychee-results.json 2>/dev/null || true
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"jq:"* ]]
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
    [[ "$output" != *"jq:"* ]]
    rm -f .lychee-results.json
}

@test "statusline handles non-git directory" {
    cd /tmp
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    # Should show some output, possibly "no git" indicator
}

@test "statusline handles missing path lint cache gracefully" {
    cd "$FIXTURES/sample_repo"
    rm -f .lint-relative-paths-results.txt 2>/dev/null || true
    run bash -c "echo '$TEST_INPUT' | $STATUSLINE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"jq:"* ]]
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

@test "statusline detects bearer-mode pin and renders pin scope badge" {
    # Post-rewrite design (2026-05-13):
    #   - Drops the "[5th-fleet]" badge entirely (fleet terminology retired).
    #   - Drops rendering of the bearer credential NAME (operationally
    #     uninteresting since doorward picks the upstream account per-request).
    #   - Pin scope+mode badge is preserved — operator still needs to see
    #     which scope (session/repo/device) is overriding default rotation.
    #   - Bearer-mode detection still gates whether the doorward block renders
    #     (presence of the block implies bearer-mode routing).
    tmp_home="$(mktemp -d)"
    mkdir -p "$tmp_home/.claude/plugins/marketplaces/ccmax/hooks"
    cat > "$tmp_home/.claude/plugins/marketplaces/ccmax/hooks/pin-helper.sh" <<'EOF'
ccmax_resolve_layered_pin_with_account_mode() {
    printf 'el02-doorward-bearer-api-1|soft|repo|bearer_key_anthropic_compatible_api_mode\n'
}
EOF

    cd "$FIXTURES/sample_repo"
    run env HOME="$tmp_home" bash -c "echo '$TEST_INPUT' | '$STATUSLINE'"
    rm -rf "$tmp_home"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[repo:soft]"* ]]
    # Retired markers — must NOT appear under the post-rewrite design.
    [[ "$output" != *"[5th-fleet]"* ]]
    [[ "$output" != *"el02-doorward-bearer-api-1"* ]]
}

@test "statusline detects inherited bearer-key env without crashing" {
    # When no local pin-helper exists but the operator has
    # CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION exported (legacy
    # env-based bearer activation), the statusline must still:
    #   - exit 0 (no crash from missing helper)
    #   - NOT leak the bearer credential name into render output
    #   - NOT render the retired [5th-fleet] marker
    # Whether the doorward block renders depends on live reachability, which
    # we can't fake here — so we don't assert on it.
    tmp_home="$(mktemp -d)"
    mkdir -p "$tmp_home/.claude"

    cd "$FIXTURES/sample_repo"
    run env HOME="$tmp_home" CCMAX_BEARER_PIN_ACCOUNT_NAME_ACTIVE_FOR_THIS_SESSION="el02-doorward-bearer-api-1" \
        bash -c "echo '$TEST_INPUT' | '$STATUSLINE'"
    rm -rf "$tmp_home"

    [ "$status" -eq 0 ]
    [[ "$output" != *"el02-doorward-bearer-api-1"* ]]
    [[ "$output" != *"[5th-fleet]"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Antifragile probe invariant — discovered 2026-05-12 when ccmax-claude's
# bearer-pin CONNECT proxy on 127.0.0.1:<port> started 502'ing every CONNECT
# target it doesn't intercept (api.github.com etc.). Without `probe_direct`,
# the statusline's outbound gh/curl calls inherited the broken HTTPS_PROXY
# and the visibility badge permanently showed (?), the release lookup
# permanently showed `⌁ offline`, even though the network was fine.
#
# These three tests pin the fix so it cannot regress silently.
# ─────────────────────────────────────────────────────────────────────────────

@test "probe_direct strips HTTPS_PROXY/HTTP_PROXY/ALL_PROXY from subprocess" {
    # Extract the probe_direct definition from the live script, source it
    # into a poisoned-proxy subshell, and confirm zero proxy env vars
    # survive into the wrapped subprocess.
    helper_body=$(sed -n '/^probe_direct() {/,/^}/p' "$STATUSLINE")
    [ -n "$helper_body" ]  # guard: definition extracted

    run env \
        HTTPS_PROXY=http://127.0.0.1:1 \
        HTTP_PROXY=http://127.0.0.1:1 \
        ALL_PROXY=http://127.0.0.1:1 \
        https_proxy=http://127.0.0.1:1 \
        http_proxy=http://127.0.0.1:1 \
        all_proxy=http://127.0.0.1:1 \
        bash -c "${helper_body}"$'\n'"probe_direct env | grep -iE '^(https?|all)_proxy=' | wc -l | tr -d ' '"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]  # zero proxy env vars visible to the subprocess
}

@test "every outbound gh/curl call in custom-statusline.sh is wrapped with probe_direct" {
    # Lint: any line that runs `gh api`, `gh release`, `gh auth`, or `curl`
    # must contain `probe_direct` on the same line. Comments (`^\s*#`) are
    # excluded by the first grep. The second grep is allowed to "fail"
    # (exit 1 = zero violations = success) so we capture its output without
    # tripping bats's errexit; the violations check is on the captured text.
    violations=$(grep -nE '^[[:space:]]*[^#].*(\bgh[[:space:]]+(api|release|auth)\b|\bcurl[[:space:]])' \
        "$STATUSLINE" | grep -v 'probe_direct' || true)
    if [ -n "$violations" ]; then
        echo "Unwrapped outbound network call(s) found:" >&2
        echo "$violations" >&2
        echo "Wrap each with: probe_direct <command>" >&2
        return 1
    fi
}

@test "statusline survives broken HTTPS_PROXY in env (antifragile)" {
    # Inject an unreachable proxy on a deliberately closed port. With the fix
    # in place the statusline must still exit 0 and the visibility badge
    # must NOT be the red `(?)` fault marker (which would mean gh was still
    # being routed through the broken proxy).
    cd "$FIXTURES/sample_repo"
    run env \
        HTTPS_PROXY=http://127.0.0.1:1 \
        HTTP_PROXY=http://127.0.0.1:1 \
        ALL_PROXY=http://127.0.0.1:1 \
        https_proxy=http://127.0.0.1:1 \
        http_proxy=http://127.0.0.1:1 \
        all_proxy=http://127.0.0.1:1 \
        bash -c "echo '$TEST_INPUT' | '$STATUSLINE'"
    [ "$status" -eq 0 ]

    # Strip ANSI color codes for plain-text assertions.
    plain=$(printf '%s' "$output" | sed $'s/\x1b\\[[0-9;]*m//g')

    # The red `(?)` badge means gh's visibility query failed. With
    # probe_direct in place gh bypasses the broken proxy and returns
    # either `(private)` or `(public)` — anything but `(?)`.
    [[ "$plain" != *"(?)"* ]]
}
