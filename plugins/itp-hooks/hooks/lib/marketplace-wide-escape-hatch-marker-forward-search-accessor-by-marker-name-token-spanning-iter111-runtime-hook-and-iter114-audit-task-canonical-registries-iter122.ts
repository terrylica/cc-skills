/**
 * Iter-122 forward-search registry accessor — operator-facing complement
 * to the iter-116 reverse-search accessor. Closes the symmetric direction
 * gap: pre-iter-122, when an operator was reading code and saw `# FOO-OK`
 * (or `# CARGO-TTY-SKIP`), the only way to learn what the marker did was
 * to grep the iter-111 / iter-114 registry source files by hand.
 *
 * ────────────────────────────────────────────────────────────────────
 *  Iter-122 design rationale
 * ────────────────────────────────────────────────────────────────────
 *
 * The iter-116 reverse-search resolved one direction of the operator
 * workflow:
 *
 *   "I want to opt out of THIS consumer hook/audit-task — what marker
 *    do I write?" → reverse-search by consumer-path
 *
 * Iter-122 resolves the symmetric forward direction:
 *
 *   "I'm reading source code and saw `# FOO-OK`. What does this marker
 *    do, and which consumer hook/audit-task recognizes it?"
 *   → forward-search by marker-name-token
 *
 * Single forward accessor:
 *
 *   `lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries(token)`
 *
 * Returns an array of discriminated-union hits (parallel to iter-116's
 * shape) encoding which registry the entry came from. The current
 * canonical state has each marker token in EXACTLY ONE registry, so
 * the array typically holds 0 or 1 entries — but the array shape leaves
 * room for future markers that might span both lifecycle layers.
 *
 * # Why a separate lib file (not extending iter-116's lib)?
 *
 * The iter-116 reverse-search-accessor file is named to encode its
 * lookup direction. Adding forward-direction functions there would
 * create a naming mismatch (`...reverse-search-accessor...` exporting
 * a forward-search function). Cleaner to ship a sibling lib whose name
 * encodes the forward direction. Both libs sit at the same level under
 * `plugins/itp-hooks/hooks/lib/` and the operator-facing iter-122 CLI
 * imports from both.
 *
 * # Fuzzy-fallback chain (symmetric to iter-116 CLI's chain)
 *
 *   1. Exact case-sensitive match (`FILE-SIZE-OK` → FILE-SIZE-OK)
 *   2. Exact case-insensitive match (`file-size-ok` → FILE-SIZE-OK)
 *   3. Substring search in marker token (`TTY` → CARGO-TTY-SKIP +
 *      CARGO-TTY-WRAP) — parallel to iter-120 basename-substring on
 *      consumer paths
 *   4. Levenshtein "Did you mean?" (`FIEL-SIZE-OK` → FILE-SIZE-OK) —
 *      parallel to iter-118 Levenshtein on consumer paths
 *   5. Full-list dump
 *
 * Levenshtein utilities (`computeLevenshteinEditDistance…`,
 * `isLevenshteinDistanceCloseEnough…`) are reused as-is from the
 * iter-116 reverse-search-accessor lib — they're algorithm-level
 * generic helpers that don't care whether the strings are file paths
 * or marker tokens.
 */

import {
  MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY,
  type MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry,
} from "./marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts";
import {
  MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY,
  type MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry,
} from "./marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts";
import {
  computeLevenshteinEditDistanceBetweenTwoStrings,
} from "./marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts";

/**
 * Discriminated-union shape encoding which canonical registry the
 * forward-search hit came from. Parallel to iter-116's reverse-search
 * shape. Callers branch on `originatingRegistryLifecycleLayerTag` to
 * access lifecycle-specific fields.
 */
export type EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag =
  | {
      readonly originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111";
      readonly matchedRegistryEntry: MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry;
    }
  | {
      readonly originatingRegistryLifecycleLayerTag: "AUDIT_TASK_ITER114";
      readonly matchedRegistryEntry: MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry;
    };

