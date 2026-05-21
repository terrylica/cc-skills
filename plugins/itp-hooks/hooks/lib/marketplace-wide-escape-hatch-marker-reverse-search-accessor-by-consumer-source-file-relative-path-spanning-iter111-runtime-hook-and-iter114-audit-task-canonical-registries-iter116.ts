/**
 * Iter-116 reverse-search registry accessor — spans both the iter-111
 * RUNTIME-HOOK canonical registry and the iter-114 AUDIT-TASK canonical
 * registry. Closes the operator-workflow gap documented inline at the
 * end of iter-114 and re-affirmed by iter-115's regression-test footer.
 *
 * ────────────────────────────────────────────────────────────────────
 *  Iter-116 design rationale
 * ────────────────────────────────────────────────────────────────────
 *
 * The pre-iter-116 operator workflow for "I want to opt out of THIS
 * specific hook/audit-task — what marker do I write?" required one of:
 *
 *   (a) Table-scanning the 385-line operator-facing reference doc at
 *       `docs/marketplace-escape-hatch-marker-reference.md`. Slow when
 *       the operator only has the hook source-file path in hand.
 *   (b) Greping the iter-111 + iter-114 registries for the consumer
 *       path string. Requires knowing the registry file names.
 *   (c) Reading the hook source to find which marker token it passes
 *       to the iter-107 helper. Slowest path; defeats the purpose of
 *       the registry as a discoverability layer.
 *
 * Iter-116 introduces a single forward function:
 *
 *   `lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(consumerSourceFileRelativePath)`
 *
 * Returns an array (multi-marker consumers like the cargo-tty-guard
 * with its CARGO-TTY-SKIP + CARGO-TTY-WRAP pair return ≥2 entries) of
 * discriminated-union hits encoding which registry the entry came from,
 * the full registry entry, and a normalized human-readable summary.
 *
 * The function is intentionally a CROSS-REGISTRY joint accessor — not
 * a method on either registry — because:
 *
 *   - Coupling either registry to the other would force callers to
 *     import both even when they only need one.
 *   - The two registries have INTENTIONALLY DIFFERENT consumer-path
 *     field names (`consumerHookSourceFileRelativePath` vs
 *     `consumerAuditTaskSourceFileRelativePath`) to encode the runtime-
 *     vs-audit lifecycle layer at the type level. The joint accessor
 *     bridges them via a discriminated-union return shape.
 *
 * Reverse-search is O(N+M) where N=12 (iter-111) and M=8 (iter-114). A
 * Map index isn't worth the construction cost at these sizes; both
 * registries are scanned linearly.
 *
 * ────────────────────────────────────────────────────────────────────
 *  Iter-117+ candidate (queued by the iter-116 regression test)
 * ────────────────────────────────────────────────────────────────────
 *
 * Audit task verifying every entry's
 * `humanReadableEscapeHatchDescriptionForOperatorDocumentation` mentions
 * a hook/task name consistent with its declared consumer-path field —
 * catches stale descriptions after a hook is renamed without updating
 * the registry blurb.
 */

import {
  MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY,
  type MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry,
} from "./marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts";
import {
  MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY,
  type MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry,
} from "./marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts";

/**
 * Discriminated-union shape encoding which canonical registry the hit
 * came from. Callers branch on `originatingRegistryLifecycleLayerTag`
 * to access lifecycle-specific fields (e.g., window-semantics is only
 * meaningful for runtime-hook markers, not audit-task markers).
 */
export type EscapeHatchMarkerReverseSearchHitWithRegistryProvenanceTag =
  | {
      readonly originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111";
      readonly matchedRegistryEntry: MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry;
    }
  | {
      readonly originatingRegistryLifecycleLayerTag: "AUDIT_TASK_ITER114";
      readonly matchedRegistryEntry: MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry;
    };

