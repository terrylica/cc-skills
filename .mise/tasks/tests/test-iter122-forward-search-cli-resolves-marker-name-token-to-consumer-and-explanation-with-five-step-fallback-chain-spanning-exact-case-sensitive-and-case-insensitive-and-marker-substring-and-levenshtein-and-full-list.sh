#!/usr/bin/env bash
#MISE description="Iter-122 regression test for the forward-search CLI symmetric to iter-116 reverse-search. Verifies (1) the iter-122 forward-search accessor lib exports the six documented functions; (2) Step 1 — exact case-sensitive match resolves FILE-SIZE-OK to its iter-111 registry entry; (3) Step 2 — case-insensitive fallback resolves lowercase file-size-ok to canonical FILE-SIZE-OK; (4) Step 3 — substring search on marker tokens resolves partial query TTY to both CARGO-TTY-SKIP and CARGO-TTY-WRAP; (5) Step 4 — Levenshtein Did-You-Mean fires on typo FIEL-SIZE-OK proposing FILE-SIZE-OK with distance 2 within ⌊queryLen/3⌋ threshold; (6) Step 5 — full-list dump emits when query unrelated to every registered marker; (7) iter-119-parallel --json mode emits matchType=exact|exact-case-insensitive|marker-substring on found paths and didYouMean array on plausible-typo not-found; (8) exit-code contract — 0 found at any layer, 2 unknown after all fallbacks, 1 usage error; (9) cross-registry parity — audit-task marker SPAWN-SYNC-OK from iter-114 registry resolves through Step 1 with lifecycleLayer=audit-task; (10) renderer produces well-formed terminal block with Marker/Lifecycle/Consumer/Reason/What-it-does/Example fields."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER122_FORWARD_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-forward-search-accessor-by-marker-name-token-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter122.ts"
ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-explanation-by-marker-name-token-via-iter122-forward-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-122 forward-search CLI regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: forward-search accessor lib exports documented functions ────
EXPECTED_FORWARD_SEARCH_EXPORTS=(
    "lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries"
    "lookupAllCanonicalRegistryEntriesByMarkerNameTokenCaseInsensitivelySpanningBothRegistries"
    "findAllRegisteredMarkerNameTokensWhoseTokenContainsQueryStringCaseInsensitively"
    "rankAllRegisteredMarkerNameTokensByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches"
    "listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically"
    "renderSingleForwardSearchHitAsHumanReadableTerminalBlock"
)
MISSING_FORWARD_SEARCH_EXPORT_COUNT=0
for expected_export_function_name in "${EXPECTED_FORWARD_SEARCH_EXPORTS[@]}"; do
    if ! grep -qE "^export function ${expected_export_function_name}" "$ITER122_FORWARD_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH"; then
        MISSING_FORWARD_SEARCH_EXPORT_COUNT=$((MISSING_FORWARD_SEARCH_EXPORT_COUNT + 1))
        echo "    [diag] missing exported function: $expected_export_function_name"
    fi
done
if [[ "$MISSING_FORWARD_SEARCH_EXPORT_COUNT" -eq 0 ]]; then
    assert_passes "Case 1: iter-122 forward-search accessor lib exports all 6 documented functions (exact, exact-CI, substring, Levenshtein-rank, distinct-list, renderer)"
else
    assert_fails "Case 1: $MISSING_FORWARD_SEARCH_EXPORT_COUNT iter-122 forward-search lib export(s) missing"
fi