/**
 * Forward-lookup: given a marker name token, return every registry
 * entry that declares this marker as a recognized opt-out. Returns an
 * empty array when the token is not registered anywhere.
 *
 * Default behavior is CASE-SENSITIVE — marker names are UPPER-KEBAB-CASE
 * by convention (the lone exception `SSoT-OK` is grandfathered, see
 * iter-111 registry comments). The iter-122 CLI provides a case-
 * insensitive fallback path for operators who type lowercase by habit.
 *
 * Current canonical state has each marker in EXACTLY ONE registry, so
 * this typically returns 0 or 1 entries. The array return shape leaves
 * room for future markers spanning both lifecycle layers.
 */
export function lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries(
  markerNameTokenIncludingSuffix: string,
): ReadonlyArray<EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag> {
  const forwardSearchHits: EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag[] =
    [];

  for (const runtimeHookEntry of MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY) {
    if (
      runtimeHookEntry.markerNameTokenIncludingSuffix ===
      markerNameTokenIncludingSuffix
    ) {
      forwardSearchHits.push({
        originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111",
        matchedRegistryEntry: runtimeHookEntry,
      });
    }
  }
  for (const auditTaskEntry of MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY) {
    if (
      auditTaskEntry.markerNameTokenIncludingSuffix ===
      markerNameTokenIncludingSuffix
    ) {
      forwardSearchHits.push({
        originatingRegistryLifecycleLayerTag: "AUDIT_TASK_ITER114",
        matchedRegistryEntry: auditTaskEntry,
      });
    }
  }
  return forwardSearchHits;
}

/**
 * Case-insensitive variant: matches `file-size-ok` → `FILE-SIZE-OK`,
 * `bash-launchd-ok` → `BASH-LAUNCHD-OK`, etc. The iter-122 CLI invokes
 * this AFTER the case-sensitive lookup fails — symmetric to how iter-120
 * basename-substring runs only AFTER exact-path-match fails.
 */
export function lookupAllCanonicalRegistryEntriesByMarkerNameTokenCaseInsensitivelySpanningBothRegistries(
  operatorSuppliedQueryMarkerNameTokenWithAnyCasing: string,
): ReadonlyArray<EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag> {
  const operatorQueryLowercased =
    operatorSuppliedQueryMarkerNameTokenWithAnyCasing.toLowerCase();
  const forwardSearchHits: EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag[] =
    [];
  for (const runtimeHookEntry of MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY) {
    if (
      runtimeHookEntry.markerNameTokenIncludingSuffix.toLowerCase() ===
      operatorQueryLowercased
    ) {
      forwardSearchHits.push({
        originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111",
        matchedRegistryEntry: runtimeHookEntry,
      });
    }
  }
  for (const auditTaskEntry of MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY) {
    if (
      auditTaskEntry.markerNameTokenIncludingSuffix.toLowerCase() ===
      operatorQueryLowercased
    ) {
      forwardSearchHits.push({
        originatingRegistryLifecycleLayerTag: "AUDIT_TASK_ITER114",
        matchedRegistryEntry: auditTaskEntry,
      });
    }
  }
  return forwardSearchHits;
}

/**
 * Distinct marker name tokens across both registries, sorted
 * alphabetically. Used by the iter-122 CLI for the full-list-dump
 * fallback when nothing else matches, AND by the substring + Levenshtein
 * fuzzy-fallback functions as their search corpus.
 */
export function listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically(): ReadonlyArray<string> {
  const distinctMarkerNameTokens = new Set<string>();
  for (const runtimeHookEntry of MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY) {
    distinctMarkerNameTokens.add(runtimeHookEntry.markerNameTokenIncludingSuffix);
  }
  for (const auditTaskEntry of MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY) {
    distinctMarkerNameTokens.add(auditTaskEntry.markerNameTokenIncludingSuffix);
  }
  return [...distinctMarkerNameTokens].toSorted();
}

/**
 * Iter-120-parallel substring search but on marker name tokens rather
 * than consumer-path basenames. Catches operators who remember only
 * part of the marker name (e.g., "TTY" → CARGO-TTY-SKIP + CARGO-TTY-WRAP,
 * "FILE-SIZE" → FILE-SIZE-OK, "MATCHER" → MATCHER-NO-MULTIEDIT-OK +
 * WILDCARD-MATCHER-OK). Case-insensitive — operators don't think in
 * case-sensitive terms when recalling tokens.
 *
 * The caller is responsible for deciding when to invoke (typically:
 * after exact-match AND exact-case-insensitive-match both fail).
 */
