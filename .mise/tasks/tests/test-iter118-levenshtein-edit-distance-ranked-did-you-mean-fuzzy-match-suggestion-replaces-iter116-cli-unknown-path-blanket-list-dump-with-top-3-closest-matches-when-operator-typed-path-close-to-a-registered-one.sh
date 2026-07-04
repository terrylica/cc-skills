#!/usr/bin/env bash
#MISE description="Iter-118 regression test for the Levenshtein-edit-distance-ranked Did-You-Mean fuzzy-match suggestion added to the iter-116 reverse-search CLI's unknown-path branch. Verifies (1) iter-118 accessor file exposes the 3 new exports: computeLevenshteinEditDistanceBetweenTwoStrings + rankAllRegisteredConsumerSourceFilePaths... + isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypo...; (2) Levenshtein distance correctness on classic textbook probes (kitten-to-sitting=3, abc-to-abc=0, empty-to-abc=3); (3) top-3 ranking returns the correct intended consumer path with distance 1 when operator typed extra trailing s on a known runtime-hook path (synthetic typo probe); (4) threshold predicate returns true on close typo (distance well under one-third of query length) and false on completely unrelated query (distance > one-third of query length); (5) iter-116 CLI unknown-path branch emits Did-you-mean-style top-3 suggestion when operator typed a plausible typo; (6) iter-116 CLI unknown-path branch falls back to full 19-path list display when operator query is completely unrelated to any registered path; (7) iter-118 enhancement does not regress the iter-116 happy-path (known-consumer lookup still works identically)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts"
ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"

# Real consumer paths picked from the registries — used to construct
# synthetic typos (add a trailing 's', flip a letter, etc.) whose
# Levenshtein distance to the intended path is intentionally small.
KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_FUZZY_PROBE="plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
SYNTHETIC_TYPO_OF_KNOWN_RUNTIME_HOOK_CONSUMER_PATH="plugins/itp-hooks/hooks/pretooluse-file-size-guards.ts"  # extra trailing 's' before .ts (distance 1)
COMPLETELY_UNRELATED_PATH_GUARANTEED_TO_BE_FAR_FROM_EVERY_REGISTERED_PATH="totally/different/thing.py"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-118 Levenshtein-ranked Did-You-Mean fuzzy-match regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: accessor file exposes the 3 new iter-118 exports ────────────
if grep -qE "^export function computeLevenshteinEditDistanceBetweenTwoStrings" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-118 accessor exports all 3 new functions (Levenshtein DP + top-K ranker + threshold predicate)"
else
    assert_fails "Case 1: iter-118 accessor missing one or more required exports"
fi

# ─── Cases 2-4: TypeScript probe exercising the functions directly ───────
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter118-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import {
  computeLevenshteinEditDistanceBetweenTwoStrings,
  rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches,
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold,
} from "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH";

let allProbesPassed = true;

