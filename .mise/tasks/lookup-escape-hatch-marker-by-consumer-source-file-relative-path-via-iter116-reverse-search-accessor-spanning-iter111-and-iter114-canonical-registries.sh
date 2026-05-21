#!/usr/bin/env bash
#MISE description="Iter-116 operator-facing reverse-search: 'I want to opt out of THIS hook/audit-task — what marker do I write?' Takes a consumer source file relative path argument (e.g., plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts OR .mise/tasks/audit-...-iter106.sh) and reports every registered escape-hatch marker token that opts the caller out of that consumer's enforcement, spanning both the iter-111 RUNTIME-HOOK canonical registry and the iter-114 AUDIT-TASK canonical registry. Exits 0 when ≥1 marker found, exits 2 when no markers target the path, exits 1 on usage error."

# ────────────────────────────────────────────────────────────────────────
# Iter-116 design rationale (operator-facing CLI side)
# ────────────────────────────────────────────────────────────────────────
#
# Pre-iter-116 operator workflow:
#
#   $ # I want to suppress file-size-guard for one file. What marker?
#   $ # Choice 1: Open docs/marketplace-escape-hatch-marker-reference.md
#   $ #           and table-scan 20 sections looking for "file-size-guard".
#   $ # Choice 2: grep the iter-111 registry for the hook path string.
#   $ # Choice 3: read the hook source to find the marker token passed
#   $ #           to the iter-107 helper.
#
# Post-iter-116 operator workflow:
#
#   $ mise run lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts
#   ✓ Found 1 escape-hatch marker for consumer:
#       plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts
#
#     Marker:                 FILE-SIZE-OK
#     Lifecycle layer:        RUNTIME-HOOK (iter-111; consumed at every …)
#     …
#
# Exit-code policy (designed for CI / scripted operator use):
#
#   0 : ≥1 marker found and printed
#   1 : usage error (missing arg, --help)
#   2 : path is well-formed but no markers target it. Operator sees a
#       compact "available consumers" hint listing every distinct
#       consumer path the registry knows about (sourced from the
#       iter-116 accessor's listAllDistinctConsumerSourceFileRelativePaths…
#       helper) so they can grep/fuzzy-match to find the closest match.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts"

print_usage_and_exit_one() {
    echo "Usage: mise run $(basename "$0" .sh) [--json] <consumer-source-file-relative-path>"
    echo ""
    echo "  Reverse-search the iter-111 + iter-114 canonical escape-hatch-marker"
    echo "  registries by consumer source file relative path. Returns every"
    echo "  marker token that opts the caller out of that consumer's enforcement."
    echo ""
    echo "Arguments:"
    echo "  consumer-source-file-relative-path"
    echo "      Repo-root-relative path to a hook source file (under"
    echo "      plugins/itp-hooks/hooks/) OR an audit task source file (under"
    echo "      .mise/tasks/). Must match the registry-declared path exactly."
    echo ""
    echo "Flags:"
    echo "  --json   Iter-119: emit structured JSON to stdout for jq pipelines"
    echo "           and automation. JSON shape:"
    echo "             {status: 'found',    consumerPath, markers: [...]}"
    echo "             {status: 'not-found', consumerPath, didYouMean: [...] | null}"
    echo "           didYouMean is non-null when iter-118 Levenshtein top-3"
    echo "           ranking has a candidate within ⌊queryLen/3⌋ edit distance"
    echo "           of the operator query (plausible typo), null otherwise"
    echo "           (operator query is unrelated to every registered path)."
    echo ""
    echo "Examples:"
    echo "  mise run lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries \\"
    echo "      plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
    echo ""
    echo "  mise run lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries \\"
    echo "      --json plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts | jq '.markers[0].markerNameTokenIncludingSuffix'"
    echo ""
    echo "Exit codes:"
    echo "  0 : ≥1 marker found and printed"
    echo "  1 : usage error (missing arg, --help)"
    echo "  2 : path is well-formed but no markers target it"
    exit 1
}

# Iter-119: parse optional --json flag (must appear BEFORE the positional
# consumer-path argument so a path that happens to literally start with
# `--json` won't be mistakenly consumed as a flag). Keep the parser simple
# rather than pulling in getopts/getopt — only one flag is supported.
ITER119_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR=false
if [[ "$#" -ge 1 ]] && [[ "$1" == "--json" ]]; then
    ITER119_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR=true
    shift
