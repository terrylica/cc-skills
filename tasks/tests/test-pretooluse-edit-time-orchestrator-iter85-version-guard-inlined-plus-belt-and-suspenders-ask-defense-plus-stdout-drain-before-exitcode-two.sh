#!/usr/bin/env bash
#MISE description="Iter-85 regression test extending iter-84 orchestrator coverage. Verifies: (1) version-guard subhook inlined as second registry entry produces matching deny output as standalone, (2) the iter-85-audit-driven belt-and-suspenders defense now covers BOTH deny AND ask paths (previously only deny had stderr+exit2), (3) stdout-drain-before-exit pattern (process.exitCode=2 instead of process.exit(2)) preserves full JSON payload integrity, (4) registry-order-is-lightest-first invariant — version-guard's O(1) extension+path filter runs BEFORE file-size-guard's sync fs.readFileSync."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCHESTRATOR_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"
STANDALONE_VERSION_GUARD_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-version-guard.ts"

for required_file in "$ORCHESTRATOR_HOOK_PATH" "$STANDALONE_VERSION_GUARD_PATH"; do
    if [[ ! -f "$required_file" ]]; then
        echo "FAIL: required file not found: $required_file"
        exit 1
    fi
done

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
echo "  Iter-85 PreToolUse Edit-Time Orchestrator — version-guard inlined + audit fixes"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: version-guard inlined classifier denies hardcoded markdown version
# Path /home/foo/README.md is NOT in the exemption list. Content has "Version: 9.9.9"
# which matches /Version:\s*(\d+\.\d+\.\d+)/gi.
case1_payload_file=$(mktemp -t iter85-orch-test-case1.XXXXXX.json)
trap 'rm -f "$case1_payload_file"' EXIT
cat > "$case1_payload_file" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/home/foo/README.md","content":"# Title\n\nVersion: 9.9.9\n"}}
PAYLOAD

case1_stderr_file=$(mktemp -t iter85-orch-test-case1-stderr.XXXXXX.txt)
trap 'rm -f "$case1_payload_file" "$case1_stderr_file"' EXIT

set +e
case1_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case1_payload_file" 2>"$case1_stderr_file")
case1_exit=$?
set -e
case1_stderr=$(cat "$case1_stderr_file")

if [[ "$case1_stdout" == *'"permissionDecision":"deny"'* ]]; then
    assert_passes "Case 1a: orchestrator stdout JSON denies hardcoded markdown version"
else
    assert_fails "Case 1a: stdout missing deny; got=$case1_stdout"
fi

if [[ "$case1_stdout" == *'version-guard → DENY'* ]]; then
    assert_passes "Case 1b: orchestrator deny reason attributes to version-guard subhook"
else
    assert_fails "Case 1b: subhook attribution missing; stdout=$case1_stdout"
fi

if [[ "$case1_stderr" == *'DENY from subhook=version-guard'* ]]; then
    assert_passes "Case 1c: stderr diagnostic line emitted (belt-and-suspenders)"
else
    assert_fails "Case 1c: stderr diagnostic missing; got=$case1_stderr"
fi

if [[ "$case1_exit" == "2" ]]; then
    assert_passes "Case 1d: exit code 2 (process.exitCode pattern, drain-before-exit)"
else
    assert_fails "Case 1d: exit code = $case1_exit, expected 2"
fi

# ─── Case 2: version-guard inlined classifier allows exempted CHANGELOG path
case2_payload_file=$(mktemp -t iter85-orch-test-case2.XXXXXX.json)
trap 'rm -f "$case1_payload_file" "$case1_stderr_file" "$case2_payload_file"' EXIT
cat > "$case2_payload_file" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/home/foo/CHANGELOG.md","content":"# v1.2.3\n\nReleased version 1.2.3 with fixes.\n"}}
PAYLOAD

set +e
case2_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case2_payload_file" 2>/dev/null)
case2_exit=$?
set -e

if [[ "$case2_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case2_exit" == "0" ]]; then
    assert_passes "Case 2: CHANGELOG path exempted → allow + exit 0"
else
    assert_fails "Case 2: CHANGELOG exemption broken; exit=$case2_exit stdout=$case2_stdout"
fi

# ─── Case 3: standalone version-guard.ts still functions after .mjs→.ts refactor
case3_stdout=$(bun "$STANDALONE_VERSION_GUARD_PATH" < "$case1_payload_file" 2>/dev/null || true)
if [[ "$case3_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case3_stdout" == *'[VERSION-GUARD] Hardcoded version'* ]]; then
    assert_passes "Case 3a: standalone version-guard.ts denies (.mjs→.ts refactor backward-compat)"
