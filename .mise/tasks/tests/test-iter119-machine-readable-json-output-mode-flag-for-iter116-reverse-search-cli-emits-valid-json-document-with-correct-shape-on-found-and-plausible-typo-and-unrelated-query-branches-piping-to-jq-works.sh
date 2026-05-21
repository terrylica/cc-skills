#!/usr/bin/env bash
#MISE description="Iter-119 regression test for the --json output mode flag added to the iter-116 reverse-search CLI. Verifies (1) --json flag is documented in the CLI's usage message; (2) --json on a known consumer emits valid JSON parseable by jq with status=found + markers array containing the lifecycleLayer string field + the full registry entry; (3) --json on a plausible-typo query emits valid JSON with status=not-found + didYouMean array sorted ascending by Levenshtein distance + allRegisteredConsumerSourceFilePaths is null (didYouMean non-null path); (4) --json on a truly-unrelated query emits valid JSON with status=not-found + didYouMean=null + allRegisteredConsumerSourceFilePaths populated; (5) JSON output is emitted to stdout (not stderr) so it can be piped to jq; (6) exit codes are unchanged from iter-116/iter-118 baseline (0 found, 2 not-found, 1 usage error); (7) human-readable mode (no --json flag) is preserved unchanged."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"

KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_JSON_PROBE="plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
SYNTHETIC_TYPO_OF_KNOWN_RUNTIME_HOOK_CONSUMER_PATH="plugins/itp-hooks/hooks/pretooluse-file-size-guards.ts"  # extra trailing 's' (distance 1)
COMPLETELY_UNRELATED_PATH_GUARANTEED_TO_BE_FAR_FROM_EVERY_REGISTERED_PATH="zzz/xyz/qqq-iter119-totally-unrelated-bogus-path-with-no-shared-prefix.aaa"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-119 --json output mode regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Sanity: jq must be on PATH for this test to verify JSON correctness.
if ! command -v jq >/dev/null 2>&1; then
    assert_fails "Precondition: jq is required to validate --json output but was not found on PATH"
    echo "  Install jq via Homebrew (brew install jq) and re-run."
    exit 1
fi

# ─── Case 1: --json flag is documented in the CLI usage message ──────────
set +e
USAGE_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --help 2>&1)
USAGE_EXIT_CODE=$?
set -e
if [[ "$USAGE_EXIT_CODE" -eq 1 ]] && \
   [[ "$USAGE_OUTPUT" == *"--json"* ]] && \
   [[ "$USAGE_OUTPUT" == *"jq"* ]]; then
    assert_passes "Case 1: --json flag is documented in --help usage message with jq pipeline example"
else
    assert_fails "Case 1: --json flag missing from --help output (exit=$USAGE_EXIT_CODE)"
fi