# ─── Case 2: Step 1 — exact case-sensitive resolves FILE-SIZE-OK ────────
set +e
STEP1_EXACT_OUTPUT=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "FILE-SIZE-OK" 2>&1)
STEP1_EXACT_EXIT_CODE=$?
set -e
if [[ "$STEP1_EXACT_EXIT_CODE" -eq 0 ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Found 1 canonical registry entry"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"FILE-SIZE-OK"* ]]; then
    assert_passes "Case 2: Step 1 exact case-sensitive match resolves FILE-SIZE-OK to iter-111 runtime-hook entry (consumer=pretooluse-file-size-guard.ts)"
else
    assert_fails "Case 2: Step 1 exact case-sensitive match broken (exit=$STEP1_EXACT_EXIT_CODE)"
fi

# ─── Case 3: Step 2 — case-insensitive fallback ──────────────────────────
set +e
STEP2_CI_OUTPUT=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "file-size-ok" 2>&1)
STEP2_CI_EXIT_CODE=$?
set -e
if [[ "$STEP2_CI_EXIT_CODE" -eq 0 ]] && \
   [[ "$STEP2_CI_OUTPUT" == *"matches canonical \"FILE-SIZE-OK\" (case-insensitive)"* ]] && \
   [[ "$STEP2_CI_OUTPUT" == *"pretooluse-file-size-guard.ts"* ]]; then
    assert_passes "Case 3: Step 2 case-insensitive fallback resolves lowercase 'file-size-ok' to canonical 'FILE-SIZE-OK' (surfaces canonical-name-vs-operator-typed-name disambiguation in the human-readable narrative)"
else
    assert_fails "Case 3: Step 2 case-insensitive fallback broken (exit=$STEP2_CI_EXIT_CODE)"
fi

# ─── Case 4: Step 3 — substring search on marker tokens ─────────────────
set +e
STEP3_SUBSTR_OUTPUT=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "TTY" 2>&1)
STEP3_SUBSTR_EXIT_CODE=$?
set -e
if [[ "$STEP3_SUBSTR_EXIT_CODE" -eq 0 ]] && \
   [[ "$STEP3_SUBSTR_OUTPUT" == *"found 2 markers whose token contains your query"* ]] && \
   [[ "$STEP3_SUBSTR_OUTPUT" == *"CARGO-TTY-SKIP"* ]] && \
   [[ "$STEP3_SUBSTR_OUTPUT" == *"CARGO-TTY-WRAP"* ]]; then
    assert_passes "Case 4: Step 3 marker-substring case-insensitive search resolves 'TTY' to BOTH CARGO-TTY-SKIP + CARGO-TTY-WRAP (multi-hit demonstrating array-shape forward-lookup)"
else
    assert_fails "Case 4: Step 3 marker-substring search broken (exit=$STEP3_SUBSTR_EXIT_CODE)"
fi

# ─── Case 5: Step 4 — Levenshtein Did-You-Mean ──────────────────────────
set +e
STEP4_LEV_OUTPUT=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "FIEL-SIZE-OK" 2>&1)
STEP4_LEV_EXIT_CODE=$?
set -e
if [[ "$STEP4_LEV_EXIT_CODE" -eq 2 ]] && \
   [[ "$STEP4_LEV_OUTPUT" == *"Did you mean"* ]] && \
   [[ "$STEP4_LEV_OUTPUT" == *"[2 edits] FILE-SIZE-OK"* ]]; then
    assert_passes "Case 5: Step 4 Levenshtein Did-You-Mean fires on typo 'FIEL-SIZE-OK', top suggestion is canonical 'FILE-SIZE-OK' with distance 2 (within ⌊12/3⌋=4 threshold)"
else
    assert_fails "Case 5: Step 4 Levenshtein typo correction broken (exit=$STEP4_LEV_EXIT_CODE)"
fi

# ─── Case 6: Step 5 — full-list dump on truly-unrelated query ───────────
set +e
STEP5_UNRELATED_OUTPUT=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "ZZZ-XYZZY-NEVER-REGISTERED-OK" 2>&1)
STEP5_UNRELATED_EXIT_CODE=$?
set -e
if [[ "$STEP5_UNRELATED_EXIT_CODE" -eq 2 ]] && \
   [[ "$STEP5_UNRELATED_OUTPUT" == *"Showing all "*"registered marker tokens"* ]] && \
   [[ "$STEP5_UNRELATED_OUTPUT" != *"Did you mean"* ]]; then
    assert_passes "Case 6: Step 5 full-list dump emits when query is truly unrelated (no Did-You-Mean since top Levenshtein candidate exceeds threshold)"