export function findAllRegisteredMarkerNameTokensWhoseTokenContainsQueryStringCaseInsensitively(
  operatorSuppliedQueryStringToMatchAgainstMarkerTokens: string,
): ReadonlyArray<string> {
  const operatorQueryLowercased =
    operatorSuppliedQueryStringToMatchAgainstMarkerTokens.toLowerCase();
  return listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically().filter(
    (registeredMarkerToken) =>
      registeredMarkerToken.toLowerCase().includes(operatorQueryLowercased),
  );
}

/**
 * Ranking shape: registered marker name token paired with its
 * Levenshtein edit distance from the operator-supplied query token.
 * Parallel to iter-118's `RegisteredConsumerPathRankedByLevenshtein…`.
 */
export interface RegisteredMarkerNameTokenRankedByLevenshteinDistanceFromQuery {
  readonly markerNameTokenIncludingSuffix: string;
  readonly levenshteinEditDistanceFromOperatorSuppliedQuery: number;
}

/**
 * Iter-118-parallel ranking on marker name tokens. Computes edit
 * distance from the operator-supplied query to every registered marker
 * token, sorts ascending, returns the top-K closest matches. Used by
 * the iter-122 CLI to surface "Did you mean?" suggestions when an
 * operator typos a marker name (e.g., `FIEL-SIZE-OK` → FILE-SIZE-OK
 * with distance 2).
 *
 * Reuses `computeLevenshteinEditDistanceBetweenTwoStrings` from the
 * iter-116 reverse-search-accessor lib — generic algorithm, agnostic
 * to whether inputs are file paths or marker tokens.
 */
export function rankAllRegisteredMarkerNameTokensByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches(
  operatorSuppliedQueryMarkerNameToken: string,
  topKClosestMatchesToReturn: number,
): ReadonlyArray<RegisteredMarkerNameTokenRankedByLevenshteinDistanceFromQuery> {
  const allRegisteredMarkerTokens =
    listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically();
  const allRankedCandidates: RegisteredMarkerNameTokenRankedByLevenshteinDistanceFromQuery[] =
    allRegisteredMarkerTokens.map((registeredMarkerToken) => ({
      markerNameTokenIncludingSuffix: registeredMarkerToken,
      levenshteinEditDistanceFromOperatorSuppliedQuery:
        computeLevenshteinEditDistanceBetweenTwoStrings(
          operatorSuppliedQueryMarkerNameToken,
          registeredMarkerToken,
        ),
    }));
  const sortedRankedCandidates = allRankedCandidates.toSorted(
    (
      candidateA: RegisteredMarkerNameTokenRankedByLevenshteinDistanceFromQuery,
      candidateB: RegisteredMarkerNameTokenRankedByLevenshteinDistanceFromQuery,
    ) =>
      candidateA.levenshteinEditDistanceFromOperatorSuppliedQuery -
      candidateB.levenshteinEditDistanceFromOperatorSuppliedQuery,
  );
  return sortedRankedCandidates.slice(0, topKClosestMatchesToReturn);
}

/**
 * Render a single forward-search hit as a multi-line human-readable
 * block for terminal display by the iter-122 mise task. Parallel to
 * iter-116's `renderSingleReverseSearchHitAsHumanReadableTerminalBlock`
 * — same field layout, same example-comment-form pattern, same
 * lifecycle-tag-discrimination logic. Forward direction means the
 * "Marker" line is given (it's the query input) and the "Consumer"
 * line is the lookup result.
 */
export function renderSingleForwardSearchHitAsHumanReadableTerminalBlock(
  forwardSearchHit: EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag,
): string {
  if (
    forwardSearchHit.originatingRegistryLifecycleLayerTag ===
    "RUNTIME_HOOK_ITER111"
  ) {
    const entry = forwardSearchHit.matchedRegistryEntry;
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

  const entry = forwardSearchHit.matchedRegistryEntry;
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