/**
 * Reverse-lookup: given a consumer source file relative path (either a
 * hook source under `plugins/itp-hooks/hooks/` OR an audit task source
 * under `.mise/tasks/`), return every marker token that opts the caller
 * out of that consumer's enforcement.
 *
 * Returns an empty array when no markers target the given path — caller
 * can distinguish "no markers exist for this consumer" from "consumer
 * path is unknown" only by checking that the path exists on disk
 * separately (the registry is the authority on markers, not on which
 * files exist).
 *
 * Multi-marker consumers (e.g., `pretooluse-cargo-tty-guard.ts` which
 * honors both `CARGO-TTY-SKIP` and `CARGO-TTY-WRAP`) return ≥2 hits.
 */
export function lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
  consumerSourceFileRelativePath: string,
): ReadonlyArray<EscapeHatchMarkerReverseSearchHitWithRegistryProvenanceTag> {
  const reverseSearchHits: EscapeHatchMarkerReverseSearchHitWithRegistryProvenanceTag[] =
    [];

  for (const runtimeHookRegistryEntry of MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY) {
    if (
      runtimeHookRegistryEntry.consumerHookSourceFileRelativePath ===
      consumerSourceFileRelativePath
    ) {
      reverseSearchHits.push({
        originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111",
        matchedRegistryEntry: runtimeHookRegistryEntry,
      });
    }
  }

  for (const auditTaskRegistryEntry of MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY) {
    if (
      auditTaskRegistryEntry.consumerAuditTaskSourceFileRelativePath ===
      consumerSourceFileRelativePath
    ) {
      reverseSearchHits.push({
        originatingRegistryLifecycleLayerTag: "AUDIT_TASK_ITER114",
        matchedRegistryEntry: auditTaskRegistryEntry,
      });
    }
  }

  return reverseSearchHits;
}

/**
 * Convenience accessor: returns a sorted list of every distinct
 * consumer source file relative path that has ≥1 marker registered
 * against it, across both registries. Useful for the iter-116 mise
 * task to print an "available consumers" hint when the operator
 * supplies a path with no matches.
 */
export function listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically(): ReadonlyArray<string> {
  const distinctConsumerSourceFileRelativePaths = new Set<string>();
  for (const runtimeHookRegistryEntry of MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY) {
    distinctConsumerSourceFileRelativePaths.add(
      runtimeHookRegistryEntry.consumerHookSourceFileRelativePath,
    );
  }
  for (const auditTaskRegistryEntry of MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY) {
    distinctConsumerSourceFileRelativePaths.add(
      auditTaskRegistryEntry.consumerAuditTaskSourceFileRelativePath,
    );
  }
  return [...distinctConsumerSourceFileRelativePaths].toSorted();
}

/**
 * Iter-118 Levenshtein edit-distance computation between two strings —
 * standard 2-row dynamic-programming implementation. Used to rank
 * registered consumer paths by similarity to the operator-supplied
 * (likely-typo'd) query string when the iter-116 CLI hits the
 * unknown-path branch. Memory: O(min(a, b)); time: O(a × b).
 *
 * Function name encodes "Levenshtein edit distance" — standard
 * industry-terminology algorithm name — so future maintainers can
 * confirm the algorithm without reading the body.
 */
export function computeLevenshteinEditDistanceBetweenTwoStrings(
  stringA: string,
  stringB: string,
): number {
  if (stringA === stringB) return 0;
  if (stringA.length === 0) return stringB.length;
  if (stringB.length === 0) return stringA.length;

  // Two-row DP: only the previous row + current row are needed.
  // Using Array.from instead of `new Array(n)` because the latter trips
  // the oxlint unicorn/no-new-array rule (single-integer-arg constructor
  // is ambiguous between "sparse array of length n" and "1-element array
  // containing the integer").
  let previousRowOfEditDistances = Array.from<number>({
    length: stringB.length + 1,
  });
  for (
    let columnIndex = 0;
    columnIndex <= stringB.length;
    columnIndex += 1
  ) {
    previousRowOfEditDistances[columnIndex] = columnIndex;
  }
  let currentRowOfEditDistances = Array.from<number>({
    length: stringB.length + 1,
  }).fill(0);

  for (
    let rowIndex = 1;
    rowIndex <= stringA.length;
    rowIndex += 1
  ) {
    currentRowOfEditDistances[0] = rowIndex;
    for (
      let columnIndex = 1;
      columnIndex <= stringB.length;
      columnIndex += 1
    ) {
      const substitutionCost =
        stringA[rowIndex - 1] === stringB[columnIndex - 1] ? 0 : 1;
      currentRowOfEditDistances[columnIndex] = Math.min(
        currentRowOfEditDistances[columnIndex - 1] + 1, // insertion
        previousRowOfEditDistances[columnIndex] + 1, // deletion
        previousRowOfEditDistances[columnIndex - 1] + substitutionCost, // substitution
      );
    }
    [previousRowOfEditDistances, currentRowOfEditDistances] = [
      currentRowOfEditDistances,
      previousRowOfEditDistances,
    ];
  }

  return previousRowOfEditDistances[stringB.length];
}

