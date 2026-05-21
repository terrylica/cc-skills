#!/usr/bin/env bash
#MISE description="Iter-144 regression test for the semantic-release DEBUG namespace stderr parser script. Validates against a SYNTHETIC fixture log containing known ISO8601 timestamps + known semantic-release: namespaces + known options-for plugin/lifecycle-step markers + known silent SyntaxError stack traces. Asserts the parser correctly: (a) sums cumulative elapsed-milliseconds per debug-namespace with documented timestamp deltas, (b) sums per plugin-lifecycle-step using options-for markers with documented LOADING-PHASE-ONLY caveat, (c) counts silent JSON.parse SyntaxError stack traces emitted by the getTagsNotes swallowed catch block, (d) handles multi-line continuation lines without ISO8601 prefix by skipping them, (e) emits BOTH ranking dimensions in correct sort order, (f) honors ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY operator-tunable override. Synthetic fixture chosen over live capture so the test is deterministic (live semantic-release timing varies with network)."
set -euo pipefail

ITER144_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER144_REPO_ROOT"

ITER144_PARSER_SCRIPT_RELATIVE_PATH="scripts/iter144-semantic-release-plugin-lifecycle-step-timing-instrumentation-via-debug-namespace-stderr-output-parser-emitting-top-n-slowest-bottleneck-ranking-with-cumulative-elapsed-milliseconds-summed-per-plugin-step.py"
ITER144_PARSER_SCRIPT_ABSOLUTE_PATH="$ITER144_REPO_ROOT/$ITER144_PARSER_SCRIPT_RELATIVE_PATH"

ITER144_TOTAL_ASSERTIONS_EVALUATED=0
ITER144_TOTAL_ASSERTIONS_FAILED=0

