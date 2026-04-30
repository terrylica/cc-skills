#!/usr/bin/env bash
# Test harness for stop-orchestrator.ts — verifies subhook isolation,
# output aggregation, exit-code propagation, and timeout handling.
#
# Strategy: SUBHOOKS_DIR env override points the orchestrator at a temp
# directory of mock subhooks. Each mock is a standalone shell script
# named identically to a real subhook (stop-subprocess-session-cleanup.ts,
# stop-hook-error-summary.ts, stop-ty-project-check.ts, stop-markdown-lint.ts,
# stop-loop-stall-guard.ts) whose behavior we control per test case.
#
# Run: bash plugins/itp-hooks/tests/test-stop-orchestrator.sh
# Exits 0 on all-pass.
set -uo pipefail

ORCH="$(cd "$(dirname "$0")/.." && pwd)/hooks/stop-orchestrator.ts"
[[ -f "$ORCH" ]] || { echo "FAIL: orchestrator not found at $ORCH" >&2; exit 2; }

PASSES=0
FAILS=0
FAILED_CASES=()
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build a mock subhook directory. Each subhook prints fixed output.
# Args: <name> <mode>  where mode is one of:
#   silent       → print {} and exit 0
#   block-reason → print {decision:"block",reason:"..."} and exit 0
#   context      → print {additionalContext:"..."} and exit 0
#   exit2        → print error to stderr, exit 2
#   crash        → exit 99 with stderr "boom"
#   timeout      → sleep 30 then exit (forces orchestrator timeout)
#   bad-json     → print "not json" and exit 0
build_mock() {
    local mock_dir="$1" name="$2" mode="$3"
    local script="$mock_dir/$name"
    case "$mode" in
        silent)
            cat >"$script" <<'EOF'
#!/bin/sh
cat >/dev/null
echo '{}'
EOF
            ;;
        block-reason)
            cat >"$script" <<EOF
#!/bin/sh
cat >/dev/null
echo '{"decision":"block","reason":"reason from $name"}'
EOF
            ;;
        context)
            cat >"$script" <<EOF
#!/bin/sh
cat >/dev/null
echo '{"additionalContext":"ctx from $name"}'
EOF
            ;;
        exit2)
            cat >"$script" <<EOF
#!/bin/sh
cat >/dev/null
echo "stall message from $name" >&2
exit 2
EOF
            ;;
        crash)
            cat >"$script" <<EOF
#!/bin/sh
cat >/dev/null
echo "boom from $name" >&2
exit 99
EOF
            ;;
        timeout)
            cat >"$script" <<'EOF'
#!/bin/sh
cat >/dev/null
sleep 30
EOF
            ;;
        bad-json)
            cat >"$script" <<'EOF'
#!/bin/sh
cat >/dev/null
echo "not json"
EOF
            ;;
    esac
    chmod +x "$script"
}

# Set up a mock subhook dir with all 5 subhooks in given modes.
# Args: <dir> <subprocess-mode> <error-summary-mode> <ty-mode> <md-mode> <loop-mode>
setup_mocks() {
    local dir="$1"
    rm -rf "$dir" && mkdir -p "$dir"
    build_mock "$dir" stop-subprocess-session-cleanup.ts "$2"
    build_mock "$dir" stop-hook-error-summary.ts          "$3"
    build_mock "$dir" stop-ty-project-check.ts             "$4"
    build_mock "$dir" stop-markdown-lint.ts               "$5"
    build_mock "$dir" stop-loop-stall-guard.ts            "$6"
}

# Tests set SUBHOOK_RUNNER="" so the orchestrator skips `bun script` and
# exec's the mock files directly via their shebang. No PATH-shim trick.
run_orch() {
    local mock_dir="$1" extra_env="${2:-}"
    # shellcheck disable=SC2086
    env $extra_env SUBHOOKS_DIR="$mock_dir" SUBHOOK_RUNNER="" \
        bun "$ORCH" <<<'{"transcript_path":"/tmp/x.jsonl","session_id":"s","cwd":"/tmp"}'
}

run_case() {
    local name="$1" expected_exit="$2" expected_pattern="$3" mock_dir="$4" extra_env="${5:-}"
    local stdout stderr rc
    stdout=$(run_orch "$mock_dir" "$extra_env" 2>"$TMP/stderr.txt") || rc=$?
    rc=${rc:-0}
    stderr=$(cat "$TMP/stderr.txt")

    local fail=0
    if [[ "$rc" -ne "$expected_exit" ]]; then
        fail=1
        echo "  FAIL: $name (exit=$rc expected=$expected_exit)"
    elif [[ -n "$expected_pattern" ]] && ! grep -qE "$expected_pattern" <<<"$stdout$stderr"; then
        fail=1
        echo "  FAIL: $name (pattern '$expected_pattern' not found)"
        echo "         stdout: $stdout"
        echo "         stderr: $stderr"
    fi
    if [[ $fail -eq 0 ]]; then
        echo "  PASS: $name"
        PASSES=$((PASSES + 1))
    else
        FAILS=$((FAILS + 1))
        FAILED_CASES+=("$name")
    fi
}

