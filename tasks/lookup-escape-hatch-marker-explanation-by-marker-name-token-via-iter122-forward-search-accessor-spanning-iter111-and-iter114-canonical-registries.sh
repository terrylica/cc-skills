#!/usr/bin/env bash
#MISE description="Iter-122 operator-facing forward-search CLI complementary to iter-116. Operator workflow: 'I'm reading source code and saw the marker token FILE-SIZE-OK or PROCESS-STORM-OK. What does this marker do, and which consumer hook or audit-task recognizes it?' Takes a marker name token (case-sensitive UPPER-KEBAB-CASE preferred, case-insensitive fallback exists) and reports the canonical registry entry plus operator-readable description, reason policy, example comment form. Five-step fallback chain: (1) exact case-sensitive marker-token match against iter-111+iter-114 registries; (2) exact case-insensitive match catching operators who typed lowercase; (3) case-insensitive substring search in marker tokens catching partial recall like TTY matches CARGO-TTY-SKIP+CARGO-TTY-WRAP; (4) iter-118-parallel Levenshtein Did-You-Mean catching typos like FIEL-SIZE-OK; (5) full-list dump. Iter-119-parallel --json mode emits status+matchType+matchingMarkers for jq pipelines. Exits 0 when ≥1 marker matched at any layer, exits 2 when unknown after exhausting fallbacks, exits 1 on usage error."

# ────────────────────────────────────────────────────────────────────────
# Iter-122 design rationale (operator-facing CLI side)
# ────────────────────────────────────────────────────────────────────────
#
# Pre-iter-122 operator workflow for the FORWARD direction:
#
#   $ # I see `# CARGO-TTY-SKIP` in a Cargo.toml. What does it do?
#   $ # Choice 1: open docs/marketplace-escape-hatch-marker-reference.md
#   $ #           and table-scan 20 sections looking for CARGO-TTY-SKIP.
#   $ # Choice 2: grep the iter-111 + iter-114 registries by marker name.
#   $ # Choice 3: read the consumer hook source to learn what it does.
#
# All three are slower than they should be. Iter-122 ships a CLI that
# resolves marker → consumer + explanation in one command, symmetric to
# the iter-116 CLI that resolved consumer → markers.
#
# Five-step fallback chain (parallel to iter-116's four-step chain):
#
#   1. Exact case-sensitive match      — fast path, ~99% of intentional queries
#   2. Exact case-insensitive match    — operators who typed lowercase by habit
#   3. Marker-substring (case-insensitive) — partial-recall queries like "TTY"
#   4. Levenshtein "Did you mean?"     — typo correction via iter-118 helper
#   5. Full-list dump                  — when everything fails
#
# Step 2 is the only addition specific to iter-122 beyond the iter-116
# chain shape — because marker-name canonical casing is UPPER-KEBAB-CASE
# (an enforceable, predictable shape), the case-insensitive exact match
# is a high-value catch BEFORE falling through to substring search. The
# iter-116 reverse-search omits this step because file paths have no
# canonical-case convention.
#
# Exit-code policy (designed for CI / scripted operator use):
#
#   0 : ≥1 marker matched at any fallback layer and printed
#   1 : usage error (missing arg, --help)
#   2 : query is well-formed but matches no marker after exhausting all
#       fallback layers (truly-unrelated token)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

ITER122_SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER122_REPO_ROOT="$(cd "$ITER122_SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER122_FORWARD_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$ITER122_REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-forward-search-accessor-by-marker-name-token-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter122.ts"