# ─── Case 2: --json on known consumer emits valid JSON with found shape ───
set +e
JSON_FOUND_STDOUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_JSON_PROBE" 2>/dev/null)
JSON_FOUND_EXIT_CODE=$?
set -e
JSON_FOUND_STATUS=$(echo "$JSON_FOUND_STDOUT" | jq -r '.status' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_FOUND_MARKER_COUNT=$(echo "$JSON_FOUND_STDOUT" | jq -r '.markers | length' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_FOUND_FIRST_MARKER_NAME=$(echo "$JSON_FOUND_STDOUT" | jq -r '.markers[0].markerNameTokenIncludingSuffix' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_FOUND_FIRST_MARKER_LIFECYCLE=$(echo "$JSON_FOUND_STDOUT" | jq -r '.markers[0].lifecycleLayer' 2>/dev/null || echo "JQ_PARSE_ERROR")

if [[ "$JSON_FOUND_EXIT_CODE" -eq 0 ]] && \
   [[ "$JSON_FOUND_STATUS" == "found" ]] && \
   [[ "$JSON_FOUND_MARKER_COUNT" == "1" ]] && \
   [[ "$JSON_FOUND_FIRST_MARKER_NAME" == "FILE-SIZE-OK" ]] && \
   [[ "$JSON_FOUND_FIRST_MARKER_LIFECYCLE" == "runtime-hook" ]]; then
    assert_passes "Case 2: --json on known consumer emits valid JSON (status=found, 1 marker = FILE-SIZE-OK, lifecycleLayer=runtime-hook) parseable by jq"
else
    assert_fails "Case 2: --json found-branch JSON shape wrong (status=$JSON_FOUND_STATUS, markerCount=$JSON_FOUND_MARKER_COUNT, firstMarker=$JSON_FOUND_FIRST_MARKER_NAME, lifecycle=$JSON_FOUND_FIRST_MARKER_LIFECYCLE, exit=$JSON_FOUND_EXIT_CODE)"
fi

# ─── Case 3: --json on plausible typo emits valid not-found with didYouMean ──
set +e
JSON_TYPO_STDOUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "$SYNTHETIC_TYPO_OF_KNOWN_RUNTIME_HOOK_CONSUMER_PATH" 2>/dev/null)
JSON_TYPO_EXIT_CODE=$?
set -e
JSON_TYPO_STATUS=$(echo "$JSON_TYPO_STDOUT" | jq -r '.status' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_TYPO_DID_YOU_MEAN_LENGTH=$(echo "$JSON_TYPO_STDOUT" | jq -r '.didYouMean | length' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_TYPO_TOP_MATCH_PATH=$(echo "$JSON_TYPO_STDOUT" | jq -r '.didYouMean[0].consumerSourceFileRelativePath' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_TYPO_TOP_MATCH_DISTANCE=$(echo "$JSON_TYPO_STDOUT" | jq -r '.didYouMean[0].levenshteinEditDistanceFromOperatorSuppliedQuery' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_TYPO_ALL_REGISTERED_IS_NULL=$(echo "$JSON_TYPO_STDOUT" | jq -r '.allRegisteredConsumerSourceFilePaths == null' 2>/dev/null || echo "JQ_PARSE_ERROR")

if [[ "$JSON_TYPO_EXIT_CODE" -eq 2 ]] && \
   [[ "$JSON_TYPO_STATUS" == "not-found" ]] && \
   [[ "$JSON_TYPO_DID_YOU_MEAN_LENGTH" == "3" ]] && \
   [[ "$JSON_TYPO_TOP_MATCH_PATH" == "$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_JSON_PROBE" ]] && \
   [[ "$JSON_TYPO_TOP_MATCH_DISTANCE" == "1" ]] && \
   [[ "$JSON_TYPO_ALL_REGISTERED_IS_NULL" == "true" ]]; then
    assert_passes "Case 3: --json on plausible typo emits status=not-found + didYouMean[3] (top match = intended path with distance 1) + allRegisteredConsumerSourceFilePaths is null"
else
    assert_fails "Case 3: --json typo-branch JSON shape wrong (status=$JSON_TYPO_STATUS, didYouMeanLen=$JSON_TYPO_DID_YOU_MEAN_LENGTH, topMatch=$JSON_TYPO_TOP_MATCH_PATH, topDistance=$JSON_TYPO_TOP_MATCH_DISTANCE, allRegisteredIsNull=$JSON_TYPO_ALL_REGISTERED_IS_NULL, exit=$JSON_TYPO_EXIT_CODE)"
fi

# ─── Case 4: --json on unrelated query emits not-found + didYouMean=null + full list ──
set +e
JSON_UNRELATED_STDOUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "$COMPLETELY_UNRELATED_PATH_GUARANTEED_TO_BE_FAR_FROM_EVERY_REGISTERED_PATH" 2>/dev/null)
JSON_UNRELATED_EXIT_CODE=$?
set -e
JSON_UNRELATED_STATUS=$(echo "$JSON_UNRELATED_STDOUT" | jq -r '.status' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_UNRELATED_DID_YOU_MEAN_IS_NULL=$(echo "$JSON_UNRELATED_STDOUT" | jq -r '.didYouMean == null' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_UNRELATED_ALL_REGISTERED_LENGTH=$(echo "$JSON_UNRELATED_STDOUT" | jq -r '.allRegisteredConsumerSourceFilePaths | length' 2>/dev/null || echo "JQ_PARSE_ERROR")

if [[ "$JSON_UNRELATED_EXIT_CODE" -eq 2 ]] && \
   [[ "$JSON_UNRELATED_STATUS" == "not-found" ]] && \
   [[ "$JSON_UNRELATED_DID_YOU_MEAN_IS_NULL" == "true" ]] && \
   [[ "$JSON_UNRELATED_ALL_REGISTERED_LENGTH" -ge 15 ]]; then
    assert_passes "Case 4: --json on unrelated query emits status=not-found + didYouMean=null + allRegisteredConsumerSourceFilePaths populated (length ≥15) — symmetric inverse of Case 3"
else
    assert_fails "Case 4: --json unrelated-branch shape wrong (status=$JSON_UNRELATED_STATUS, didYouMeanIsNull=$JSON_UNRELATED_DID_YOU_MEAN_IS_NULL, allRegisteredLen=$JSON_UNRELATED_ALL_REGISTERED_LENGTH, exit=$JSON_UNRELATED_EXIT_CODE)"
fi

# ─── Case 5: JSON goes to stdout (not stderr) so it can be piped to jq ───
# Separately capture stdout + stderr to confirm: stdout contains JSON,
# stderr is empty (or at most contains non-JSON diagnostic noise — but
# anything emitted to stderr would break a `... --json X | jq` pipeline
# because jq would see whatever stderr text the shell merges in if 2>&1
# is added unintentionally; the contract is JSON on stdout, nothing on
# stderr when --json is set).
JSON_STDOUT_TEMP_FILE=$(mktemp -t iter119-stdout-XXXXXX)
JSON_STDERR_TEMP_FILE=$(mktemp -t iter119-stderr-XXXXXX)
trap 'rm -f "$JSON_STDOUT_TEMP_FILE" "$JSON_STDERR_TEMP_FILE"' EXIT
set +e
bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_JSON_PROBE" >"$JSON_STDOUT_TEMP_FILE" 2>"$JSON_STDERR_TEMP_FILE"
set -e
STDOUT_SIZE_BYTES=$(wc -c <"$JSON_STDOUT_TEMP_FILE" | tr -d ' ')
STDERR_SIZE_BYTES=$(wc -c <"$JSON_STDERR_TEMP_FILE" | tr -d ' ')
STDOUT_PARSES_AS_JSON_ECHOING_STATUS=$(jq -r '.status' "$JSON_STDOUT_TEMP_FILE" 2>/dev/null || echo "JQ_PARSE_ERROR")

if [[ "$STDOUT_SIZE_BYTES" -gt 100 ]] && \
   [[ "$STDOUT_PARSES_AS_JSON_ECHOING_STATUS" == "found" ]] && \
   [[ "$STDERR_SIZE_BYTES" -eq 0 ]]; then
    assert_passes "Case 5: JSON output (${STDOUT_SIZE_BYTES} bytes) goes to stdout; stderr is empty (${STDERR_SIZE_BYTES} bytes) — pipe-to-jq contract intact"
else
    assert_fails "Case 5: JSON output routing broken (stdout=$STDOUT_SIZE_BYTES bytes, stderr=$STDERR_SIZE_BYTES bytes, stdoutStatus=$STDOUT_PARSES_AS_JSON_ECHOING_STATUS)"
fi

# ─── Case 6: exit codes unchanged from iter-116/118 baseline ─────────────
# Re-verify exit codes from Cases 2, 3, 4 above.
if [[ "$JSON_FOUND_EXIT_CODE" -eq 0 ]] && \
   [[ "$JSON_TYPO_EXIT_CODE" -eq 2 ]] && \
   [[ "$JSON_UNRELATED_EXIT_CODE" -eq 2 ]] && \
   [[ "$USAGE_EXIT_CODE" -eq 1 ]]; then
    assert_passes "Case 6: --json mode preserves exit-code contract (0=found, 2=not-found, 1=usage-error) — automation can branch on exit code without parsing JSON"
else
    assert_fails "Case 6: exit-code contract broken (found=$JSON_FOUND_EXIT_CODE expected 0; typo=$JSON_TYPO_EXIT_CODE expected 2; unrelated=$JSON_UNRELATED_EXIT_CODE expected 2; help=$USAGE_EXIT_CODE expected 1)"
fi

# ─── Case 7: human-readable mode (no --json) preserved unchanged ─────────
set +e
HUMAN_READABLE_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_JSON_PROBE" 2>&1)
HUMAN_READABLE_EXIT_CODE=$?
set -e
if [[ "$HUMAN_READABLE_EXIT_CODE" -eq 0 ]] && \
   [[ "$HUMAN_READABLE_OUTPUT" == *"FILE-SIZE-OK"* ]] && \
   [[ "$HUMAN_READABLE_OUTPUT" == *"Found 1 escape-hatch marker"* ]] && \
   [[ "$HUMAN_READABLE_OUTPUT" != *"\"status\":"* ]]; then
    assert_passes "Case 7: human-readable mode (no --json) preserved unchanged — emits terminal blocks, NOT JSON (the --json flag is purely additive)"
else
    assert_fails "Case 7: human-readable mode regressed when --json was NOT supplied (exit=$HUMAN_READABLE_EXIT_CODE)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-119 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-119 --json output mode established. Operators can now pipe"
echo "     the iter-116 reverse-search CLI directly to jq for automation"
echo "     workflows: dashboards, coverage checks, programmatic registry"
echo "     queries. The JSON shape preserves iter-116's discriminated-union"
echo "     lifecycle-layer provenance (runtime-hook vs audit-task) and"
echo "     iter-118's Levenshtein-ranked didYouMean suggestions — encoding"
echo "     the 'plausible typo' vs 'unrelated query' decision in the JSON"
echo "     shape itself (didYouMean is non-null XOR allRegisteredConsumer"
echo "     SourceFilePaths is non-null) so downstream consumers can branch"
echo "     without re-running the threshold check."
echo "  🚀 Iter-120+ queue:"
echo "     - Stale-description audit (task #144): verify every registry"
echo "       entry's operator-doc description field mentions a hook/task"
echo "       name consistent with declared consumer-path. Wire as preflight"
echo "       Check 4v informational."
echo "     - Basename-substring search mode (e.g., --basename-substring"
echo "       file-size) so operators who know only the consumer's"
echo "       short name don't need to type the full path."