else
    assert_fails "Case 6: Step 5 full-list dump broken (exit=$STEP5_UNRELATED_EXIT_CODE)"
fi

# ─── Case 7: --json mode emits matchType across all branches ────────────
if ! command -v jq >/dev/null 2>&1; then
    assert_fails "Case 7: jq required to verify --json output but not on PATH"
else
    set +e
    JSON_EXACT=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "FILE-SIZE-OK" 2>/dev/null)
    JSON_EXACT_CI=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "file-size-ok" 2>/dev/null)
    JSON_SUBSTR=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "TTY" 2>/dev/null)
    JSON_TYPO=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "FIEL-SIZE-OK" 2>/dev/null)
    set -e
    MATCHTYPE_EXACT=$(echo "$JSON_EXACT" | jq -r '.matchType' 2>/dev/null)
    MATCHTYPE_EXACT_CI=$(echo "$JSON_EXACT_CI" | jq -r '.matchType' 2>/dev/null)
    MATCHTYPE_SUBSTR=$(echo "$JSON_SUBSTR" | jq -r '.matchType' 2>/dev/null)
    SUBSTR_HIT_COUNT=$(echo "$JSON_SUBSTR" | jq -r '.matchingMarkers | length' 2>/dev/null)
    TYPO_STATUS=$(echo "$JSON_TYPO" | jq -r '.status' 2>/dev/null)
    TYPO_DIDYOUMEAN_TOP=$(echo "$JSON_TYPO" | jq -r '.didYouMean[0].markerNameTokenIncludingSuffix' 2>/dev/null)
    if [[ "$MATCHTYPE_EXACT" == "exact" ]] && \
       [[ "$MATCHTYPE_EXACT_CI" == "exact-case-insensitive" ]] && \
       [[ "$MATCHTYPE_SUBSTR" == "marker-substring" ]] && \
       [[ "$SUBSTR_HIT_COUNT" -eq 2 ]] && \
       [[ "$TYPO_STATUS" == "not-found" ]] && \
       [[ "$TYPO_DIDYOUMEAN_TOP" == "FILE-SIZE-OK" ]]; then
        assert_passes "Case 7: --json mode emits all four matchType discriminators correctly (exact, exact-case-insensitive, marker-substring, not-found+didYouMean)"
    else
        assert_fails "Case 7: --json discriminators broken (exact=$MATCHTYPE_EXACT, ci=$MATCHTYPE_EXACT_CI, substr=$MATCHTYPE_SUBSTR/count=$SUBSTR_HIT_COUNT, typo-status=$TYPO_STATUS/top=$TYPO_DIDYOUMEAN_TOP)"
    fi
fi

# ─── Case 8: exit-code contract ─────────────────────────────────────────
if [[ "$STEP1_EXACT_EXIT_CODE" -eq 0 ]] && \
   [[ "$STEP2_CI_EXIT_CODE" -eq 0 ]] && \
   [[ "$STEP3_SUBSTR_EXIT_CODE" -eq 0 ]] && \
   [[ "$STEP4_LEV_EXIT_CODE" -eq 2 ]] && \
   [[ "$STEP5_UNRELATED_EXIT_CODE" -eq 2 ]]; then
    assert_passes "Case 8: exit-code contract (0=found at any fallback layer 1-3, 2=unknown after exhausting all fallbacks at layers 4-5) intact across all paths"
else
    assert_fails "Case 8: exit-code contract broken (step1=$STEP1_EXACT_EXIT_CODE step2=$STEP2_CI_EXIT_CODE step3=$STEP3_SUBSTR_EXIT_CODE step4=$STEP4_LEV_EXIT_CODE step5=$STEP5_UNRELATED_EXIT_CODE)"