fi

if [[ "$#" -ne 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    print_usage_and_exit_one
fi

OPERATOR_SUPPLIED_CONSUMER_SOURCE_FILE_RELATIVE_PATH="$1"

# ════════════════════════════════════════════════════════════════════════
# Renderer: small TypeScript program executed via bun. Inline (heredoc)
# rather than a separate file to keep the operator CLI self-contained.
# ════════════════════════════════════════════════════════════════════════

RENDERER_TEMP_SCRIPT_DIRECTORY=$(mktemp -d -t iter116-reverse-search-XXXXXX)
trap 'rm -rf "$RENDERER_TEMP_SCRIPT_DIRECTORY"' EXIT

cat > "$RENDERER_TEMP_SCRIPT_DIRECTORY/reverse-search-from-cli.ts" <<EOF
import {
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries,
  listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically,
  renderSingleReverseSearchHitAsHumanReadableTerminalBlock,
  rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches,
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold,
} from "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH";

const operatorSuppliedConsumerSourceFileRelativePath = "$OPERATOR_SUPPLIED_CONSUMER_SOURCE_FILE_RELATIVE_PATH";

// Iter-119: shell wires the --json flag into a TypeScript boolean here so
// the renderer can branch on output mode without re-parsing argv inside
// the heredoc. When true, all output goes to stdout as a single JSON
// document (suitable for piping to jq). When false, the iter-116 human-
// readable terminal output is preserved verbatim.
const ITER119_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR: boolean = ${ITER119_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR};

const reverseSearchHits =
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
    operatorSuppliedConsumerSourceFileRelativePath,
  );

if (reverseSearchHits.length === 0) {
  // Iter-118: rank registered paths by Levenshtein edit distance from the
  // operator-supplied query and surface the top-3 closest matches as a
  // "Did you mean?" hint when at least one is within the ⌊queryLen / 3⌋
  // edit-distance threshold (operator likely typo'd a real path). When
  // the top candidate is further than the threshold the query is treated
  // as unrelated to any registered path and we fall back to the iter-116
  // full-list display (less misleading than surfacing three random-
  // looking suggestions).
  const ITER118_TOP_K_CLOSEST_MATCHES_TO_SHOW_AS_DID_YOU_MEAN_SUGGESTIONS = 3;
  const topRankedCandidates =
    rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches(
      operatorSuppliedConsumerSourceFileRelativePath,
      ITER118_TOP_K_CLOSEST_MATCHES_TO_SHOW_AS_DID_YOU_MEAN_SUGGESTIONS,
    );
  const topCandidateIsCloseEnoughToBeAPlausibleOperatorTypo =
    topRankedCandidates.length > 0 &&
    isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold(
      topRankedCandidates[0].levenshteinEditDistanceFromOperatorSuppliedQuery,
      operatorSuppliedConsumerSourceFileRelativePath.length,
    );

  if (ITER119_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR) {
    // Iter-119 JSON-not-found branch. didYouMean is non-null ONLY when
    // the iter-118 Levenshtein top-1 candidate is within ⌊queryLen/3⌋
    // edit distance — this encodes the "plausible typo" vs "unrelated
    // query" decision in the JSON shape itself so downstream consumers
    // can branch without re-running the threshold check.
    const machineReadableNotFoundJsonDocument = {
      status: "not-found",
      consumerSourceFileRelativePath:
        operatorSuppliedConsumerSourceFileRelativePath,
      didYouMean: topCandidateIsCloseEnoughToBeAPlausibleOperatorTypo
        ? topRankedCandidates.map((rankedCandidate) => ({
            consumerSourceFileRelativePath:
              rankedCandidate.consumerSourceFileRelativePath,
            levenshteinEditDistanceFromOperatorSuppliedQuery:
              rankedCandidate.levenshteinEditDistanceFromOperatorSuppliedQuery,
          }))
        : null,
      allRegisteredConsumerSourceFilePaths:
        topCandidateIsCloseEnoughToBeAPlausibleOperatorTypo
          ? null
          : listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically(),
    };
    console.log(JSON.stringify(machineReadableNotFoundJsonDocument, null, 2));
    process.exit(2);
  }

  console.error(
    \`✗ No registered escape-hatch markers target this consumer path:\\n    \${operatorSuppliedConsumerSourceFileRelativePath}\\n\`,
  );

  if (topCandidateIsCloseEnoughToBeAPlausibleOperatorTypo) {
    console.error(
      \`  Did you mean (top-\${topRankedCandidates.length} closest match\${topRankedCandidates.length === 1 ? "" : "es"} by Levenshtein edit distance)?\\n\`,
    );
    for (const rankedCandidate of topRankedCandidates) {
      console.error(
        \`    [\${rankedCandidate.levenshteinEditDistanceFromOperatorSuppliedQuery} edit\${rankedCandidate.levenshteinEditDistanceFromOperatorSuppliedQuery === 1 ? "" : "s"}] \${rankedCandidate.consumerSourceFileRelativePath}\`,
      );
    }
    console.error(
      \`\\n  If none of these match, the consumer may not yet be registered. Add an entry to:\\n    - Runtime hooks: plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts\\n    - Audit tasks:  plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts\`,
    );
  } else {
    const distinctRegisteredConsumerPaths =
      listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically();
    console.error(
      \`  Hint: query is not close to any registered path (top match has \${topRankedCandidates[0]?.levenshteinEditDistanceFromOperatorSuppliedQuery ?? "n/a"} edit distance, threshold ⌊queryLen / 3⌋). Showing all \${distinctRegisteredConsumerPaths.length} registered consumer paths:\\n\`,
    );
    for (const distinctRegisteredConsumerPath of distinctRegisteredConsumerPaths) {
      console.error(\`    - \${distinctRegisteredConsumerPath}\`);
    }
    console.error(
      \`\\n  If your consumer is genuinely registered but the path differs significantly, check the\\n  spelling against the list above. If the consumer is NOT yet registered, add an entry to\\n  the appropriate canonical registry (see paths above).\`,
    );
  }
  process.exit(2);
}

if (ITER119_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR) {
  // Iter-119 JSON-found branch. Each hit is normalized into a flat shape
  // that preserves the iter-116 discriminated-union lifecycle-layer tag
  // alongside the full registry entry. Downstream consumers can branch
  // on the lifecycleLayer field (string-valued: "runtime-hook" or
  // "audit-task") without unpacking the discriminated-union TypeScript
  // shape.
  const machineReadableFoundJsonDocument = {
    status: "found",
    consumerSourceFileRelativePath:
      operatorSuppliedConsumerSourceFileRelativePath,
    markers: reverseSearchHits.map((reverseSearchHit) => ({
      lifecycleLayer:
        reverseSearchHit.originatingRegistryLifecycleLayerTag ===
        "RUNTIME_HOOK_ITER111"
          ? "runtime-hook"
          : "audit-task",
      registryProvenanceTag:
        reverseSearchHit.originatingRegistryLifecycleLayerTag,
      ...reverseSearchHit.matchedRegistryEntry,
    })),
  };
  console.log(JSON.stringify(machineReadableFoundJsonDocument, null, 2));
  process.exit(0);
}

console.log(
  \`✓ Found \${reverseSearchHits.length} escape-hatch marker\${reverseSearchHits.length === 1 ? "" : "s"} for consumer:\\n    \${operatorSuppliedConsumerSourceFileRelativePath}\\n\`,
);

for (let reverseSearchHitIndex = 0; reverseSearchHitIndex < reverseSearchHits.length; reverseSearchHitIndex++) {
  const reverseSearchHit = reverseSearchHits[reverseSearchHitIndex];
  console.log(renderSingleReverseSearchHitAsHumanReadableTerminalBlock(reverseSearchHit));
  if (reverseSearchHitIndex < reverseSearchHits.length - 1) {
    console.log("");
  }
}

process.exit(0);
EOF

set +e
(cd "$REPO_ROOT" && bun "$RENDERER_TEMP_SCRIPT_DIRECTORY/reverse-search-from-cli.ts")
RENDERER_EXIT_CODE=$?
set -e

exit "$RENDERER_EXIT_CODE"