print_usage_and_exit_one() {
    echo "Usage: mise run $(basename "$0" .sh) [--json] <marker-name-token>"
    echo ""
    echo "  Forward-search the iter-111 + iter-114 canonical escape-hatch-marker"
    echo "  registries by marker name token. Reports the consumer hook or audit"
    echo "  task that recognizes the marker, plus the operator-readable"
    echo "  description, reason policy, and example comment form."
    echo ""
    echo "Arguments:"
    echo "  marker-name-token"
    echo "      Exact marker token (UPPER-KEBAB-CASE preferred, e.g., FILE-SIZE-OK,"
    echo "      BASH-LAUNCHD-OK, CARGO-TTY-SKIP). The CLI falls back through:"
    echo "      case-insensitive exact match → substring search → Levenshtein"
    echo "      Did-You-Mean → full-list dump, so partial recall + typos work too."
    echo ""
    echo "Flags:"
    echo "  --json   Iter-122 machine-readable mode: emit single JSON document"
    echo "           to stdout. JSON shape:"
    echo "             {status: 'found', matchType: 'exact' |"
    echo "                                          'exact-case-insensitive' |"
    echo "                                          'marker-substring' |"
    echo "                                          'levenshtein-suggestion',"
    echo "              operatorSuppliedQuery, matchingMarkers: [...]}"
    echo "             {status: 'not-found', operatorSuppliedQuery,"
    echo "              didYouMean: [...] | null,"
    echo "              allRegisteredMarkerNameTokens: [...] | null}"
    echo ""
    echo "Examples:"
    echo "  mise run lookup-escape-hatch-marker-explanation-by-marker-name-token-via-iter122-forward-search-accessor-spanning-iter111-and-iter114-canonical-registries \\"
    echo "      FILE-SIZE-OK"
    echo ""
    echo "  # Case-insensitive fallback:"
    echo "  mise run lookup-...iter122... file-size-ok"
    echo ""
    echo "  # Substring search — finds CARGO-TTY-SKIP + CARGO-TTY-WRAP:"
    echo "  mise run lookup-...iter122... TTY"
    echo ""
    echo "  # JSON output piped to jq:"
    echo "  mise run lookup-...iter122... --json FILE-SIZE-OK | jq '.matchingMarkers[0].consumerHookSourceFileRelativePath'"
    echo ""
    echo "Exit codes:"
    echo "  0 : ≥1 marker matched at any fallback layer and printed"
    echo "  1 : usage error (missing arg, --help)"
    echo "  2 : query is well-formed but matches no marker after exhausting fallbacks"
    exit 1
}

# Parse optional --json flag (must appear BEFORE the positional marker
# argument so a marker token that happens to literally start with `--json`
# won't be mistakenly consumed as a flag).
ITER122_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR=false
if [[ "$#" -ge 1 ]] && [[ "$1" == "--json" ]]; then
    ITER122_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR=true
    shift
fi

