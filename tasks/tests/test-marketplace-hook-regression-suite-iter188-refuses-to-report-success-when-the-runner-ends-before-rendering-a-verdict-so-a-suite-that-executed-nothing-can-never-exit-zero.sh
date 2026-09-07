#!/usr/bin/env bash
# Iter-188 regression test proving the marketplace hook regression suite can never again report SUCCESS while having executed nothing. Hermetic: copies the real runner into a mktemp sandbox holding two synthetic passing tests, then deliberately breaks it the way the incident broke it, so every assertion is against the actual runner source with no dependence on the real 114-test corpus and no recursion. Covers layer 1 (the runner's own bash -n self-check, which must read the DIAGNOSTIC TEXT because bash -n exits 0 for an unterminated heredoc), layer 2 (the EXIT-trap verdict sentinel, which is the load-bearing one and is asserted with layer 1 disabled so it cannot free-ride), the zero-discovery path, and the green control proving none of it fires on a healthy run.
#
# ─── WHY THIS TEST EXISTS ────────────────────────────────────────────────────
# Issue #113: the suite reported SUCCESS having run 0 of 113 discovered tests.
# An unterminated heredoc ended the script early, and bash treats that as a
# WARNING rather than an error — so the script exited 0, `set -euo pipefail`
# never fired, and moon printed `Tasks: 1 completed`. The 1058-byte log was the
# only evidence anything was wrong, and nothing was looking at its size.
#
# The class matters more than the instance. Any early termination — a truncated
# file, a stray `exit 0`, a killed subshell — produces the same silent green.
# So the fix is not "fix the heredoc"; it is a sentinel that refuses to let the
# process report success unless the run reached one of its own verdict lines.
#
# THE TRAP THAT MAKES IT WORK, and the trap that would undo it: bash runs EXIT
# traps even when it stops at EOF inside an open heredoc, which is why layer 2
# can catch its own cause of death. But bash keeps exactly ONE EXIT trap, so a
# later `trap 'rm -rf ...' EXIT` anywhere in the runner would silently REPLACE
# the sentinel with a cleanup handler that always exits 0 — reintroducing the
# exact bug. This test therefore also pins that the runner has one EXIT trap.
#
# WHY LAYER 1 CANNOT BE ASSERTED BY EXIT CODE: `bash -n` returns 0 for an
# unterminated heredoc while printing a warning to stderr. A self-check that
# consulted the exit status would pass on precisely the input it exists to
# catch, so the runner reads the diagnostic TEXT, and this test asserts that
# distinction explicitly rather than trusting the implementation.

set -uo pipefail

ASSERTIONS_PASSED=0
ASSERTIONS_FAILED=0

assert_equals() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✓ PASS: $label (= $actual)"
        ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    else
        echo "  ✗ FAIL: $label — expected '$expected', got '$actual'"
        ASSERTIONS_FAILED=$((ASSERTIONS_FAILED + 1))
    fi
}

assert_substring_present() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  ✓ PASS: $label"
        ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    else
        echo "  ✗ FAIL: $label — missing substring: $needle"
        ASSERTIONS_FAILED=$((ASSERTIONS_FAILED + 1))
    fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_RUNNER="$REPO_ROOT/tasks/test-marketplace-hook-regression-suite"

if [[ ! -f "$REAL_RUNNER" ]]; then
    echo "✗ FAIL: runner not found at $REAL_RUNNER"
    exit 1
fi

SANDBOX="$(mktemp -d)"
# shellcheck disable=SC2064  # expand SANDBOX now, not at trap time
trap "rm -rf '$SANDBOX'" EXIT

# Two synthetic tests that both pass. Discovery walks plugins/*/hooks or
# tasks/tests depending on the runner's globs; create both so the sandbox is
# insensitive to which path it prefers.
mkdir -p "$SANDBOX/tasks/tests" "$SANDBOX/plugins/synthetic/hooks"
for n in alpha beta; do
    cat > "$SANDBOX/tasks/tests/test-synthetic-$n.sh" <<'SYNTHETIC'
#!/usr/bin/env bash
echo "synthetic test ran"
exit 0
SYNTHETIC
    chmod +x "$SANDBOX/tasks/tests/test-synthetic-$n.sh"
done

echo "Iter-188 — silent-green sentinel regression"
echo

# ── Structural: exactly one EXIT trap in the real runner ────────────────────
# A second one would replace the sentinel with a handler that always exits 0.
EXIT_TRAP_COUNT="$(grep -cE "^[[:space:]]*trap .* EXIT" "$REAL_RUNNER")"
assert_equals "runner installs exactly ONE EXIT trap (a second would erase the sentinel)" \
    "$EXIT_TRAP_COUNT" "1"