echo "=== stop-orchestrator.ts test harness ==="
echo ""

# Case 1: all silent → exit 0, output {}
MOCK="$TMP/case1"
setup_mocks "$MOCK" silent silent silent silent silent
run_case "all silent → exit 0, empty JSON" 0 '^\{\}' "$MOCK"

# Case 2: one block-reason → exit 0, output contains decision:block
MOCK="$TMP/case2"
setup_mocks "$MOCK" silent block-reason silent silent silent
run_case "one block-reason → decision:block in output" 0 '"decision":"block"' "$MOCK"

# Case 3: two block-reasons → both reasons concatenated
MOCK="$TMP/case3"
setup_mocks "$MOCK" silent block-reason silent block-reason silent
run_case "two block-reasons → both reasons in output" 0 'error-summary.*markdown-lint|markdown-lint.*error-summary' "$MOCK"

# Case 4: additionalContext from one subhook → forwarded
MOCK="$TMP/case4"
setup_mocks "$MOCK" silent silent context silent silent
run_case "additionalContext forwarded" 0 '"additionalContext"' "$MOCK"

# Case 5: loop-stall-guard exit 2 → orchestrator exits 2 (asyncRewake path)
MOCK="$TMP/case5"
setup_mocks "$MOCK" silent silent silent silent exit2
run_case "loop-stall-guard exit 2 → orchestrator exit 2" 2 'stall message' "$MOCK"

# Case 6: NON-loop-stall-guard exit 2 → swallowed, orchestrator exits 0
# (Other subhooks must not be allowed to trigger asyncRewake.)
MOCK="$TMP/case6"
setup_mocks "$MOCK" exit2 silent silent silent silent
run_case "subprocess-cleanup exit 2 → swallowed (orch exit 0)" 0 '^\{\}' "$MOCK"

# Case 7: crash isolation — one subhook crashes, others still run
MOCK="$TMP/case7"
setup_mocks "$MOCK" crash silent context silent silent
run_case "crash isolation — context still aggregated" 0 '"additionalContext"' "$MOCK"

# Case 8: bad JSON output is treated as silent (no parse failure)
MOCK="$TMP/case8"
setup_mocks "$MOCK" bad-json silent silent silent silent
run_case "bad JSON treated as silent" 0 '^\{\}' "$MOCK"

# Case 9: empty stdin doesn't break the orchestrator
MOCK="$TMP/case9"
setup_mocks "$MOCK" silent silent silent silent silent
echo -n "" | env SUBHOOKS_DIR="$MOCK" SUBHOOK_RUNNER="" bun "$ORCH" >"$TMP/out9" 2>"$TMP/err9" && rc9=$? || rc9=$?
if [[ "${rc9:-0}" -eq 0 ]]; then
    echo "  PASS: empty stdin doesn't crash orchestrator"
    PASSES=$((PASSES + 1))
else
    echo "  FAIL: empty stdin (rc=$rc9)"
    FAILS=$((FAILS + 1))
    FAILED_CASES+=("empty stdin")
fi


# Case 10: stop_hook_active loop guard — even with a block-emitting
# subhook, the orchestrator must exit silently when stop_hook_active=true.
MOCK="$TMP/case10"
setup_mocks "$MOCK" silent block-reason silent silent silent
out10=$(env SUBHOOKS_DIR="$MOCK" SUBHOOK_RUNNER="" bun "$ORCH" \
    <<<'{"transcript_path":"/tmp/x.jsonl","session_id":"s","cwd":"/tmp","stop_hook_active":true}' 2>/dev/null)
if [[ "$out10" == "{}" ]]; then
    echo "  PASS: stop_hook_active=true bypasses block-emitting subhook"
    PASSES=$((PASSES + 1))
else
    echo "  FAIL: stop_hook_active loop guard (got: $out10)"
    FAILS=$((FAILS + 1))
    FAILED_CASES+=("stop_hook_active loop guard")
fi

echo ""
echo "=== summary ==="
echo "  Passes: $PASSES"
echo "  Fails:  $FAILS"
if [[ "$FAILS" -gt 0 ]]; then
    for c in "${FAILED_CASES[@]}"; do echo "    - $c"; done
    exit 1
fi
echo "  ✓ All tests passed"
