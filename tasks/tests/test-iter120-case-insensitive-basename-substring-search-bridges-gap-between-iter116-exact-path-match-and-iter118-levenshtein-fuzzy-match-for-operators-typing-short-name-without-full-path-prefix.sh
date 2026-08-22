#!/usr/bin/env bash
#MISE description="Iter-120 regression test for the case-insensitive basename-substring search added to the iter-116 CLI fallback chain BETWEEN exact-path-match and iter-118 Levenshtein fuzzy-match. Verifies (1) accessor function findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively exists and exports correctly; (2) accessor returns expected matches for short-name queries that iter-118 would reject (file-size, cargo); (3) accessor returns case-insensitively (uppercase query matches lowercase basenames); (4) CLI catches basename-substring queries before falling through to Levenshtein; (5) CLI skips basename-substring step when query contains a slash (operator clearly meant a fully-qualified path so iter-118 Levenshtein is the right tool); (6) JSON mode emits status=found + matchType=basename-substring + matchingConsumerSourceFilePaths + markers; (7) JSON mode on exact match now emits matchType=exact (iter-119 forward-compat); (8) iter-118 Levenshtein still works on plausible-typo full-path queries (not regressed by iter-120)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts"
ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-120 basename-substring search regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: accessor function exported ──────────────────────────────────
if grep -qE "^export function findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-120 accessor function findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively is exported"
else
    assert_fails "Case 1: iter-120 accessor function missing"
fi

# ─── Cases 2-3: TypeScript probe exercising the accessor directly ────────
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter120-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import {
  findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively,
} from "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH";

let allProbesPassed = true;

// Probe 2: short-name "file-size" should match exactly one registered path
const fileSizeBasenameMatches =
  findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively(
    "file-size",
  );
