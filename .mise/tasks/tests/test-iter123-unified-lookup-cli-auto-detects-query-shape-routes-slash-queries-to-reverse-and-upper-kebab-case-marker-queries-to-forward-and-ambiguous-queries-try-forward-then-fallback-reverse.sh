#!/usr/bin/env bash
#MISE description="Iter-123 regression test for the unified lookup CLI that auto-detects query shape and dispatches to iter-116 reverse-search OR iter-122 forward-search without forcing the operator to choose direction. Verifies (1) classifier library exports the documented constants and classification function with discriminated-union return shape; (2) classifier returns REVERSE_SEARCH_ITER116_CONFIDENT for queries containing '/'; (3) classifier returns FORWARD_SEARCH_ITER122_CONFIDENT for strict UPPER-KEBAB-CASE markers ending in OK/SKIP/WRAP; (4) classifier handles grandfathered SSoT-OK mixed-case marker token; (5) classifier returns AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE for queries with no slash and not matching strict marker regex; (6) CLI dispatches path queries to reverse-search backend with routing rationale visible in stderr/stdout; (7) CLI dispatches marker queries to forward-search backend with routing rationale; (8) CLI ambiguous queries try forward first then fall back to reverse when forward returns no hits; (9) --direction=forward and --direction=reverse explicit overrides bypass auto-detect; (10) --json mode emits iter123UnifiedLookupEnvelope wrapping the dispatchedBackendResponse with classifierRationale + effectiveRoutingRationale + dispatchedBackend fields."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER123_CLASSIFIER_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/iter123-unified-lookup-query-shape-auto-detection-router-dispatching-to-iter116-reverse-or-iter122-forward-search-direction-based-on-slash-and-upper-kebab-case-marker-shape-heuristics.ts"
ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-or-consumer-path-auto-detecting-query-shape-via-iter123-unified-router-dispatching-to-iter116-reverse-or-iter122-forward-search.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-123 unified lookup CLI auto-detection regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: classifier lib exports documented symbols ────────────────────
EXPECTED_ITER123_EXPORTS=(
    "CANONICAL_UPPER_KEBAB_CASE_MARKER_NAME_REGEX_INCLUDING_SUFFIX_FAMILY"
    "GRANDFATHERED_MIXED_CASE_MARKER_NAME_TOKENS_NOT_MATCHING_STRICT_UPPER_KEBAB_REGEX"
    "classifyOperatorQueryShapeForUnifiedLookupDispatchRouting"
)
MISSING_ITER123_EXPORT_COUNT=0
for expected_export_name in "${EXPECTED_ITER123_EXPORTS[@]}"; do
    if ! grep -qE "^export (const|function|type) ${expected_export_name}" "$ITER123_CLASSIFIER_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH"; then
        MISSING_ITER123_EXPORT_COUNT=$((MISSING_ITER123_EXPORT_COUNT + 1))
        echo "    [diag] missing exported symbol: $expected_export_name"
    fi
done
if [[ "$MISSING_ITER123_EXPORT_COUNT" -eq 0 ]]; then
    assert_passes "Case 1: iter-123 classifier lib exports canonical regex constant + grandfathered set constant + classification function"
else
    assert_fails "Case 1: $MISSING_ITER123_EXPORT_COUNT iter-123 export(s) missing"
fi

# ─── Cases 2-5: TypeScript probe exercising classifier directly ───────────
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter123-classifier-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/iter123-classifier-probe.ts" <<EOF
import {
  classifyOperatorQueryShapeForUnifiedLookupDispatchRouting,
} from "$ITER123_CLASSIFIER_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH";

let allProbesPassed = true;

