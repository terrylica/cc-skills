#!/usr/bin/env bash
#MISE description="Iter-121 regression test for the stale-description audit. Verifies (1) the iter-121 algorithm library exports the three documented extraction functions; (2) the discriminating-hyphen-segment extractor correctly drops marker-suffix stoplist tokens (OK/SKIP/WRAP); (3) the basename extractor correctly drops generic-prefix stoplist tokens (pretooluse/posttooluse/audit/guard/...) and iteration-suffix tokens (iter111/iter114/...); (4) the candidate-substring builder includes adjacent-pair kebab-case joins; (5) the top-level predicate returns the matched candidate for a well-grounded synthetic description AND null for a deliberately-unmoored synthetic description; (6) the iter-121 audit script passes cleanly on the 20-entry baseline (12 iter-111 runtime-hook + 8 iter-114 audit-task); (7) the audit prints AUDIT PASSED with the discriminating-segment-grounded narrative; (8) the audit's exit-code is 0 on the baseline (informational on iter-121 — always exits 0 regardless of findings)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER121_ALGORITHM_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/iter121-stale-description-audit-algorithm-discriminating-hyphen-segment-extraction-from-marker-or-consumer-source-file-basename.ts"
ITER121_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-iter121-canonical-registry-entry-description-references-discriminating-hyphen-segment-from-marker-or-consumer-basename-to-catch-stale-descriptions-after-hook-renames-spanning-iter111-and-iter114-registries.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-121 stale-description audit regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: algorithm library exports the documented extraction functions ──
if grep -qE "^export function extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix" "$ITER121_ALGORITHM_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename" "$ITER121_ALGORITHM_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename" "$ITER121_ALGORITHM_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-121 algorithm library exports all 3 documented extraction functions (marker, basename, top-level predicate)"
else
    assert_fails "Case 1: one or more iter-121 algorithm functions missing from the library"
fi

# ─── Cases 2-5: TypeScript probe exercising the algorithm directly ──────────
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter121-algorithm-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/iter121-algorithm-probe.ts" <<EOF
import {
  extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix,
  extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename,
  buildCandidateSubstringSetWithSegmentsAndAdjacentPairKebabCaseJoins,
  findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename,
} from "$ITER121_ALGORITHM_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH";

let allProbesPassed = true;

// Probe 2: marker extractor drops OK/SKIP/WRAP suffix tokens
const markerSegmentsForFileSizeOk =
  extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix("FILE-SIZE-OK");
const markerSegmentsForCargoTtySkip =
  extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix("CARGO-TTY-SKIP");
const markerSegmentsForCargoTtyWrap =
  extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix("CARGO-TTY-WRAP");
const allMarkerSuffixesDropped =
  !markerSegmentsForFileSizeOk.includes("ok") &&
  !markerSegmentsForCargoTtySkip.includes("skip") &&
  !markerSegmentsForCargoTtyWrap.includes("wrap") &&
  markerSegmentsForFileSizeOk.includes("file") &&
  markerSegmentsForFileSizeOk.includes("size") &&
  markerSegmentsForCargoTtySkip.includes("cargo") &&
  markerSegmentsForCargoTtySkip.includes("tty");
