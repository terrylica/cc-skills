#!/usr/bin/env bash
#MISE description="Asserts the PROPERTY that proto >= 0.61.2 guarantees: a shim-invoked tool's STDOUT is the tool's own output, with no 'Detected an AI agent environment' NDJSON banner prepended, even under the concurrency that used to trigger it. Replaces the retired validate-plugins hygiene lint, which could only check that people wrote the `env -u AI_AGENT -u CLAUDECODE` workaround rather than that the bug is absent. Skips cleanly when proto or a shim is unavailable."

# ────────────────────────────────────────────────────────────────────────
# Why this test exists, and why it is a test rather than a lint
# ────────────────────────────────────────────────────────────────────────
#
# proto < 0.61.2 wrote an NDJSON banner to the STDOUT of tools invoked through
# a shim:
#
#   {"type":"message","message":"Detected an AI agent environment, printing as
#    NDJSON. Trace logs are written to stderr, while user-facing logs are
#    written to stdout."}
#
# A Claude Code hook's stdout is a JSON protocol the harness parses for the
# hook's decision, so that banner made the payload two JSON documents and the
# decision was DISCARDED — 2,008 times over three days, at exit code 0, with a
# set of guards silently not applying. Reported as moonrepo/proto#1105 and
# fixed upstream ("Fixed in v0.61.2").
#
# We carried a workaround (`env -u AI_AGENT -u CLAUDECODE ` on all 43 hook
# commands) plus a lint that required it. Both are retired. The lint checked a
# PROXY — "did someone write the prefix" — whereas this checks the property
# anyone actually cares about: is the bug absent. A proxy check keeps passing
# when the workaround is present but useless, and keeps failing when the
# workaround is correctly removed.
#
# The floor is enforced in .prototools (proto = "0.61.2") and by preflight
# Check 1b. This test is the backstop for a REGRESSION — an upstream revert, or
# a machine that somehow runs an older proto.
#
# CONCURRENCY MATTERS. The banner was never deterministic: it appeared under
# lock contention when many shimmed processes started at once. Measured on
# 0.61.1: 0/100 polluted serially, 27-45/100 at 100-way concurrency. A serial
# check here would have passed on the broken version and proved nothing.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

BANNER_SUBSTRING="Detected an AI agent environment"
CONCURRENT_SHIM_INVOCATION_COUNT="${PROTO_BANNER_TEST_INVOCATIONS:-60}"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails() { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  proto shim STDOUT cleanliness (moonrepo/proto#1105 regression)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

PROTO_SHIM_FOR_BUN="$HOME/.proto/shims/bun"
if ! command -v proto >/dev/null 2>&1 || [[ ! -x "$PROTO_SHIM_FOR_BUN" ]]; then
    echo "  ⊘ SKIP: proto or its bun shim is unavailable on this machine"
    echo "    (nothing to regress against; not a pass)"
    exit 0
fi

echo "  proto: $(proto --version 2>/dev/null || echo unknown)"
echo ""

SHIM_STDOUT_CAPTURE_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$SHIM_STDOUT_CAPTURE_DIRECTORY"' EXIT

# ─── Case 1: banner absent under concurrency, with the agent env vars SET ────
#
# The env vars are set deliberately: they are exactly what proto sniffs, and
# what Claude Code exports into every hook subprocess. Running without them
# would test nothing.
invoke_shim_capturing_stdout() {
    local capture_index="$1"
    AI_AGENT=claude-code CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli \
        "$PROTO_SHIM_FOR_BUN" --version \
        >"$SHIM_STDOUT_CAPTURE_DIRECTORY/$capture_index.out" 2>/dev/null || true
}

for capture_index in $(seq 1 "$CONCURRENT_SHIM_INVOCATION_COUNT"); do
    invoke_shim_capturing_stdout "$capture_index" &
done
wait

POLLUTED_INVOCATION_COUNT=0
EMPTY_INVOCATION_COUNT=0
for captured_stdout_file in "$SHIM_STDOUT_CAPTURE_DIRECTORY"/*.out; do
    if grep -qF "$BANNER_SUBSTRING" "$captured_stdout_file"; then
        POLLUTED_INVOCATION_COUNT=$((POLLUTED_INVOCATION_COUNT + 1))
    fi
    [[ -s "$captured_stdout_file" ]] || EMPTY_INVOCATION_COUNT=$((EMPTY_INVOCATION_COUNT + 1))
done

# Positive control: if every capture is empty the shim never ran, and a zero
# pollution count would be vacuous — the exact failure class this repo keeps
# rediscovering. An empty result set and a clean result set are the same bytes.
if [[ "$EMPTY_INVOCATION_COUNT" -eq "$CONCURRENT_SHIM_INVOCATION_COUNT" ]]; then
    assert_fails "Case 1: all $CONCURRENT_SHIM_INVOCATION_COUNT invocations produced EMPTY stdout — the shim never ran, so this check examined nothing"
elif [[ "$POLLUTED_INVOCATION_COUNT" -eq 0 ]]; then
    assert_passes "Case 1: 0/$CONCURRENT_SHIM_INVOCATION_COUNT concurrent shim invocations carried the AI-agent banner on stdout"
else
    assert_fails "Case 1: $POLLUTED_INVOCATION_COUNT/$CONCURRENT_SHIM_INVOCATION_COUNT concurrent shim invocations wrote the banner to stdout — hook decisions would be silently discarded. Upgrade proto (>= 0.61.2)."
fi

# ─── Case 2: the detector itself works ──────────────────────────────────────
#
# Case 1 passing is only meaningful if a banner WOULD have been detected. Feed
# the grep the real banner text and confirm it fires, so a future edit that
# breaks the pattern cannot turn Case 1 into an unconditional pass.
printf '%s\n' '{"type":"message","message":"Detected an AI agent environment, printing as NDJSON."}' \
    >"$SHIM_STDOUT_CAPTURE_DIRECTORY/synthetic-positive-control.txt"
if grep -qF "$BANNER_SUBSTRING" "$SHIM_STDOUT_CAPTURE_DIRECTORY/synthetic-positive-control.txt"; then
    assert_passes "Case 2: detector fires on a synthetic banner (Case 1's clean result is meaningful, not vacuous)"
else
    assert_fails "Case 2: detector did NOT fire on a synthetic banner — Case 1 can never fail and proves nothing"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Summary — passed: $ASSERTION_PASSED_COUNT, failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
[[ "$ASSERTION_FAILED_COUNT" -eq 0 ]] || exit 1
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