if [[ "$#" -ne 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    print_usage_and_exit_one
fi

ITER122_OPERATOR_SUPPLIED_MARKER_NAME_TOKEN_QUERY="$1"

# ════════════════════════════════════════════════════════════════════════
# Renderer: small TypeScript program executed via bun. Inline (heredoc)
# rather than a separate file to keep the operator CLI self-contained.
# ════════════════════════════════════════════════════════════════════════

ITER122_RENDERER_TEMP_SCRIPT_DIRECTORY=$(mktemp -d -t iter122-forward-search-XXXXXX)
trap 'rm -rf "$ITER122_RENDERER_TEMP_SCRIPT_DIRECTORY"' EXIT

cat > "$ITER122_RENDERER_TEMP_SCRIPT_DIRECTORY/forward-search-from-cli.ts" <<EOF
import {
  lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries,
  lookupAllCanonicalRegistryEntriesByMarkerNameTokenCaseInsensitivelySpanningBothRegistries,
  findAllRegisteredMarkerNameTokensWhoseTokenContainsQueryStringCaseInsensitively,
  rankAllRegisteredMarkerNameTokensByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches,
  listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically,
  renderSingleForwardSearchHitAsHumanReadableTerminalBlock,
  type EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag,
} from "$ITER122_FORWARD_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH";
import {
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold,
} from "$ITER122_REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts";

const operatorSuppliedMarkerNameTokenQuery = "$ITER122_OPERATOR_SUPPLIED_MARKER_NAME_TOKEN_QUERY";
const ITER122_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR: boolean = ${ITER122_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR};

function flattenForwardSearchHitsToMachineReadableMarkersArray(
  forwardSearchHits: ReadonlyArray<EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag>,
) {
  return forwardSearchHits.map((forwardSearchHit) => ({
    lifecycleLayer:
      forwardSearchHit.originatingRegistryLifecycleLayerTag ===
      "RUNTIME_HOOK_ITER111"
        ? "runtime-hook"
        : "audit-task",
    registryProvenanceTag:
      forwardSearchHit.originatingRegistryLifecycleLayerTag,
    ...forwardSearchHit.matchedRegistryEntry,
  }));
}

// ─── Step 1: exact case-sensitive match ─────────────────────────────────
const exactCaseSensitiveHits =
  lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries(
    operatorSuppliedMarkerNameTokenQuery,
  );

if (exactCaseSensitiveHits.length > 0) {
  if (ITER122_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR) {
    console.log(
      JSON.stringify(
        {
          status: "found",
          matchType: "exact",
          operatorSuppliedQuery: operatorSuppliedMarkerNameTokenQuery,
          matchingMarkers: flattenForwardSearchHitsToMachineReadableMarkersArray(
            exactCaseSensitiveHits,
          ),
        },
        null,
        2,
      ),
    );
    process.exit(0);
  }
  console.log(
    \`✓ Found \${exactCaseSensitiveHits.length} canonical registry entry/entries for marker:\\n    \${operatorSuppliedMarkerNameTokenQuery}\\n\`,
  );
  for (
    let hitIndex = 0;
    hitIndex < exactCaseSensitiveHits.length;
    hitIndex += 1
  ) {
    console.log(
      renderSingleForwardSearchHitAsHumanReadableTerminalBlock(
        exactCaseSensitiveHits[hitIndex],
      ),
    );
    if (hitIndex < exactCaseSensitiveHits.length - 1) console.log("");
  }
  process.exit(0);
}

// ─── Step 2: exact case-insensitive match ───────────────────────────────
const exactCaseInsensitiveHits =
  lookupAllCanonicalRegistryEntriesByMarkerNameTokenCaseInsensitivelySpanningBothRegistries(
    operatorSuppliedMarkerNameTokenQuery,
  );

if (exactCaseInsensitiveHits.length > 0) {
  if (ITER122_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR) {
    console.log(
      JSON.stringify(
        {
          status: "found",
          matchType: "exact-case-insensitive",
          operatorSuppliedQuery: operatorSuppliedMarkerNameTokenQuery,
          matchingMarkers: flattenForwardSearchHitsToMachineReadableMarkersArray(
            exactCaseInsensitiveHits,
          ),
        },
        null,
        2,
      ),
    );
    process.exit(0);
  }
  const canonicalMarkerName =
    exactCaseInsensitiveHits[0].matchedRegistryEntry
      .markerNameTokenIncludingSuffix;
  console.log(
    \`✓ Marker "\${operatorSuppliedMarkerNameTokenQuery}" matches canonical "\${canonicalMarkerName}" (case-insensitive):\\n\`,
  );
  for (
    let hitIndex = 0;
    hitIndex < exactCaseInsensitiveHits.length;
    hitIndex += 1
  ) {
    console.log(
      renderSingleForwardSearchHitAsHumanReadableTerminalBlock(
        exactCaseInsensitiveHits[hitIndex],
      ),
    );
    if (hitIndex < exactCaseInsensitiveHits.length - 1) console.log("");
  }
  process.exit(0);
}

// ─── Step 3: case-insensitive substring search in marker tokens ─────────
const markerSubstringMatches =
  findAllRegisteredMarkerNameTokensWhoseTokenContainsQueryStringCaseInsensitively(
    operatorSuppliedMarkerNameTokenQuery,
  );

if (markerSubstringMatches.length > 0) {
  // Resolve each matching marker to its registry entries.
  const allHitsFoundViaMarkerSubstring = markerSubstringMatches.flatMap(
    (matchingMarkerToken) =>
      lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries(
        matchingMarkerToken,
      ),
  );
  if (ITER122_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR) {
    console.log(
      JSON.stringify(
        {
          status: "found",
          matchType: "marker-substring",
          operatorSuppliedQuery: operatorSuppliedMarkerNameTokenQuery,
          matchingMarkerNameTokens: markerSubstringMatches,
          matchingMarkers: flattenForwardSearchHitsToMachineReadableMarkersArray(
            allHitsFoundViaMarkerSubstring,
          ),
        },
        null,
        2,
      ),
    );
    process.exit(0);
  }
  console.log(
    \`✓ No exact match for "\${operatorSuppliedMarkerNameTokenQuery}", but found \${markerSubstringMatches.length} marker\${markerSubstringMatches.length === 1 ? "" : "s"} whose token contains your query (case-insensitive):\\n\`,
  );
  for (const matchingMarkerToken of markerSubstringMatches) {
    console.log(\`  \${matchingMarkerToken}\`);
  }
  console.log("");
  for (
    let hitIndex = 0;
    hitIndex < allHitsFoundViaMarkerSubstring.length;
    hitIndex += 1
  ) {
    console.log(
      renderSingleForwardSearchHitAsHumanReadableTerminalBlock(
        allHitsFoundViaMarkerSubstring[hitIndex],
      ),
    );
    if (hitIndex < allHitsFoundViaMarkerSubstring.length - 1) console.log("");
  }
  process.exit(0);
}

// ─── Step 4: Levenshtein "Did you mean?" ────────────────────────────────
const ITER122_TOP_K_LEVENSHTEIN_DID_YOU_MEAN_SUGGESTIONS = 3;
const topRankedLevenshteinCandidates =
  rankAllRegisteredMarkerNameTokensByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches(
    operatorSuppliedMarkerNameTokenQuery,
    ITER122_TOP_K_LEVENSHTEIN_DID_YOU_MEAN_SUGGESTIONS,
  );
const topRankedLevenshteinCandidateIsCloseEnoughToBeOperatorTypo =
  topRankedLevenshteinCandidates.length > 0 &&
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold(
    topRankedLevenshteinCandidates[0].levenshteinEditDistanceFromOperatorSuppliedQuery,
    operatorSuppliedMarkerNameTokenQuery.length,
  );

if (ITER122_JSON_OUTPUT_MODE_REQUESTED_BY_OPERATOR) {
  const machineReadableNotFoundJsonDocument = {
    status: "not-found",
    operatorSuppliedQuery: operatorSuppliedMarkerNameTokenQuery,
    didYouMean: topRankedLevenshteinCandidateIsCloseEnoughToBeOperatorTypo
      ? topRankedLevenshteinCandidates.map((rankedCandidate) => ({
          markerNameTokenIncludingSuffix:
            rankedCandidate.markerNameTokenIncludingSuffix,
          levenshteinEditDistanceFromOperatorSuppliedQuery:
            rankedCandidate.levenshteinEditDistanceFromOperatorSuppliedQuery,
        }))
      : null,
    allRegisteredMarkerNameTokens:
      topRankedLevenshteinCandidateIsCloseEnoughToBeOperatorTypo
        ? null
        : listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically(),
  };
  console.log(JSON.stringify(machineReadableNotFoundJsonDocument, null, 2));
  process.exit(2);
}

console.error(
  \`✗ No canonical registry entry matches the marker token:\\n    \${operatorSuppliedMarkerNameTokenQuery}\\n\`,
);

if (topRankedLevenshteinCandidateIsCloseEnoughToBeOperatorTypo) {
  console.error(
    \`  Did you mean (top-\${topRankedLevenshteinCandidates.length} closest match\${topRankedLevenshteinCandidates.length === 1 ? "" : "es"} by Levenshtein edit distance)?\\n\`,
  );
  for (const rankedCandidate of topRankedLevenshteinCandidates) {
    console.error(
      \`    [\${rankedCandidate.levenshteinEditDistanceFromOperatorSuppliedQuery} edit\${rankedCandidate.levenshteinEditDistanceFromOperatorSuppliedQuery === 1 ? "" : "s"}] \${rankedCandidate.markerNameTokenIncludingSuffix}\`,
    );
  }
  console.error(
    \`\\n  If none of these match, the marker may not yet be registered. Add an entry to:\\n    - Runtime hooks: plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts\\n    - Audit tasks:  plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts\`,
  );
} else {
  // ─── Step 5: full-list dump ─────────────────────────────────────────
  const allRegisteredMarkerTokens =
    listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically();
  console.error(
    \`  Hint: query is not close to any registered marker (top match has \${topRankedLevenshteinCandidates[0]?.levenshteinEditDistanceFromOperatorSuppliedQuery ?? "n/a"} edit distance, threshold ⌊queryLen / 3⌋). Showing all \${allRegisteredMarkerTokens.length} registered marker tokens:\\n\`,
  );
  for (const registeredMarkerToken of allRegisteredMarkerTokens) {
    console.error(\`    - \${registeredMarkerToken}\`);
  }
  console.error(
    \`\\n  If the marker is genuinely registered but the token differs significantly, check the\\n  spelling against the list above. If the marker is NOT yet registered, add an entry to\\n  the appropriate canonical registry (see paths above).\`,
  );
}
process.exit(2);
EOF

set +e
(cd "$ITER122_REPO_ROOT" && bun "$ITER122_RENDERER_TEMP_SCRIPT_DIRECTORY/forward-search-from-cli.ts")
ITER122_RENDERER_EXIT_CODE=$?
set -e

exit "$ITER122_RENDERER_EXIT_CODE"