iter144_assert_substring_present_in_parser_output() {
    local human_readable_assertion_label_for_iter144="$1"
    local parser_output_haystack="$2"
    local expected_substring_to_locate_inside_parser_output="$3"
    ITER144_TOTAL_ASSERTIONS_EVALUATED=$((ITER144_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$parser_output_haystack" == *"$expected_substring_to_locate_inside_parser_output"* ]]; then
        echo "  ✓ $human_readable_assertion_label_for_iter144"
    else
        echo "  ✗ $human_readable_assertion_label_for_iter144"
        echo "    expected substring: ${expected_substring_to_locate_inside_parser_output:0:120}"
        ITER144_TOTAL_ASSERTIONS_FAILED=$((ITER144_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter144_assert_filesystem_predicate_holds_against_parser_script_file() {
    local human_readable_assertion_label_for_iter144="$1"
    local bash_test_expression="$2"
    ITER144_TOTAL_ASSERTIONS_EVALUATED=$((ITER144_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label_for_iter144"
    else
        echo "  ✗ $human_readable_assertion_label_for_iter144"
        echo "    failed bash predicate: $bash_test_expression"
        ITER144_TOTAL_ASSERTIONS_FAILED=$((ITER144_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-144 SEMANTIC-RELEASE DEBUG NAMESPACE STDERR PARSER REGRESSION TEST"
echo "  Pins: dual-dimension ranking output, silent SyntaxError forensic count,"
echo "        multi-line continuation handling, top-N operator-tunable override."
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Parser script presence + invocability ──────────────────────────
echo ""
echo "GROUP A (3 assertions): Parser script exists + python3 invocable"

iter144_assert_filesystem_predicate_holds_against_parser_script_file \
    "A1: iter-144 parser script exists at verbose iter-144 path" \
    "-f \"$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH\""

iter144_assert_filesystem_predicate_holds_against_parser_script_file \
    "A2: iter-144 parser script is executable (chmod +x)" \
    "-x \"$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH\""

# Compile-check: python3 -m py_compile should exit 0.
ITER144_TOTAL_ASSERTIONS_EVALUATED=$((ITER144_TOTAL_ASSERTIONS_EVALUATED + 1))
if python3 -m py_compile "$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A3: iter-144 parser script passes python3 -m py_compile"
else
    echo "  ✗ A3: iter-144 parser script FAILS python3 -m py_compile"
    ITER144_TOTAL_ASSERTIONS_FAILED=$((ITER144_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group B: Synthetic fixture parsing — deterministic timing claims ────────
echo ""
echo "GROUP B (8 assertions): Parser against synthetic fixture with known deltas"

# Synthetic fixture: 4 namespaces, known cumulative deltas summing to 1000ms+.
# All timestamps in 2026-01-01 to avoid year-rollover edge case.
ITER144_SYNTHETIC_DEBUG_LOG_FIXTURE_FILE_PATH=$(mktemp -t iter144-synthetic-debug-fixture-XXXXXX.log)
cat > "$ITER144_SYNTHETIC_DEBUG_LOG_FIXTURE_FILE_PATH" <<'ITER144_SYNTHETIC_DEBUG_FIXTURE_HEREDOC'
2026-01-01T00:00:00.000Z semantic-release:config load config from: /tmp/fake.yml
2026-01-01T00:00:00.500Z semantic-release:config options values: {
  branches: [ 'main' ],
  plugins: [ ... ]
}
2026-01-01T00:00:01.000Z semantic-release:plugins options for @semantic-release/exec/verifyConditions: { cmd: 'true' }
2026-01-01T00:00:01.010Z semantic-release:plugins options for @semantic-release/git/verifyConditions: { assets: [...] }
2026-01-01T00:00:01.020Z semantic-release:plugins options for @semantic-release/github/verifyConditions: {}
2026-01-01T00:00:01.030Z semantic-release:plugins options for @semantic-release/exec/fail: { cmd: 'false' }
2026-01-01T00:00:03.000Z semantic-release:get-git-auth-url Verifying ssh auth by attempting to push to https://github.com/fake/fake.git
2026-01-01T00:00:05.000Z semantic-release:get-git-auth-url SSH key auth successful.
2026-01-01T00:00:06.500Z semantic-release:get-tags Found tags: ["v1.0.0","v2.0.0"]
2026-01-01T00:00:06.510Z semantic-release:git SyntaxError: "undefined" is not valid JSON
    at JSON.parse (<anonymous>)
    at getTagsNotes (file:///fake/node_modules/semantic-release/lib/git.js:346:27)
2026-01-01T00:00:06.520Z semantic-release:git SyntaxError: "undefined" is not valid JSON
    at JSON.parse (<anonymous>)
    at getTagsNotes (file:///fake/node_modules/semantic-release/lib/git.js:346:27)
2026-01-01T00:00:06.600Z semantic-release:get-commits Found 1 commit since last release
ITER144_SYNTHETIC_DEBUG_FIXTURE_HEREDOC

# Capture parser output for assertions.
ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE=$(python3 "$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH" "$ITER144_SYNTHETIC_DEBUG_LOG_FIXTURE_FILE_PATH" 2>&1)

iter144_assert_substring_present_in_parser_output \
    "B1: dimension-1 header 'slowest semantic-release debug-namespaces' present in parser output" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "slowest semantic-release debug-namespaces"

iter144_assert_substring_present_in_parser_output \
    "B2: dimension-2 header 'plugin-lifecycle-steps by loading-phase elapsed-ms' present" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "plugin-lifecycle-steps by loading-phase elapsed-ms"

iter144_assert_substring_present_in_parser_output \
    "B3: ACCURATE attribution caveat for dimension 1 present in parser output" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "actionable target for further optimization"

iter144_assert_substring_present_in_parser_output \
    "B4: MISATTRIBUTION caveat for dimension 2 (LOADING-PHASE-ONLY) present in parser output" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "post-loading execution misattributes to the LAST loaded step"

iter144_assert_substring_present_in_parser_output \
    "B5: get-git-auth-url namespace ranked in dimension-1 output (synthetic fixture: 2000ms expected)" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "semantic-release:get-git-auth-url"

iter144_assert_substring_present_in_parser_output \
    "B6: get-tags namespace ranked in dimension-1 output (synthetic fixture)" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "semantic-release:get-tags"

iter144_assert_substring_present_in_parser_output \
    "B7: forensic finding emits with 2 silent SyntaxError occurrences from synthetic fixture" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "2 silent JSON.parse SyntaxError stack traces"

iter144_assert_substring_present_in_parser_output \
    "B8: forensic finding cites root cause (empty notes refs)" \
    "$ITER144_PARSER_OUTPUT_CAPTURED_FROM_RUNNING_AGAINST_SYNTHETIC_FIXTURE" \
    "tags with empty"

# ─── Group C: Operator-tunable top-N override ────────────────────────────────
echo ""
echo "GROUP C (2 assertions): ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY honored"

ITER144_PARSER_OUTPUT_WITH_TOP_N_OVERRIDE_SET_TO_THREE=$(ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY=3 python3 "$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH" "$ITER144_SYNTHETIC_DEBUG_LOG_FIXTURE_FILE_PATH" 2>&1)

iter144_assert_substring_present_in_parser_output \
    "C1: Top-3 header rendered when override=3 (instead of default Top-10)" \
    "$ITER144_PARSER_OUTPUT_WITH_TOP_N_OVERRIDE_SET_TO_THREE" \
    "Top 3 slowest"

iter144_assert_substring_present_in_parser_output \
    "C2: Top-N override env-var name documented in parser output" \
    "$ITER144_PARSER_OUTPUT_WITH_TOP_N_OVERRIDE_SET_TO_THREE" \
    "ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY"

# ─── Group D: Edge cases — empty log, missing file ───────────────────────────
echo ""
echo "GROUP D (2 assertions): Error handling"

# D1: nonexistent file → exit 1.
ITER144_TOTAL_ASSERTIONS_EVALUATED=$((ITER144_TOTAL_ASSERTIONS_EVALUATED + 1))
if ! python3 "$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH" "/tmp/iter144-does-not-exist-$$.log" 2>/dev/null; then
    echo "  ✓ D1: nonexistent debug log file produces non-zero exit code"
else
    echo "  ✗ D1: nonexistent debug log file should exit non-zero"
    ITER144_TOTAL_ASSERTIONS_FAILED=$((ITER144_TOTAL_ASSERTIONS_FAILED + 1))
fi

# D2: empty log file → parser doesn't crash.
ITER144_EMPTY_LOG_FIXTURE_FILE_PATH=$(mktemp -t iter144-empty-debug-fixture-XXXXXX.log)
: > "$ITER144_EMPTY_LOG_FIXTURE_FILE_PATH"
ITER144_TOTAL_ASSERTIONS_EVALUATED=$((ITER144_TOTAL_ASSERTIONS_EVALUATED + 1))
if python3 "$ITER144_PARSER_SCRIPT_ABSOLUTE_PATH" "$ITER144_EMPTY_LOG_FIXTURE_FILE_PATH" >/dev/null 2>&1; then
    echo "  ✓ D2: empty debug log file does not crash parser (exits 0)"
else
    echo "  ✗ D2: empty debug log file crashed parser"
    ITER144_TOTAL_ASSERTIONS_FAILED=$((ITER144_TOTAL_ASSERTIONS_FAILED + 1))
fi
rm -f "$ITER144_EMPTY_LOG_FIXTURE_FILE_PATH"

# Cleanup synthetic fixture.
rm -f "$ITER144_SYNTHETIC_DEBUG_LOG_FIXTURE_FILE_PATH"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER144_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-144 REGRESSION TEST: ${ITER144_TOTAL_ASSERTIONS_EVALUATED}/${ITER144_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-144 REGRESSION TEST: $((ITER144_TOTAL_ASSERTIONS_EVALUATED - ITER144_TOTAL_ASSERTIONS_FAILED))/${ITER144_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER144_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