if (
  fileSizeBasenameMatches.length === 1 &&
  fileSizeBasenameMatches[0] === "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
) {
  console.log("PROBE-2-PASS: short-name 'file-size' matches exactly 1 path (file-size-guard.ts)");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-2-FAIL: 'file-size' matches: \${JSON.stringify(fileSizeBasenameMatches)}\`);
}

// Probe 3: case-insensitivity — "FILE-SIZE" must equal "file-size" matches
const uppercaseFileSizeMatches =
  findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively(
    "FILE-SIZE",
  );
if (
  uppercaseFileSizeMatches.length === fileSizeBasenameMatches.length &&
  uppercaseFileSizeMatches.every((path, index) => path === fileSizeBasenameMatches[index])
) {
  console.log("PROBE-3-PASS: case-insensitive — uppercase 'FILE-SIZE' returns identical matches to lowercase 'file-size'");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-3-FAIL: case-insensitivity broken (lower=\${JSON.stringify(fileSizeBasenameMatches)}, UPPER=\${JSON.stringify(uppercaseFileSizeMatches)})\`);
}

// Probe 3b: unrelated query returns empty array
const unrelatedQueryMatches =
  findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively(
    "xyzzy-iter120-bogus",
  );
if (unrelatedQueryMatches.length === 0) {
  console.log("PROBE-3B-PASS: unrelated query returns empty array (no false positives)");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-3B-FAIL: unrelated query matched: \${JSON.stringify(unrelatedQueryMatches)}\`);
}

if (!allProbesPassed) process.exit(1);
EOF

set +e
PROBE_OUTPUT=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
PROBE_EXIT_CODE=$?
set -e

if [[ "$PROBE_OUTPUT" == *"PROBE-2-PASS"* ]]; then
    assert_passes "Case 2: accessor returns expected match for short-name query 'file-size'"
else
    assert_fails "Case 2: accessor probe failed (output=$PROBE_OUTPUT)"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-3-PASS"* ]] && [[ "$PROBE_OUTPUT" == *"PROBE-3B-PASS"* ]]; then
    assert_passes "Case 3: accessor is case-insensitive (FILE-SIZE == file-size) AND returns empty array on unrelated query (no false positives)"
else
    assert_fails "Case 3: case-insensitivity or unrelated-query probe failed (exit=$PROBE_EXIT_CODE)"
fi

# ─── Case 4: CLI catches basename-substring query before Levenshtein ────
set +e
CLI_BASENAME_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "file-size-guard" 2>&1)
CLI_BASENAME_EXIT_CODE=$?
set -e
if [[ "$CLI_BASENAME_EXIT_CODE" -eq 0 ]] && \
   [[ "$CLI_BASENAME_OUTPUT" == *"basename contains your query"* ]] && \
   [[ "$CLI_BASENAME_OUTPUT" == *"FILE-SIZE-OK"* ]] && \
   [[ "$CLI_BASENAME_OUTPUT" != *"Did you mean"* ]]; then
    assert_passes "Case 4: CLI catches short-name 'file-size-guard' via basename-substring search (exit 0, surfaces FILE-SIZE-OK marker, does NOT fall through to Levenshtein 'Did you mean?' branch)"
else
    assert_fails "Case 4: CLI did not catch short-name via basename-substring (exit=$CLI_BASENAME_EXIT_CODE)"
fi

# ─── Case 5: CLI skips basename-substring when query contains a slash ────
# A query with a slash means operator typed a fully-qualified path. Even
# if a substring of the basename would match, the basename-substring
# branch should be SKIPPED so iter-118 Levenshtein can handle the typo.
# Use a query with slash that does NOT have an exact registered path
# match, and whose basename ("file-size" — appears in basename of
# pretooluse-file-size-guard.ts) WOULD match basename-substring if not
# skipped. The Levenshtein branch should fire instead.
set +e
CLI_SLASH_QUERY_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "wrong/dir/file-size-guard.ts" 2>&1)
CLI_SLASH_QUERY_EXIT_CODE=$?
set -e
if [[ "$CLI_SLASH_QUERY_EXIT_CODE" -eq 2 ]] && \
   [[ "$CLI_SLASH_QUERY_OUTPUT" != *"basename contains your query"* ]]; then
    assert_passes "Case 5: CLI skips basename-substring search when query contains a '/' (operator meant a fully-qualified path; iter-118 Levenshtein/full-list branches handle it)"
else
    assert_fails "Case 5: CLI did NOT skip basename-substring on slash-containing query (exit=$CLI_SLASH_QUERY_EXIT_CODE) — should have fallen through to iter-118"
fi

# ─── Case 6: JSON mode on basename match ─────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
    assert_fails "Case 6: jq is required to verify --json output but was not found on PATH"
else
    set +e
    JSON_BASENAME_STDOUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "file-size" 2>/dev/null)
    JSON_BASENAME_EXIT_CODE=$?
    set -e
    JSON_BASENAME_STATUS=$(echo "$JSON_BASENAME_STDOUT" | jq -r '.status' 2>/dev/null || echo "JQ_PARSE_ERROR")
    JSON_BASENAME_MATCH_TYPE=$(echo "$JSON_BASENAME_STDOUT" | jq -r '.matchType' 2>/dev/null || echo "JQ_PARSE_ERROR")
    JSON_BASENAME_MATCHING_PATHS_LENGTH=$(echo "$JSON_BASENAME_STDOUT" | jq -r '.matchingConsumerSourceFilePaths | length' 2>/dev/null || echo "JQ_PARSE_ERROR")
    JSON_BASENAME_FIRST_MARKER=$(echo "$JSON_BASENAME_STDOUT" | jq -r '.markers[0].markerNameTokenIncludingSuffix' 2>/dev/null || echo "JQ_PARSE_ERROR")
    if [[ "$JSON_BASENAME_EXIT_CODE" -eq 0 ]] && \
       [[ "$JSON_BASENAME_STATUS" == "found" ]] && \
       [[ "$JSON_BASENAME_MATCH_TYPE" == "basename-substring" ]] && \
       [[ "$JSON_BASENAME_MATCHING_PATHS_LENGTH" -ge 1 ]] && \
       [[ "$JSON_BASENAME_FIRST_MARKER" == "FILE-SIZE-OK" ]]; then
        assert_passes "Case 6: --json on basename query emits status=found + matchType=basename-substring + matchingConsumerSourceFilePaths + markers (parseable by jq)"
    else
        assert_fails "Case 6: --json basename-branch shape wrong (status=$JSON_BASENAME_STATUS, matchType=$JSON_BASENAME_MATCH_TYPE, matchingPathsLen=$JSON_BASENAME_MATCHING_PATHS_LENGTH, firstMarker=$JSON_BASENAME_FIRST_MARKER, exit=$JSON_BASENAME_EXIT_CODE)"
    fi
fi

# ─── Case 7: JSON mode on exact match emits matchType=exact ──────────────
set +e
JSON_EXACT_STDOUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts" 2>/dev/null)
JSON_EXACT_EXIT_CODE=$?
set -e
JSON_EXACT_STATUS=$(echo "$JSON_EXACT_STDOUT" | jq -r '.status' 2>/dev/null || echo "JQ_PARSE_ERROR")
JSON_EXACT_MATCH_TYPE=$(echo "$JSON_EXACT_STDOUT" | jq -r '.matchType' 2>/dev/null || echo "JQ_PARSE_ERROR")
if [[ "$JSON_EXACT_EXIT_CODE" -eq 0 ]] && \
   [[ "$JSON_EXACT_STATUS" == "found" ]] && \
   [[ "$JSON_EXACT_MATCH_TYPE" == "exact" ]]; then
    assert_passes "Case 7: --json on exact-path-match emits matchType=exact (symmetric with iter-120 matchType=basename-substring — operators can disambiguate the lookup mode that resolved their query)"
else
    assert_fails "Case 7: --json exact-path-match did NOT emit matchType=exact (status=$JSON_EXACT_STATUS, matchType=$JSON_EXACT_MATCH_TYPE)"
fi

# ─── Case 8: iter-118 Levenshtein not regressed on full-path typo ───────
set +e
CLI_LEVENSHTEIN_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "plugins/itp-hooks/hooks/pretooluse-file-size-guards.ts" 2>&1)
CLI_LEVENSHTEIN_EXIT_CODE=$?
set -e
if [[ "$CLI_LEVENSHTEIN_EXIT_CODE" -eq 2 ]] && \
   [[ "$CLI_LEVENSHTEIN_OUTPUT" == *"Did you mean"* ]] && \
   [[ "$CLI_LEVENSHTEIN_OUTPUT" == *"[1 edit]"* ]] && \
   [[ "$CLI_LEVENSHTEIN_OUTPUT" != *"basename contains your query"* ]]; then
    assert_passes "Case 8: iter-118 Levenshtein 'Did you mean?' still triggers on plausible-typo full-path query (slash present → basename-substring skipped → falls through to Levenshtein → close-match found)"
else
    assert_fails "Case 8: iter-118 Levenshtein branch regressed (exit=$CLI_LEVENSHTEIN_EXIT_CODE)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-120 regression — Summary"
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
echo "  🚀 Iter-120 basename-substring search established. The iter-116 CLI"
echo "     fallback chain is now:"
echo "       1. exact-path-match               (iter-116 default)"
echo "       2. basename-substring             (iter-120 NEW)"
echo "       3. Levenshtein Did-you-mean       (iter-118)"
echo "       4. full-list dump                 (iter-116 default)"
echo "     Operators who know only the consumer's short name now get useful"
echo "     results instead of iter-118's unhelpful full-list fallback. The"
echo "     basename-substring step is intentionally skipped when the query"
echo "     contains a '/' (operator clearly meant a fully-qualified path;"
echo "     iter-118 Levenshtein is the right tool for that case)."
echo "  🚀 Iter-121+ queue:"
echo "     - Stale-description audit (task #144): verify every registry"
echo "       entry's operator-doc description field mentions a hook/task"
echo "       name consistent with declared consumer-path. Wire as preflight"
echo "       Check 4v informational."