/**
 * Iter-118 ranking shape: a registered consumer path paired with its
 * Levenshtein edit distance from the operator-supplied query.
 */
export interface RegisteredConsumerPathRankedByLevenshteinDistanceFromQuery {
  readonly consumerSourceFileRelativePath: string;
  readonly levenshteinEditDistanceFromOperatorSuppliedQuery: number;
}

/**
 * Iter-118 ranking function: compute Levenshtein distance from the
 * operator-supplied query to every registered consumer path, sort
 * ascending, and return the top-K matches. Used by the iter-116 CLI
 * to surface a "Did you mean?" suggestion instead of dumping the
 * full 19-path list when the operator typed a path with a typo.
 *
 * Caller is responsible for applying any relative-distance threshold
 * to decide whether the suggestions are meaningful enough to display
 * (vs falling back to the full list because the query is unrelated to
 * any registered path).
 */
export function rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches(
  operatorSuppliedQueryConsumerSourceFileRelativePath: string,
  topKClosestMatchesToReturn: number,
): ReadonlyArray<RegisteredConsumerPathRankedByLevenshteinDistanceFromQuery> {
  const allRegisteredConsumerPaths =
    listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically();
  const allRankedCandidates: RegisteredConsumerPathRankedByLevenshteinDistanceFromQuery[] =
    allRegisteredConsumerPaths.map((registeredConsumerPath) => ({
      consumerSourceFileRelativePath: registeredConsumerPath,
      levenshteinEditDistanceFromOperatorSuppliedQuery:
        computeLevenshteinEditDistanceBetweenTwoStrings(
          operatorSuppliedQueryConsumerSourceFileRelativePath,
          registeredConsumerPath,
        ),
    }));
  // Sort ascending by edit distance (closest matches first). Ties are
  // broken by alphabetical path order via the upstream sort, which is
  // stable in Array.prototype.toSorted.
  const sortedRankedCandidates = allRankedCandidates.toSorted(
    (
      candidateA: RegisteredConsumerPathRankedByLevenshteinDistanceFromQuery,
      candidateB: RegisteredConsumerPathRankedByLevenshteinDistanceFromQuery,
    ) =>
      candidateA.levenshteinEditDistanceFromOperatorSuppliedQuery -
      candidateB.levenshteinEditDistanceFromOperatorSuppliedQuery,
  );
  return sortedRankedCandidates.slice(0, topKClosestMatchesToReturn);
}

/**
 * Iter-118 threshold predicate: given the top-ranked candidate's edit
 * distance and the operator-supplied query length, decide whether the
 * candidate is close enough to display as a "Did you mean?" suggestion.
 *
 * The threshold is a fraction of the query length (default 1/3) — a
 * candidate within ⌊queryLength / 3⌋ edits is considered "plausibly a
 * typo of the intended path". Anything further is considered an
 * unrelated query, and the caller should fall back to displaying the
 * full registered-paths list rather than misleading the operator with
 * three random-looking suggestions.
 *
 * The fraction is documented as part of the function name so it can't
 * silently change without a rename.
 */