# ── Control: the green path is untouched ────────────────────────────────────
mkdir -p "$SANDBOX/tasks"
# REPO_ROOT is dirname(runner)/.. — the copy must sit in tasks/ so it resolves
# to the sandbox root rather than the sandbox's parent.
cp "$REAL_RUNNER" "$SANDBOX/tasks/runner-green"
GREEN_OUT="$(cd "$SANDBOX/tasks" && bash ./runner-green 2>&1)"; GREEN_EXIT=$?
assert_equals "green run still exits 0" "$GREEN_EXIT" "0"
assert_substring_present "green run reports an executed count, not just a discovered one" \
    "$GREEN_OUT" "Test files executed:"

# ── The incident, reproduced: break the heredoc ─────────────────────────────
# Delete the heredoc terminator so the file ends mid-document, exactly as the
# original defect did.
HEREDOC_TERMINATOR="$(grep -oE "<<'[A-Z0-9_]+'" "$REAL_RUNNER" | head -1 | tr -d "<'")"
if [[ -z "$HEREDOC_TERMINATOR" ]]; then
    echo "  ✗ FAIL: could not locate a quoted heredoc opener in the runner"
    ASSERTIONS_FAILED=$((ASSERTIONS_FAILED + 1))
else
    assert_substring_present "located the heredoc delimiter to break" \
        "$HEREDOC_TERMINATOR" "$HEREDOC_TERMINATOR"

    # Remove the LAST standalone terminator line, leaving the document open.
    awk -v term="$HEREDOC_TERMINATOR" '
        $0 == term { if (!removed) { removed = 1; next } }
        { print }
    ' "$REAL_RUNNER" > "$SANDBOX/tasks/runner-broken"

    # Layer 1: the runner's own syntax self-check refuses to start.
    L1_OUT="$(cd "$SANDBOX/tasks" && bash ./runner-broken 2>&1)"; L1_EXIT=$?
    assert_equals "layer 1 refuses to run a syntactically broken runner (exit 96)" \
        "$L1_EXIT" "96"
    assert_substring_present "layer 1 says bash -n's EXIT STATUS was not consulted" \
        "$L1_OUT" "not consulted"

    # Layer 2, with layer 1 disabled so it cannot free-ride on its sibling.
    # This is the load-bearing assertion: it is the incident's exact shape.
    sed 's/^ITER188_RUNNER_SELF_PATH=.*/ITER188_RUNNER_SELF_PATH="\/dev\/null"/' \
        "$SANDBOX/tasks/runner-broken" > "$SANDBOX/tasks/runner-broken-nolayer1"
    L2_OUT="$(cd "$SANDBOX/tasks" && bash ./runner-broken-nolayer1 2>&1)"; L2_EXIT=$?
    if [[ "$L2_EXIT" == "0" ]]; then
        echo "  ✗ FAIL: layer 2 — a runner that executed nothing exited 0 (the original bug)"
        ASSERTIONS_FAILED=$((ASSERTIONS_FAILED + 1))
    else
        echo "  ✓ PASS: layer 2 — a runner that ends before a verdict cannot exit 0 (= $L2_EXIT)"
        ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    fi
    assert_substring_present "layer 2 names both numbers so the fault is self-describing" \
        "$L2_OUT" "SUITE DID NOT RUN"
fi

# ── Zero discovery must not be green either ─────────────────────────────────
# A gate that finds no tests in a repo that has 114 is the same defect by a
# different route, so "nothing to do" must never be reported as success.
EMPTY_SANDBOX="$(mktemp -d)"
mkdir -p "$EMPTY_SANDBOX/tasks/tests"
cp "$REAL_RUNNER" "$EMPTY_SANDBOX/tasks/runner-empty"
EMPTY_OUT="$(cd "$EMPTY_SANDBOX/tasks" && bash ./runner-empty 2>&1)"; EMPTY_EXIT=$?
rm -rf "$EMPTY_SANDBOX"
if [[ "$EMPTY_EXIT" == "0" ]]; then
    echo "  ✗ FAIL: zero-discovery run exited 0 — a suite finding no tests must not be green"
    ASSERTIONS_FAILED=$((ASSERTIONS_FAILED + 1))
else
    echo "  ✓ PASS: zero-discovery run is not green (= $EMPTY_EXIT)"
    ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
fi
# The diagnosis must point at DISCOVERY, not send the reader hunting a heredoc:
# a zero-discovery fault and an early-termination fault have the same symptom
# and completely different causes.
assert_substring_present "zero-discovery failure blames discovery, not a broken runner" \
    "$EMPTY_OUT" "SUITE DID NOT RUN"

echo
echo "Iter-188 — assertions passed: $ASSERTIONS_PASSED, failed: $ASSERTIONS_FAILED"
if (( ASSERTIONS_FAILED > 0 )); then
    echo "✗ FAIL — the silent-green sentinel is not holding"
    exit 1
fi
echo "✓ PASS — a suite that executes nothing can never report success"
exit 0