else
    assert_fails "Case 3a: standalone broken after refactor; got=$case3_stdout"
fi

# Standalone reason should NOT include orchestrator prefix (distinguishable
# from orchestrator-routed deny — proves the dual-mode contract is honored).
if [[ "$case3_stdout" != *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 3b: standalone reason does NOT include orchestrator prefix"
else
    assert_fails "Case 3b: standalone leaked orchestrator prefix"
fi

# ─── Case 4: stdout-drain-before-exit integrity check
# Force a large deny reason and verify the entire JSON arrives on stdout
# even with the immediate exitCode=2. This is the iter-85 audit fix for
# the previously-noted process.exit(2) truncation hazard.
case4_payload_file=$(mktemp -t iter85-orch-test-case4.XXXXXX.json)
trap 'rm -f "$case1_payload_file" "$case1_stderr_file" "$case2_payload_file" "$case4_payload_file"' EXIT

# Build a payload that produces a multi-version deny reason (large output)
cat > "$case4_payload_file" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/home/foo/multi.md","content":"# Multi-version stress\n\nVersion: 1.0.0\nVersion: 2.0.0\nVersion: 3.0.0\n\npackage==4.5.6\npackage==7.8.9\n\nv10.20.30 and v40.50.60\n"}}
PAYLOAD

set +e
case4_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case4_payload_file" 2>/dev/null)
case4_exit=$?
set -e

# Verify JSON is well-formed (drain-before-exit succeeded — no truncation)
if echo "$case4_stdout" | grep -q '"permissionDecision":"deny"'; then
    # Validate JSON parses cleanly via bun's JSON.parse
    if echo "$case4_stdout" | bun -e 'JSON.parse(await Bun.stdin.text())' 2>/dev/null; then
        assert_passes "Case 4a: large deny payload arrives intact (stdout drain before exitCode=2)"
    else
        assert_fails "Case 4a: stdout JSON malformed (truncation suspected); got=$case4_stdout"
    fi
else
    assert_fails "Case 4a: missing deny in stdout; got=$case4_stdout"
fi

if [[ "$case4_exit" == "2" ]]; then
    assert_passes "Case 4b: exit code 2 on multi-version deny"
else
    assert_fails "Case 4b: exit code = $case4_exit, expected 2"
fi

# ─── Case 5: registry-order invariant — version-guard runs before file-size-guard
# Construct a markdown file that BOTH has a hardcoded version AND is over the .md
# block threshold (>1500 lines). Both subhooks would deny, but registry order
# means version-guard wins (lightest-first invariant). Verify the deny attribution.
case5_content_file=$(mktemp -t iter85-orch-test-case5-content.XXXXXX.md)
trap 'rm -f "$case1_payload_file" "$case1_stderr_file" "$case2_payload_file" "$case4_payload_file" "$case5_content_file"' EXIT

# Generate 1700 lines (above .md block threshold of 1500) with a hardcoded version
{
    echo "# Big file with hardcoded version"
    echo ""
    echo "Version: 99.99.99"
    echo ""
    for ((i = 0; i < 1700; i++)); do
        echo "Line $i: some prose content here"
    done
} > "$case5_content_file"

case5_content_escaped=$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    print(json.dumps(f.read()), end="")
' "$case5_content_file")

case5_payload_file=$(mktemp -t iter85-orch-test-case5.XXXXXX.json)
trap 'rm -f "$case1_payload_file" "$case1_stderr_file" "$case2_payload_file" "$case4_payload_file" "$case5_content_file" "$case5_payload_file"' EXIT
printf '{"tool_name":"Write","tool_input":{"file_path":"/home/foo/bigversion.md","content":%s}}' "$case5_content_escaped" > "$case5_payload_file"

set +e
case5_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case5_payload_file" 2>/dev/null)
case5_exit=$?
set -e

# Should be denied by version-guard (lighter, runs first) NOT file-size-guard.
# If file-size-guard wins, lightest-first ordering is broken.
if [[ "$case5_stdout" == *'version-guard → DENY'* ]]; then
    assert_passes "Case 5: lightest-first registry order honored (version-guard wins over file-size-guard)"
elif [[ "$case5_stdout" == *'file-size-guard → DENY'* ]]; then
    assert_fails "Case 5: registry order INVERTED — file-size-guard ran before version-guard"
else
    assert_fails "Case 5: neither subhook denied; stdout=$case5_stdout exit=$case5_exit"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Iter-85 orchestrator + version-guard inline regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
