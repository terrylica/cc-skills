#!/usr/bin/env bash
#MISE description="Iter-116 regression test for the reverse-search registry accessor + operator-facing mise task. Verifies (1) accessor TypeScript file exists with all 3 documented exports (lookup function + list-all helper + render function) + the discriminated-union type alias; (2) single-marker reverse-lookup on a known runtime-hook consumer returns exactly 1 hit with RUNTIME_HOOK_ITER111 provenance tag; (3) multi-marker reverse-lookup on the cargo-tty-guard consumer returns exactly 2 hits both with RUNTIME_HOOK_ITER111 provenance tag covering both CARGO-TTY-SKIP and CARGO-TTY-WRAP; (4) reverse-lookup on a known audit-task consumer returns ≥1 hit with AUDIT_TASK_ITER114 provenance tag; (5) reverse-lookup on an unknown consumer path returns an empty array; (6) iter-116 operator-facing mise task exists + is executable + exits 0 with marker output on known consumer; (7) iter-116 operator-facing mise task exits 2 with 'Hint:' output on unknown consumer path; (8) iter-116 task exits 1 with usage message on --help."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts"
ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"

# Well-known consumers picked deliberately from each registry's baseline.
# These paths MUST stay in sync with the registries — a change here is
# either (a) a deliberate registry refactor that needs paired updates,
# or (b) a regression we want this test to surface.
KNOWN_SINGLE_MARKER_RUNTIME_HOOK_CONSUMER_PATH="plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
KNOWN_MULTI_MARKER_RUNTIME_HOOK_CONSUMER_PATH="plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts"
KNOWN_AUDIT_TASK_CONSUMER_PATH=".mise/tasks/audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null-which-cold-starts-bun-on-every-tool-call-causing-12-17ms-cpu-or-latency-waste-per-non-meaningful-invocation.sh"
# Use a path with NO shared prefix with any registered consumer path so
# the unknown-path branch deterministically lands in the full-list-dump
# fallback (Levenshtein distance to every registered path exceeds the
# iter-118 ⌊queryLen/3⌋ threshold, so the Did-you-mean branch is skipped).
# Previously this used "plugins/itp-hooks/hooks/..." which shares ≥23
# chars with every runtime-hook consumer path — that prefix overlap kept
# the distance below threshold and the iter-118 fuzzy-match correctly
# routed it to the Did-you-mean branch, breaking this test's assumption.
UNKNOWN_CONSUMER_PATH_GUARANTEED_NEVER_TO_APPEAR_IN_EITHER_REGISTRY="zzz/xyz/qqq-iter116-totally-unrelated-bogus-path-with-no-shared-prefix.aaa"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-116 reverse-search registry accessor regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: accessor file exists with documented exports ────────────────
if [[ -f "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH" ]] && \
   grep -qE "^export type EscapeHatchMarkerReverseSearchHitWithRegistryProvenanceTag" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function renderSingleReverseSearchHitAsHumanReadableTerminalBlock" "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-116 accessor file exists with all 4 documented exports (discriminated-union type + reverse-lookup function + list-all-distinct-paths helper + terminal renderer)"
else
    assert_fails "Case 1: iter-116 accessor file missing OR missing required exports"
fi

# ─── Cases 2-5: TypeScript probe exercising the accessor directly ────────
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter116-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import {
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries,
  listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically,
} from "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH";

let allProbesPassed = true;

// Probe 2: single-marker runtime-hook consumer
const singleMarkerHits =
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
    "$KNOWN_SINGLE_MARKER_RUNTIME_HOOK_CONSUMER_PATH",
  );