if (allMarkerSuffixesDropped) {
  console.log("PROBE-2-PASS: marker extractor drops OK/SKIP/WRAP suffix tokens, keeps discriminating tokens");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-2-FAIL: FILE-SIZE-OK -> \${JSON.stringify(markerSegmentsForFileSizeOk)}, CARGO-TTY-SKIP -> \${JSON.stringify(markerSegmentsForCargoTtySkip)}, CARGO-TTY-WRAP -> \${JSON.stringify(markerSegmentsForCargoTtyWrap)}\`);
}

// Probe 3: basename extractor drops generic-prefix and iter-suffix tokens
const basenameSegmentsForFileSizeGuardPath =
  extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename(
    "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts",
  );
const basenameSegmentsForIter78LayerGuardPath =
  extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename(
    "plugins/itp-hooks/hooks/pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts",
  );
const stoplistsCorrectlyDropGenericAndIterSuffix =
  !basenameSegmentsForFileSizeGuardPath.includes("pretooluse") &&
  !basenameSegmentsForFileSizeGuardPath.includes("guard") &&
  !basenameSegmentsForFileSizeGuardPath.includes("ts") &&
  basenameSegmentsForFileSizeGuardPath.includes("file") &&
  basenameSegmentsForFileSizeGuardPath.includes("size") &&
  !basenameSegmentsForIter78LayerGuardPath.includes("iter78") &&
  basenameSegmentsForIter78LayerGuardPath.includes("layer3") &&
  basenameSegmentsForIter78LayerGuardPath.includes("stripped") &&
  basenameSegmentsForIter78LayerGuardPath.includes("path");
if (stoplistsCorrectlyDropGenericAndIterSuffix) {
  console.log("PROBE-3-PASS: basename extractor drops generic-prefix (pretooluse/guard/ts) AND iter-NNN suffix tokens");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-3-FAIL: file-size-guard.ts -> \${JSON.stringify(basenameSegmentsForFileSizeGuardPath)}, iter78-layer3-guard.ts -> \${JSON.stringify(basenameSegmentsForIter78LayerGuardPath)}\`);
}

// Probe 4: candidate-substring builder includes adjacent-pair kebab-case joins
const candidatesForFileSize =
  buildCandidateSubstringSetWithSegmentsAndAdjacentPairKebabCaseJoins(["file", "size"]);
const candidatesForThreeSegments =
  buildCandidateSubstringSetWithSegmentsAndAdjacentPairKebabCaseJoins(["bash", "launchd", "ok"]);
const adjacentPairsBuiltCorrectly =
  candidatesForFileSize.includes("file") &&
  candidatesForFileSize.includes("size") &&
  candidatesForFileSize.includes("file-size") &&
  candidatesForThreeSegments.includes("bash-launchd") &&
  candidatesForThreeSegments.includes("launchd-ok") &&
  // Non-adjacent pair NOT in set (no transitive C(n,2) joins)
  !candidatesForThreeSegments.includes("bash-ok");
if (adjacentPairsBuiltCorrectly) {
  console.log("PROBE-4-PASS: candidate-substring builder includes raw segments + adjacent-pair kebab-case joins, excludes non-adjacent pairs");
} else {
  allProbesPassed = false;
  console.log(\`PROBE-4-FAIL: file-size pair -> \${JSON.stringify(candidatesForFileSize)}, three-segment -> \${JSON.stringify(candidatesForThreeSegments)}\`);
}

// Probe 5: top-level predicate — passes well-grounded synthetic, fails unmoored synthetic
const wellGroundedDescriptionMatchResult =
  findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename(
    "FILE-SIZE-OK",
    "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts",
    "Allow a file to exceed file-size-guard's per-extension warn/block thresholds.",
  );
const deliberatelyUnmooredDescriptionMatchResult =
  findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename(
    "FILE-SIZE-OK",
    "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts",
    "Suppresses the orchestrator timeout deadline applied to bash subprocess invocations during release preflight.",
  );
const predicateBehavesCorrectly =
  wellGroundedDescriptionMatchResult !== null &&
  deliberatelyUnmooredDescriptionMatchResult === null;
if (predicateBehavesCorrectly) {
  console.log(\`PROBE-5-PASS: top-level predicate returns matched candidate "\${wellGroundedDescriptionMatchResult}" for grounded synthetic AND null for unmoored synthetic\`);
} else {
  allProbesPassed = false;
  console.log(\`PROBE-5-FAIL: grounded -> \${wellGroundedDescriptionMatchResult}, unmoored -> \${deliberatelyUnmooredDescriptionMatchResult}\`);
}

if (!allProbesPassed) process.exit(1);
EOF

set +e
PROBE_OUTPUT=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/iter121-algorithm-probe.ts" 2>&1)
PROBE_EXIT_CODE=$?
set -e

if [[ "$PROBE_OUTPUT" == *"PROBE-2-PASS"* ]]; then
    assert_passes "Case 2: marker extractor drops OK/SKIP/WRAP suffix-token stoplist; keeps file/size/cargo/tty discriminators"
else
    assert_fails "Case 2: marker extractor algorithm broken (output=$PROBE_OUTPUT)"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-3-PASS"* ]]; then
    assert_passes "Case 3: basename extractor drops generic-prefix (pretooluse/guard/ts) AND iter-NNN suffix tokens (iter78); keeps layer3/stripped/path discriminators"
else
    assert_fails "Case 3: basename extractor algorithm broken (probe exit=$PROBE_EXIT_CODE)"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-4-PASS"* ]]; then
    assert_passes "Case 4: candidate-substring builder includes raw segments + adjacent-pair kebab-case joins (file-size, bash-launchd); intentionally excludes non-adjacent pairs (bash-ok)"
else
    assert_fails "Case 4: candidate-substring adjacent-pair builder broken"
fi

if [[ "$PROBE_OUTPUT" == *"PROBE-5-PASS"* ]]; then
    assert_passes "Case 5: top-level predicate returns matched candidate for well-grounded synthetic description AND returns null for deliberately-unmoored synthetic description (the audit's signal-to-noise hinge)"
else
    assert_fails "Case 5: top-level predicate fails to discriminate grounded from unmoored synthetic descriptions"
fi

# ─── Case 6: audit script passes cleanly on the canonical baseline ──────────
# The expected entry count is DERIVED from the registries (the official
# source) rather than hard-coded: the previous pinned "20 entries" broke the
# moment a 21st legitimate marker was registered (2026-06-11,
# INVENTED-FALLBACK-OK) even though the audit itself passed — a hard-coded
# parameter value masquerading as a regression signal. Same counting shape
# the registries themselves use: one quoted markerNameTokenIncludingSuffix
# field per entry.
ITER121_EXPECTED_REGISTRY_ENTRY_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES=$(
    grep -chE '^\s*markerNameTokenIncludingSuffix: "' \
        "$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts" \
        "$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts" \
        | awk '{ s += $1 } END { print s }'
)
set +e
AUDIT_OUTPUT=$(bash "$ITER121_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
AUDIT_EXIT_CODE=$?
set -e

if [[ "$AUDIT_EXIT_CODE" -eq 0 ]] && \
   [[ "$AUDIT_OUTPUT" == *"AUDIT PASSED"* ]] && \
   [[ "$AUDIT_OUTPUT" == *"audited ${ITER121_EXPECTED_REGISTRY_ENTRY_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES} entries"* ]]; then
    assert_passes "Case 6: audit script passes on the ${ITER121_EXPECTED_REGISTRY_ENTRY_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES}-entry canonical baseline (count derived from the iter-111 + iter-114 registries) with 0 stale-description hits"
else
    assert_fails "Case 6: audit script did NOT pass clean baseline (exit=$AUDIT_EXIT_CODE, expected entries=${ITER121_EXPECTED_REGISTRY_ENTRY_COUNT_DERIVED_FROM_BOTH_CANONICAL_REGISTRIES})"
fi

# ─── Case 7: audit prints the discriminating-segment-grounded narrative ─────
if [[ "$AUDIT_OUTPUT" == *"description is grounded in its marker or consumer-path identity"* ]] && \
   [[ "$AUDIT_OUTPUT" == *"discriminating segment"* ]]; then
    assert_passes "Case 7: audit narrative correctly explains the discriminating-segment-grounded passing criterion"
else
    assert_fails "Case 7: audit narrative missing discriminating-segment-grounded explanation"
fi

# ─── Case 8: audit exit-code is 0 on baseline (informational on iter-121) ───
# Iter-121 is informational and always exits 0 regardless of findings.
# Iter-122+ will remove the unconditional `exit 0` to promote the audit
# to STRICT-BLOCK; this test will need updating at that time.
if [[ "$AUDIT_EXIT_CODE" -eq 0 ]]; then
    assert_passes "Case 8: audit exits 0 on baseline (iter-121 informational mode — never blocks release; iter-122+ will promote to STRICT-BLOCK)"
else
    assert_fails "Case 8: audit unexpectedly exited non-zero on clean baseline (exit=$AUDIT_EXIT_CODE)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-121 regression — Summary"
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
echo "  🚀 Iter-121 stale-description audit established. Catches the bug class"
echo "     where a hook/audit-task is renamed and the canonical registry's"
echo "     consumer-path field updated, but the human-readable description"
echo "     still references the OLD name. Algorithm: extract discriminating"
echo "     hyphen-segments from marker name AND consumer basename, drop"
echo "     stoplist (OK/SKIP/WRAP suffix tokens; pretooluse/posttooluse/audit"
echo "     /guard/marketplace generic prefixes; iter-NNN suffix tokens),"
echo "     verify description contains ≥1 candidate as case-insensitive"
echo "     substring (raw segment OR adjacent-pair kebab-case join)."
echo "  🚀 Iter-122+ queue:"
echo "     - Promote iter-121 audit from informational to STRICT-BLOCK by"
echo "       removing the unconditional 'exit 0' tail (after the baseline"
echo "       coverage is verified across a few release cycles)."
echo "     - Extend the audit to ALSO verify the marker name itself is"
echo "       mentioned somewhere in the description (currently only the"
echo "       discriminating-segment slice is checked; literal marker token"
echo "       mention would catch a different class of drift)."