export function isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold(
  topRankedCandidateLevenshteinDistance: number,
  operatorSuppliedQueryLength: number,
): boolean {
  // For very short queries (e.g., "x"), allow up to 2 edits — otherwise
  // floor(1/3) = 0 and we'd reject every imperfect match. For longer
  // queries the fractional bound is more useful (typo in ≤33% of chars).
  const minimumAbsoluteAllowedEditDistanceForVeryShortQueries = 2;
  const fractionalAllowedEditDistanceBasedOnOneThirdOfQueryLength = Math.floor(
    operatorSuppliedQueryLength / 3,
  );
  const effectiveAllowedEditDistance = Math.max(
    minimumAbsoluteAllowedEditDistanceForVeryShortQueries,
    fractionalAllowedEditDistanceBasedOnOneThirdOfQueryLength,
  );
  return (
    topRankedCandidateLevenshteinDistance <= effectiveAllowedEditDistance
  );
}

/**
 * Render a single reverse-search hit as a multi-line human-readable
 * block for terminal display by the iter-116 mise task. Encodes the
 * lifecycle-layer tag explicitly so operators see which kind of
 * consumer the marker opts them out of (runtime hot path vs audit
 * task release-time cold path).
 */
export function renderSingleReverseSearchHitAsHumanReadableTerminalBlock(
  reverseSearchHit: EscapeHatchMarkerReverseSearchHitWithRegistryProvenanceTag,
): string {
  if (
    reverseSearchHit.originatingRegistryLifecycleLayerTag ===
    "RUNTIME_HOOK_ITER111"
  ) {
    const entry = reverseSearchHit.matchedRegistryEntry;
    const reasonPolicyHumanReadable =
      entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 0
        ? "Bare marker accepted (no reason required)"
        : `Reason required after colon — minimum ${entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional} characters`;
    const exampleCommentForm =
      entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 0
        ? `  # ${entry.markerNameTokenIncludingSuffix}`
        : `  # ${entry.markerNameTokenIncludingSuffix}: explain the deliberate exception here in at least ${entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional} characters`;
    return [
      `  Marker:                 ${entry.markerNameTokenIncludingSuffix}`,
      `  Lifecycle layer:        RUNTIME-HOOK (iter-111; consumed at every Write/Edit/Bash tool invocation)`,
      `  Consumer hook:          ${entry.consumerHookSourceFileRelativePath}`,
      `  Case sensitivity:       ${entry.caseSensitivityModeDeclaredAtConsumerCallSite}`,
      `  Window semantics:       ${entry.windowSemanticsModeDeclaredAtConsumerCallSite}`,
      `  Reason policy:          ${reasonPolicyHumanReadable}`,
      `  What it does:           ${entry.humanReadableEscapeHatchDescriptionForOperatorDocumentation}`,
      `  Example:`,
      exampleCommentForm,
    ].join("\n");
  }

  const entry = reverseSearchHit.matchedRegistryEntry;
  const reasonPolicyHumanReadable =
    entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 0
      ? "Bare marker accepted (no reason required)"
      : `Reason required after colon — minimum ${entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional} characters`;
  const exampleCommentForm =
    entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 0
      ? `  # ${entry.markerNameTokenIncludingSuffix}`
      : `  # ${entry.markerNameTokenIncludingSuffix}: explain the deliberate exception to this release-blocking invariant in at least ${entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional} characters`;
  return [
    `  Marker:                 ${entry.markerNameTokenIncludingSuffix}`,
    `  Lifecycle layer:        AUDIT-TASK (iter-114; consumed once per release-preflight by .mise/ audit tasks)`,
    `  Consumer audit task:    ${entry.consumerAuditTaskSourceFileRelativePath}`,
    `  Case sensitivity:       ${entry.caseSensitivityModeDeclaredAtConsumerCallSite}`,
    `  Reason policy:          ${reasonPolicyHumanReadable}`,
    `  What it does:           ${entry.releaseInvariantSuppressedDescriptionForOperatorDocumentation}`,
    `  Example:`,
    exampleCommentForm,
  ].join("\n");
}