const slashQueryResult = classifyOperatorQueryShapeForUnifiedLookupDispatchRouting(
  "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts",
);
if (slashQueryResult.classifiedDispatchDirectionTag === "REVERSE_SEARCH_ITER116_CONFIDENT") {
  console.log("PROBE-2-PASS: slash-containing query classified REVERSE_SEARCH_ITER116_CONFIDENT");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-2-FAIL: slash query returned \${slashQueryResult.classifiedDispatchDirectionTag}\`);
}

const markerQueryResult = classifyOperatorQueryShapeForUnifiedLookupDispatchRouting("FILE-SIZE-OK");
if (markerQueryResult.classifiedDispatchDirectionTag === "FORWARD_SEARCH_ITER122_CONFIDENT") {
  console.log("PROBE-3-PASS: UPPER-KEBAB-CASE marker query classified FORWARD_SEARCH_ITER122_CONFIDENT");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-3-FAIL: marker query returned \${markerQueryResult.classifiedDispatchDirectionTag}\`);
}

const grandfatheredQueryResult = classifyOperatorQueryShapeForUnifiedLookupDispatchRouting("SSoT-OK");
if (grandfatheredQueryResult.classifiedDispatchDirectionTag === "FORWARD_SEARCH_ITER122_CONFIDENT") {
  console.log("PROBE-4-PASS: grandfathered mixed-case marker SSoT-OK classified FORWARD_SEARCH_ITER122_CONFIDENT");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-4-FAIL: SSoT-OK returned \${grandfatheredQueryResult.classifiedDispatchDirectionTag}\`);
}

const ambiguousQueryResult = classifyOperatorQueryShapeForUnifiedLookupDispatchRouting("file-size-guard");
if (ambiguousQueryResult.classifiedDispatchDirectionTag === "AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE") {
  console.log("PROBE-5-PASS: ambiguous basename-shape query (no slash, lowercase, no canonical suffix) classified AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-5-FAIL: ambiguous query returned \${ambiguousQueryResult.classifiedDispatchDirectionTag}\`);
}

if (!allProbesPassed) process.exit(1);
EOF

set +e
PROBE_OUTPUT=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/iter123-classifier-probe.ts" 2>&1)
PROBE_EXIT_CODE=$?
set -e

if [[ "$PROBE_OUTPUT" == *"PROBE-2-PASS"* ]]; then
    assert_passes "Case 2: slash-containing query 'plugins/.../foo.ts' classifies as REVERSE_SEARCH_ITER116_CONFIDENT (Rule 1: path-shape)"
else
    assert_fails "Case 2: slash-query classification broken (probe output=$PROBE_OUTPUT)"
fi
if [[ "$PROBE_OUTPUT" == *"PROBE-3-PASS"* ]]; then
    assert_passes "Case 3: strict UPPER-KEBAB-CASE marker query 'FILE-SIZE-OK' classifies as FORWARD_SEARCH_ITER122_CONFIDENT (Rule 2: canonical marker regex)"
else
    assert_fails "Case 3: marker-query classification broken (probe exit=$PROBE_EXIT_CODE)"
fi
if [[ "$PROBE_OUTPUT" == *"PROBE-4-PASS"* ]]; then
    assert_passes "Case 4: grandfathered mixed-case 'SSoT-OK' classifies as FORWARD_SEARCH_ITER122_CONFIDENT (Rule 3: grandfathered exception set, NOT relying on strict UPPER-CASE regex)"
else
    assert_fails "Case 4: grandfathered-marker classification broken"
fi
if [[ "$PROBE_OUTPUT" == *"PROBE-5-PASS"* ]]; then
    assert_passes "Case 5: ambiguous 'file-size-guard' (no slash, lowercase, no -OK/-SKIP/-WRAP suffix) classifies as AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE (Rule 4: fallthrough)"
else
    assert_fails "Case 5: ambiguous-classification fallthrough broken"
fi

# ─── Case 6: CLI dispatches slash queries to reverse-search backend ───────
set +e
SLASH_DISPATCH_OUTPUT=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts" 2>&1)
SLASH_DISPATCH_EXIT_CODE=$?
set -e
if [[ "$SLASH_DISPATCH_EXIT_CODE" -eq 0 ]] && \
   [[ "$SLASH_DISPATCH_OUTPUT" == *"iter-116 reverse-search"* ]] && \
   [[ "$SLASH_DISPATCH_OUTPUT" == *"Found 1 escape-hatch marker"* ]]; then
    assert_passes "Case 6: CLI auto-routes slash query to iter-116 reverse-search; rationale visible; backend finds the marker"
else
    assert_fails "Case 6: slash-query dispatch broken (exit=$SLASH_DISPATCH_EXIT_CODE)"
fi

# ─── Case 7: CLI dispatches marker queries to forward-search backend ──────
set +e
MARKER_DISPATCH_OUTPUT=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" "FILE-SIZE-OK" 2>&1)
MARKER_DISPATCH_EXIT_CODE=$?
set -e
if [[ "$MARKER_DISPATCH_EXIT_CODE" -eq 0 ]] && \
   [[ "$MARKER_DISPATCH_OUTPUT" == *"iter-122 forward-search"* ]] && \
   [[ "$MARKER_DISPATCH_OUTPUT" == *"Found 1 canonical registry entry"* ]]; then
    assert_passes "Case 7: CLI auto-routes UPPER-KEBAB-CASE marker query to iter-122 forward-search; rationale visible; backend finds the registry entry"
else
    assert_fails "Case 7: marker-query dispatch broken (exit=$MARKER_DISPATCH_EXIT_CODE)"
fi

# ─── Case 8: ambiguous query tries forward then falls back to reverse ────
set +e
AMBIGUOUS_DISPATCH_OUTPUT=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" "file-size-guard" 2>&1)
AMBIGUOUS_DISPATCH_EXIT_CODE=$?
set -e
if [[ "$AMBIGUOUS_DISPATCH_EXIT_CODE" -eq 0 ]] && \
   [[ "$AMBIGUOUS_DISPATCH_OUTPUT" == *"Attempting forward search first"* ]] && \
   [[ "$AMBIGUOUS_DISPATCH_OUTPUT" == *"falling back to reverse search"* ]] && \
   [[ "$AMBIGUOUS_DISPATCH_OUTPUT" == *"basename contains your query"* ]]; then
    assert_passes "Case 8: ambiguous 'file-size-guard' query tries iter-122 forward FIRST (returns no-hit) then falls back to iter-116 reverse which resolves via iter-120 basename-substring"
else
    assert_fails "Case 8: ambiguous-fallback chain broken (exit=$AMBIGUOUS_DISPATCH_EXIT_CODE)"
fi

# ─── Case 9: --direction=forward and --direction=reverse explicit overrides ────
set +e
EXPLICIT_FORWARD_OUTPUT=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" --direction=forward "FILE-SIZE-OK" 2>&1)
EXPLICIT_FORWARD_EXIT_CODE=$?
EXPLICIT_REVERSE_OUTPUT=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" --direction=reverse "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts" 2>&1)
EXPLICIT_REVERSE_EXIT_CODE=$?
EXPLICIT_BAD_OUTPUT=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" --direction=sideways "FILE-SIZE-OK" 2>&1)
EXPLICIT_BAD_EXIT_CODE=$?
set -e
if [[ "$EXPLICIT_FORWARD_EXIT_CODE" -eq 0 ]] && \
   [[ "$EXPLICIT_FORWARD_OUTPUT" == *"operator --direction=forward override"* ]] && \
   [[ "$EXPLICIT_REVERSE_EXIT_CODE" -eq 0 ]] && \
   [[ "$EXPLICIT_REVERSE_OUTPUT" == *"operator --direction=reverse override"* ]] && \
   [[ "$EXPLICIT_BAD_EXIT_CODE" -eq 1 ]] && \
   [[ "$EXPLICIT_BAD_OUTPUT" == *"invalid --direction value"* ]] && \
   [[ "$EXPLICIT_BAD_OUTPUT" == *"expected forward|reverse|auto"* ]]; then
    assert_passes "Case 9: --direction=forward + --direction=reverse explicit overrides bypass auto-detect; --direction=sideways rejected with usage error (exit 1) AND surfaces 'expected forward|reverse|auto' diagnostic"
else
    assert_fails "Case 9: explicit --direction override or bad-value rejection broken (forward=$EXPLICIT_FORWARD_EXIT_CODE, reverse=$EXPLICIT_REVERSE_EXIT_CODE, bad-exit=$EXPLICIT_BAD_EXIT_CODE, bad-output-snippet=${EXPLICIT_BAD_OUTPUT:0:100})"
fi

# ─── Case 10: --json mode emits iter123UnifiedLookupEnvelope shape ────────
if ! command -v jq >/dev/null 2>&1; then
    assert_fails "Case 10: jq required to verify --json envelope but not on PATH"
else
    set +e
    JSON_MARKER_ENVELOPE=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" --json "FILE-SIZE-OK" 2>/dev/null)
    JSON_PATH_ENVELOPE=$(bash "$ITER123_UNIFIED_LOOKUP_CLI_ABSOLUTE_PATH" --json "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts" 2>/dev/null)
    set -e
    MARKER_ENVELOPE_DISPATCHED_BACKEND=$(echo "$JSON_MARKER_ENVELOPE" | jq -r '.iter123UnifiedLookupEnvelope.dispatchedBackend' 2>/dev/null)
    MARKER_ENVELOPE_CLASSIFIED_TAG=$(echo "$JSON_MARKER_ENVELOPE" | jq -r '.iter123UnifiedLookupEnvelope.classifiedDispatchDirectionTag' 2>/dev/null)
    MARKER_ENVELOPE_BACKEND_STATUS=$(echo "$JSON_MARKER_ENVELOPE" | jq -r '.dispatchedBackendResponse.status' 2>/dev/null)
    PATH_ENVELOPE_DISPATCHED_BACKEND=$(echo "$JSON_PATH_ENVELOPE" | jq -r '.iter123UnifiedLookupEnvelope.dispatchedBackend' 2>/dev/null)
    PATH_ENVELOPE_CLASSIFIED_TAG=$(echo "$JSON_PATH_ENVELOPE" | jq -r '.iter123UnifiedLookupEnvelope.classifiedDispatchDirectionTag' 2>/dev/null)
    if [[ "$MARKER_ENVELOPE_DISPATCHED_BACKEND" == "iter122-forward-search" ]] && \
       [[ "$MARKER_ENVELOPE_CLASSIFIED_TAG" == "FORWARD_SEARCH_ITER122_CONFIDENT" ]] && \
       [[ "$MARKER_ENVELOPE_BACKEND_STATUS" == "found" ]] && \
       [[ "$PATH_ENVELOPE_DISPATCHED_BACKEND" == "iter116-reverse-search" ]] && \
       [[ "$PATH_ENVELOPE_CLASSIFIED_TAG" == "REVERSE_SEARCH_ITER116_CONFIDENT" ]]; then
        assert_passes "Case 10: --json mode wraps backend response in iter123UnifiedLookupEnvelope with classifiedDispatchDirectionTag + dispatchedBackend + nested dispatchedBackendResponse intact for both marker and path queries"
    else
        assert_fails "Case 10: --json envelope shape broken (marker: backend=$MARKER_ENVELOPE_DISPATCHED_BACKEND, tag=$MARKER_ENVELOPE_CLASSIFIED_TAG, status=$MARKER_ENVELOPE_BACKEND_STATUS; path: backend=$PATH_ENVELOPE_DISPATCHED_BACKEND, tag=$PATH_ENVELOPE_CLASSIFIED_TAG)"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-123 regression — Summary"
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
echo "  🚀 Iter-123 unified lookup CLI established. The marketplace now ships"
echo "     a single operator entry point that auto-detects query shape and"
echo "     dispatches to the iter-116 reverse-search OR iter-122 forward-search"
echo "     backend, eliminating the dispatch decision from the operator workflow."
echo ""
echo "     Classification rules (top-to-bottom precedence):"
echo "       1. Query contains '/'        → CONFIDENT path     → iter-116 reverse"
echo "       2. UPPER-KEBAB-CASE marker   → CONFIDENT marker   → iter-122 forward"
echo "       3. Grandfathered SSoT-OK     → CONFIDENT marker   → iter-122 forward"
echo "       4. Anything else (ambiguous) → try forward first  → fall back to reverse"
echo ""
echo "     The iter-116 and iter-122 CLIs remain available as explicit-direction"
echo "     escape hatches (operators can also use --direction=forward|reverse"
echo "     on this unified CLI to bypass auto-detect)."
echo ""
echo "  🚀 Iter-124+ queue:"
echo "     - Promote iter-121 stale-description audit to STRICT-BLOCK after a"
echo "       few release cycles confirm baseline-clean state."
echo "     - Consider deprecating direct invocation of iter-116/iter-122 CLIs"
echo "       in favor of the iter-123 unified entry point (after operators have"
echo "       had time to adopt the new task name)."
echo "     - Broaden scope beyond the escape-hatch-marker reference ecosystem"
echo "       — the iter-107 through iter-123 arc has reached operator-facing"
echo "       maturity; next adversarial-audit iteration should look elsewhere."