// Probe 2: Levenshtein correctness — classic textbook reference cases
const kittenToSittingDistance = computeLevenshteinEditDistanceBetweenTwoStrings("kitten", "sitting");
const abcToAbcDistance = computeLevenshteinEditDistanceBetweenTwoStrings("abc", "abc");
const emptyToAbcDistance = computeLevenshteinEditDistanceBetweenTwoStrings("", "abc");
const abcToEmptyDistance = computeLevenshteinEditDistanceBetweenTwoStrings("abc", "");
if (
  kittenToSittingDistance === 3 &&
  abcToAbcDistance === 0 &&
  emptyToAbcDistance === 3 &&
  abcToEmptyDistance === 3
) {
  console.log("PROBE-2-PASS: Levenshtein DP correct on textbook reference cases (kitten-sitting=3, abc-abc=0, empty-abc=3, abc-empty=3)");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-2-FAIL: Levenshtein got kitten-sitting=\${kittenToSittingDistance}, abc-abc=\${abcToAbcDistance}, empty-abc=\${emptyToAbcDistance}, abc-empty=\${abcToEmptyDistance}\`);
}

// Probe 3: top-3 ranking on a synthetic single-edit typo of a real path
const topThreeRankedForSyntheticTypo =
  rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches(
    "$SYNTHETIC_TYPO_OF_KNOWN_RUNTIME_HOOK_CONSUMER_PATH",
    3,
  );
if (
  topThreeRankedForSyntheticTypo.length === 3 &&
  topThreeRankedForSyntheticTypo[0].consumerSourceFileRelativePath ===
    "$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_FUZZY_PROBE" &&
  topThreeRankedForSyntheticTypo[0].levenshteinEditDistanceFromOperatorSuppliedQuery === 1 &&
  // Verify ascending order (ties broken alphabetically by upstream sort)
  topThreeRankedForSyntheticTypo[0].levenshteinEditDistanceFromOperatorSuppliedQuery <=
    topThreeRankedForSyntheticTypo[1].levenshteinEditDistanceFromOperatorSuppliedQuery &&
  topThreeRankedForSyntheticTypo[1].levenshteinEditDistanceFromOperatorSuppliedQuery <=
    topThreeRankedForSyntheticTypo[2].levenshteinEditDistanceFromOperatorSuppliedQuery
) {
  console.log(\`PROBE-3-PASS: top-3 ranker correctly returns intended path as #1 with distance 1 (synthetic single-edit typo); list is sorted ascending\`);
} else {
  allProbesPassed = false;
  console.log(\`PROBE-3-FAIL: top-3 ranker returned wrong result: \${JSON.stringify(topThreeRankedForSyntheticTypo)}\`);
}

// Probe 4: threshold predicate — close typo passes, unrelated query fails
const closeTypoPassesThreshold =
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold(
    1, // synthetic typo distance
    "$SYNTHETIC_TYPO_OF_KNOWN_RUNTIME_HOOK_CONSUMER_PATH".length,
  );
const unrelatedQueryFailsThreshold =
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold(
    50, // arbitrary large distance
    "$COMPLETELY_UNRELATED_PATH_GUARANTEED_TO_BE_FAR_FROM_EVERY_REGISTERED_PATH".length,
  );
if (closeTypoPassesThreshold && !unrelatedQueryFailsThreshold) {
  console.log("PROBE-4-PASS: threshold predicate correctly accepts close typos (distance 1) and rejects unrelated queries (distance 50)");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-4-FAIL: threshold predicate gave wrong verdict (closeTypoPasses=\${closeTypoPassesThreshold}, unrelatedFails=\${unrelatedQueryFailsThreshold})\`);
}

if (!allProbesPassed) process.exit(1);
EOF

set +e
PROBE_OUTPUT=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
PROBE_EXIT_CODE=$?
set -e

if [[ "$PROBE_OUTPUT" == *"PROBE-2-PASS"* ]]; then
    assert_passes "Case 2: Levenshtein DP correct on textbook reference cases (kitten-sitting=3, abc-abc=0, empty-abc=3, abc-empty=3)"
else
    assert_fails "Case 2: Levenshtein DP correctness probe failed (output=$PROBE_OUTPUT)"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-3-PASS"* ]]; then
    assert_passes "Case 3: top-3 ranker returns intended path with distance 1 on synthetic single-edit typo + list is sorted ascending"
else
    assert_fails "Case 3: top-3 ranker probe failed"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-4-PASS"* ]]; then
    assert_passes "Case 4: threshold predicate accepts close typo (1 ≤ ⌊queryLen/3⌋) and rejects unrelated query (50 > ⌊queryLen/3⌋)"
else
    assert_fails "Case 4: threshold predicate probe failed (exit=$PROBE_EXIT_CODE)"
fi

# ─── Case 5: CLI emits Did-you-mean top-3 on plausible typo ──────────────
set +e
CLI_TYPO_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "$SYNTHETIC_TYPO_OF_KNOWN_RUNTIME_HOOK_CONSUMER_PATH" 2>&1)
CLI_TYPO_EXIT_CODE=$?
set -e
if [[ "$CLI_TYPO_EXIT_CODE" -eq 2 ]] && \
   [[ "$CLI_TYPO_OUTPUT" == *"Did you mean"* ]] && \
   [[ "$CLI_TYPO_OUTPUT" == *"[1 edit]"* ]] && \
   [[ "$CLI_TYPO_OUTPUT" == *"$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_FUZZY_PROBE"* ]] && \
   [[ "$CLI_TYPO_OUTPUT" != *"Hint: query is not close"* ]]; then
    assert_passes "Case 5: CLI on plausible-typo input emits 'Did you mean?' top-3 suggestion (includes [1 edit] for intended path; does NOT fall back to full-list display)"
else
    assert_fails "Case 5: CLI typo handling failed (exit=$CLI_TYPO_EXIT_CODE)"
fi

# ─── Case 6: CLI falls back to full-list display on unrelated query ──────
# The expected distinct-consumer-path count is DERIVED from the registries
# (the official source) rather than hard-coded: the previous pinned "19"
# broke when a 20th legitimate consumer path was registered (2026-06-11,
# posttooluse-invented-fallback-reminder.ts) even though the CLI behaved
# correctly. Same counting shape as the CLI's own
# distinctRegisteredConsumerPaths: unique quoted path values of the
# consumer*SourceFileRelativePath fields across both registries.
ITER118_EXPECTED_DISTINCT_CONSUMER_PATH_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES=$(
    grep -hA1 -E '^\s*consumer(Hook|AuditTask)SourceFileRelativePath:' \
        "$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts" \
        "$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts" \
        | grep -oE '"(plugins|\.mise)/[^"]+"' | sort -u | wc -l | tr -d ' '
)
set +e
CLI_UNRELATED_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "$COMPLETELY_UNRELATED_PATH_GUARANTEED_TO_BE_FAR_FROM_EVERY_REGISTERED_PATH" 2>&1)
CLI_UNRELATED_EXIT_CODE=$?
set -e
if [[ "$CLI_UNRELATED_EXIT_CODE" -eq 2 ]] && \
   [[ "$CLI_UNRELATED_OUTPUT" == *"Hint: query is not close to any registered path"* ]] && \
   [[ "$CLI_UNRELATED_OUTPUT" == *"Showing all ${ITER118_EXPECTED_DISTINCT_CONSUMER_PATH_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES} registered consumer paths"* ]] && \
   [[ "$CLI_UNRELATED_OUTPUT" != *"Did you mean"* ]]; then
    assert_passes "Case 6: CLI on unrelated-query input correctly falls back to full-list display of all ${ITER118_EXPECTED_DISTINCT_CONSUMER_PATH_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES} paths (count derived from the registries; does NOT misleadingly suggest unrelated paths)"
else
    assert_fails "Case 6: CLI unrelated-query handling failed (exit=$CLI_UNRELATED_EXIT_CODE, expected paths=${ITER118_EXPECTED_DISTINCT_CONSUMER_PATH_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES})"
fi

# ─── Case 7: iter-118 enhancement does not regress iter-116 happy path ───
set +e
CLI_HAPPY_PATH_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "$KNOWN_RUNTIME_HOOK_CONSUMER_PATH_FOR_FUZZY_PROBE" 2>&1)
CLI_HAPPY_PATH_EXIT_CODE=$?
set -e
if [[ "$CLI_HAPPY_PATH_EXIT_CODE" -eq 0 ]] && \
   [[ "$CLI_HAPPY_PATH_OUTPUT" == *"FILE-SIZE-OK"* ]] && \
   [[ "$CLI_HAPPY_PATH_OUTPUT" == *"Found 1 escape-hatch marker"* ]] && \
   [[ "$CLI_HAPPY_PATH_OUTPUT" != *"Did you mean"* ]]; then
    assert_passes "Case 7: iter-118 fuzzy-match enhancement does NOT regress the iter-116 happy-path (known-consumer lookup still works identically — no spurious Did-you-mean suggestions)"
else
    assert_fails "Case 7: iter-118 broke the iter-116 happy-path (exit=$CLI_HAPPY_PATH_EXIT_CODE)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-118 regression — Summary"
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
echo "  🚀 Iter-118 Levenshtein-ranked Did-You-Mean fuzzy-match suggestion"
echo "     established. Operators who typo a consumer source file path now"
echo "     see a top-3 'Did you mean?' list with edit-distance annotations"
echo "     (mirroring the industry-standard git/cargo/kubectl pattern)"
echo "     instead of the iter-116 blanket 19-path dump. The threshold"
echo "     predicate (⌊queryLen / 3⌋ edits) ensures unrelated queries"
echo "     fall back to the full-list display without misleading the"
echo "     operator with three random-looking suggestions."
echo "  🚀 Iter-119+ candidates queued:"
echo "     - Stale-description audit (task #144): verify every registry"
echo "       entry's operator-doc description field mentions a hook/task"
echo "       name consistent with declared consumer-path. Wire as"
echo "       preflight Check 4v informational."
echo "     - JSON output mode for iter-116 CLI (--json flag): emit"
echo "       machine-readable output for piping to jq + downstream"
echo "       automation. Top-K ranking already has structured shape"
echo "       (RegisteredConsumerPathRankedByLevenshteinDistanceFromQuery)"
echo "       so the JSON renderer is a thin wrapper over existing data."