fi

# ─── Case 9: cross-registry parity — audit-task marker from iter-114 ────
# Pick an audit-task marker (SPAWN-SYNC-OK lives only in iter-114). Verify
# Step 1 resolves it AND --json reports lifecycleLayer=audit-task.
set +e
JSON_AUDIT_MARKER=$(bash "$ITER122_FORWARD_SEARCH_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --json "SPAWN-SYNC-OK" 2>/dev/null)
JSON_AUDIT_MARKER_EXIT_CODE=$?
set -e
AUDIT_LIFECYCLE_LAYER=$(echo "$JSON_AUDIT_MARKER" | jq -r '.matchingMarkers[0].lifecycleLayer' 2>/dev/null)
AUDIT_REGISTRY_PROVENANCE=$(echo "$JSON_AUDIT_MARKER" | jq -r '.matchingMarkers[0].registryProvenanceTag' 2>/dev/null)
if [[ "$JSON_AUDIT_MARKER_EXIT_CODE" -eq 0 ]] && \
   [[ "$AUDIT_LIFECYCLE_LAYER" == "audit-task" ]] && \
   [[ "$AUDIT_REGISTRY_PROVENANCE" == "AUDIT_TASK_ITER114" ]]; then
    assert_passes "Case 9: cross-registry parity — audit-task marker SPAWN-SYNC-OK from iter-114 registry resolves through Step 1 with lifecycleLayer=audit-task + registryProvenanceTag=AUDIT_TASK_ITER114"
else
    assert_fails "Case 9: cross-registry parity broken (exit=$JSON_AUDIT_MARKER_EXIT_CODE, lifecycle=$AUDIT_LIFECYCLE_LAYER, provenance=$AUDIT_REGISTRY_PROVENANCE)"
fi

# ─── Case 10: renderer produces all expected fields ─────────────────────
if [[ "$STEP1_EXACT_OUTPUT" == *"Marker:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Lifecycle layer:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Consumer hook:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Case sensitivity:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Window semantics:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Reason policy:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"What it does:"* ]] && \
   [[ "$STEP1_EXACT_OUTPUT" == *"Example:"* ]]; then
    assert_passes "Case 10: renderer emits well-formed terminal block with all 8 expected fields (Marker, Lifecycle, Consumer, Case sensitivity, Window semantics, Reason policy, What it does, Example)"
else
    assert_fails "Case 10: renderer field set incomplete"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-122 regression — Summary"
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
echo "  🚀 Iter-122 forward-search CLI established. The marketplace now ships"
echo "     a bidirectional operator-facing lookup pair:"
echo ""
echo "       iter-116 reverse: consumer-path → marker name + description"
echo "       iter-122 forward: marker name  → consumer-path + description"
echo ""
echo "     Both share the same 4-step (iter-116) or 5-step (iter-122) fuzzy-"
echo "     fallback chain pattern, the same iter-119-parallel --json mode,"
echo "     and the same iter-118 Levenshtein helper. The iter-122 chain adds"
echo "     a Step 2 (case-insensitive exact match) catching operators who"
echo "     type lowercase by habit — possible because marker names have a"
echo "     canonical UPPER-KEBAB-CASE convention (iter-116 consumer paths"
echo "     have no canonical-case convention so the equivalent step is N/A)."
echo ""
echo "  🚀 Iter-123+ queue:"
echo "     - Document the bidirectional CLI pair in HOOKS.md operator workflow"
echo "       section, with side-by-side examples and decision tree"
echo "       ('do I know the marker name OR the consumer path?')."
echo "     - Promote iter-121 stale-description audit to STRICT-BLOCK once a"
echo "       few release cycles confirm baseline-clean state."
echo "     - Consider a unified 'lookup' CLI that auto-detects whether the"
echo "       operator query is a marker name (UPPER-KEBAB-CASE shape) or a"
echo "       consumer path (contains '/') and dispatches to the right backend."