if (
  singleMarkerHits.length === 1 &&
  singleMarkerHits[0].originatingRegistryLifecycleLayerTag === "RUNTIME_HOOK_ITER111" &&
  singleMarkerHits[0].matchedRegistryEntry.markerNameTokenIncludingSuffix === "FILE-SIZE-OK"
) {
  console.log("PROBE-2-PASS: single-marker runtime-hook reverse-lookup returns 1 hit (FILE-SIZE-OK) with RUNTIME_HOOK_ITER111 provenance");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-2-FAIL: single-marker reverse-lookup returned \${JSON.stringify(singleMarkerHits)}\`);
}

// Probe 3: multi-marker runtime-hook consumer (cargo-tty-guard)
const multiMarkerHits =
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
    "$KNOWN_MULTI_MARKER_RUNTIME_HOOK_CONSUMER_PATH",
  );
const multiMarkerHitMarkerTokens = multiMarkerHits.map((hit) => hit.matchedRegistryEntry.markerNameTokenIncludingSuffix).toSorted();
if (
  multiMarkerHits.length === 2 &&
  multiMarkerHits.every((hit) => hit.originatingRegistryLifecycleLayerTag === "RUNTIME_HOOK_ITER111") &&
  multiMarkerHitMarkerTokens[0] === "CARGO-TTY-SKIP" &&
  multiMarkerHitMarkerTokens[1] === "CARGO-TTY-WRAP"
) {
  console.log("PROBE-3-PASS: multi-marker runtime-hook reverse-lookup returns 2 hits (CARGO-TTY-SKIP + CARGO-TTY-WRAP) both with RUNTIME_HOOK_ITER111 provenance");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-3-FAIL: multi-marker reverse-lookup returned \${JSON.stringify(multiMarkerHits)}\`);
}

// Probe 4: audit-task consumer
const auditTaskHits =
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
    "$KNOWN_AUDIT_TASK_CONSUMER_PATH",
  );
if (
  auditTaskHits.length >= 1 &&
  auditTaskHits.every((hit) => hit.originatingRegistryLifecycleLayerTag === "AUDIT_TASK_ITER114")
) {
  console.log(\`PROBE-4-PASS: audit-task reverse-lookup returns \${auditTaskHits.length} hit(s) all with AUDIT_TASK_ITER114 provenance\`);
} else {
  allProbesPassed = false;
  console.log(\`PROBE-4-FAIL: audit-task reverse-lookup returned \${JSON.stringify(auditTaskHits)}\`);
}

// Probe 5: unknown consumer path returns empty array
const unknownConsumerHits =
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
    "$UNKNOWN_CONSUMER_PATH_GUARANTEED_NEVER_TO_APPEAR_IN_EITHER_REGISTRY",
  );
if (unknownConsumerHits.length === 0) {
  console.log("PROBE-5-PASS: unknown consumer path returns empty array (no false positives)");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-5-FAIL: unknown consumer path returned \${JSON.stringify(unknownConsumerHits)}\`);
}

// Probe 5b: list-all-distinct-paths returns ≥ (12 + 8 - duplicates) distinct paths sorted alphabetically
const allDistinctConsumerPaths =
  listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically();
const isSortedAlphabetically = allDistinctConsumerPaths.every((path, index) => {
  if (index === 0) return true;
  return allDistinctConsumerPaths[index - 1].localeCompare(path) <= 0;
});
if (allDistinctConsumerPaths.length >= 15 && isSortedAlphabetically) {
  console.log(\`PROBE-5B-PASS: list-all-distinct-paths returns \${allDistinctConsumerPaths.length} distinct paths sorted alphabetically\`);
} else {
  allProbesPassed = false;
  console.log(\`PROBE-5B-FAIL: list-all-distinct-paths returned \${allDistinctConsumerPaths.length} paths, sorted=\${isSortedAlphabetically}\`);
}

if (!allProbesPassed) process.exit(1);
EOF

set +e
PROBE_OUTPUT=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
PROBE_EXIT_CODE=$?
set -e

if [[ "$PROBE_OUTPUT" == *"PROBE-2-PASS"* ]]; then
    assert_passes "Case 2: single-marker reverse-lookup on file-size-guard returns 1 hit (FILE-SIZE-OK) with RUNTIME_HOOK_ITER111 provenance tag"
else
    assert_fails "Case 2: single-marker reverse-lookup probe failed (output=$PROBE_OUTPUT)"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-3-PASS"* ]]; then
    assert_passes "Case 3: multi-marker reverse-lookup on cargo-tty-guard returns exactly 2 hits (CARGO-TTY-SKIP + CARGO-TTY-WRAP) both with RUNTIME_HOOK_ITER111 provenance tag"
else
    assert_fails "Case 3: multi-marker reverse-lookup probe failed"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-4-PASS"* ]]; then
    assert_passes "Case 4: reverse-lookup on a known audit-task consumer returns ≥1 hit all with AUDIT_TASK_ITER114 provenance tag"
else
    assert_fails "Case 4: audit-task reverse-lookup probe failed"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-5-PASS"* ]] && [[ "$PROBE_OUTPUT" == *"PROBE-5B-PASS"* ]]; then
    assert_passes "Case 5: unknown consumer path returns empty array (no false positives) AND list-all-distinct-paths returns ≥15 paths sorted alphabetically"
else
    assert_fails "Case 5: unknown-path or list-all-distinct-paths probe failed (exit=$PROBE_EXIT_CODE)"
fi

# ─── Case 6: operator-facing mise task exists + works on known consumer ──
if [[ ! -x "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" ]]; then
    assert_fails "Case 6: iter-116 operator-facing mise task missing or not executable: $ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH"
else
    set +e
    KNOWN_CONSUMER_TASK_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "$KNOWN_SINGLE_MARKER_RUNTIME_HOOK_CONSUMER_PATH" 2>&1)
    KNOWN_CONSUMER_TASK_EXIT_CODE=$?
    set -e
    if [[ "$KNOWN_CONSUMER_TASK_EXIT_CODE" -eq 0 ]] && \
       [[ "$KNOWN_CONSUMER_TASK_OUTPUT" == *"FILE-SIZE-OK"* ]] && \
       [[ "$KNOWN_CONSUMER_TASK_OUTPUT" == *"Found 1 escape-hatch marker"* ]]; then
        assert_passes "Case 6: iter-116 operator-facing mise task exists + executable + exits 0 with FILE-SIZE-OK marker output on known consumer (file-size-guard)"
    else
        assert_fails "Case 6: iter-116 task failed on known consumer (exit=$KNOWN_CONSUMER_TASK_EXIT_CODE)"
    fi
fi

# ─── Case 7: operator-facing mise task on unknown consumer path ──────────
set +e
UNKNOWN_CONSUMER_TASK_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" "$UNKNOWN_CONSUMER_PATH_GUARANTEED_NEVER_TO_APPEAR_IN_EITHER_REGISTRY" 2>&1)
UNKNOWN_CONSUMER_TASK_EXIT_CODE=$?
set -e
# Iter-118 update: the unknown-path branch now has TWO output shapes —
# (a) "Did you mean?" top-3 ranked suggestions when the query is within
#     ⌊queryLen/3⌋ Levenshtein edits of a registered path
# (b) full-list dump (current case — query has no shared prefix with any
#     registered path, so distance exceeds threshold and we fall back)
# This Case 7 deliberately exercises branch (b) by using the unrelated
# query declared above. Match assertions accordingly.
if [[ "$UNKNOWN_CONSUMER_TASK_EXIT_CODE" -eq 2 ]] && \
   [[ "$UNKNOWN_CONSUMER_TASK_OUTPUT" == *"No registered escape-hatch markers"* ]] && \
   [[ "$UNKNOWN_CONSUMER_TASK_OUTPUT" == *"Hint: query is not close to any registered path"* ]] && \
   [[ "$UNKNOWN_CONSUMER_TASK_OUTPUT" == *"Showing all 19 registered consumer paths"* ]]; then
    assert_passes "Case 7: iter-116 task exits 2 with 'No registered markers' + iter-118 fallback hint (query unrelated to every registered path, top-rank distance exceeds ⌊queryLen/3⌋ threshold so full-list dump is shown)"
else
    assert_fails "Case 7: iter-116 task on unrelated unknown path failed to emit expected fallback hint or wrong exit code (exit=$UNKNOWN_CONSUMER_TASK_EXIT_CODE)"
fi

# ─── Case 8: operator-facing mise task on --help ─────────────────────────
set +e
HELP_OUTPUT=$(bash "$ITER116_OPERATOR_FACING_MISE_TASK_ABSOLUTE_PATH" --help 2>&1)
HELP_EXIT_CODE=$?
set -e
if [[ "$HELP_EXIT_CODE" -eq 1 ]] && \
   [[ "$HELP_OUTPUT" == *"Usage:"* ]] && \
   [[ "$HELP_OUTPUT" == *"Exit codes:"* ]]; then
    assert_passes "Case 8: iter-116 task exits 1 with 'Usage:' and 'Exit codes:' on --help (CLI contract intact)"
else
    assert_fails "Case 8: iter-116 task --help didn't emit usage (exit=$HELP_EXIT_CODE)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-116 regression — Summary"
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
echo "  🚀 Iter-116 reverse-search registry accessor established. Operators can"
echo "     now ask 'what marker opts out of THIS specific hook/audit-task?' with"
echo "     one CLI invocation, without table-scanning the 385-line reference doc."
echo "     The accessor spans both iter-111 RUNTIME-HOOK and iter-114 AUDIT-TASK"
echo "     canonical registries via a discriminated-union return shape that"
echo "     preserves lifecycle-layer provenance for downstream consumers."
echo "  🚀 Iter-117+ candidate (queued):"
echo "     - Audit task verifying every entry's"
echo "       humanReadableEscapeHatchDescriptionForOperatorDocumentation (iter-111)"
echo "       and releaseInvariantSuppressedDescriptionForOperatorDocumentation (iter-114)"
echo "       mentions a hook/task name consistent with the declared consumer-path"
echo "       field — catches stale descriptions after a hook/task rename without"
echo "       a paired registry blurb update"
