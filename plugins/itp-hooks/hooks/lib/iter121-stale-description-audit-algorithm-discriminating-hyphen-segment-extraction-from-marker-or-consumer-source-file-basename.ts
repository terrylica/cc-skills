/**
 * Iter-121 stale-description audit algorithm — extracted into a typed
 * library so the audit task AND its regression test can both import the
 * SAME extraction logic instead of duplicating it. Catches the bug class
 * where an operator renames a hook/audit-task (updating the consumer-
 * path field in the canonical registry) but forgets to update the
 * `humanReadableEscapeHatchDescriptionForOperatorDocumentation` /
 * `releaseInvariantSuppressedDescriptionForOperatorDocumentation` field,
 * leaving the operator-facing doc with a stale name.
 *
 * # Algorithm: discriminating-hyphen-segment mention invariant
 *
 * For each registry entry:
 *
 *   1. Extract MARKER discriminating segments — split the marker name
 *      token by '-', lowercase, drop suffix tokens {OK, SKIP, WRAP} that
 *      every marker shares (non-discriminating).
 *
 *   2. Extract BASENAME discriminating segments — take the basename of
 *      the consumer source-file path, strip the final extension, split
 *      by '-', lowercase, drop generic-prefix segments (pretooluse,
 *      posttooluse, audit, guard, patterns, marketplace, wide, …) and
 *      iteration-suffix tokens (iter111, iter114, …) that appear in
 *      many entries and so don't discriminate any specific entry.
 *
 *   3. Build candidate-substring set — for each remaining segment, add
 *      the segment itself, PLUS adjacent-pair kebab-case joins
 *      ("file-size", "spawn-sync") so the audit passes when the
 *      description references the canonical kebab-case pair rather than
 *      the individual words.
 *
 *   4. Verify the description (lowercased) contains AT LEAST ONE
 *      candidate as a substring. If NONE: report as stale-description
 *      candidate hit.
 *
 * # Why "at least one segment" rather than "all segments"?
 *
 * Descriptions paraphrase, explain context, reference adjacent concepts.
 * Requiring ALL segments would false-positive on legitimate descriptions
 * that use synonyms or focus on the policy domain. Requiring AT LEAST
 * ONE catches the unmoored case (description references neither the
 * marker NOR the consumer-path basename in any form) while preserving
 * descriptive freedom.
 *
 * # Empirical baseline (iter-121 ship-time, 2026-05-21)
 *
 * Runs clean against the 20 baseline entries across both canonical
 * registries (12 iter-111 runtime-hook + 8 iter-114 audit-task). The
 * algorithm was tuned to that baseline — the stoplists below were
 * derived by tracing every entry by hand to ensure the audit passes
 * green AND would catch a synthetic mismatch.
 */

// Marker-suffix tokens that appear in every marker name and so prove
// nothing about description grounding.
export const NON_DISCRIMINATING_MARKER_SUFFIX_TOKENS_SHARED_ACROSS_ALL_REGISTRY_ENTRIES =
  new Set<string>(["ok", "skip", "wrap"]);

// Basename segments that appear in many or all registry-entry consumer
// paths and so don't discriminate between entries. Derived from manual
// inspection of all 20 baseline entries.
export const NON_DISCRIMINATING_BASENAME_PREFIX_AND_GENERIC_SEGMENTS =
  new Set<string>([
    // Hook lifecycle layer prefixes
    "pretooluse",
    "posttooluse",
    "stop",
    "subagentstop",
    "userpromptsubmit",
    "sessionstart",
    "sessionend",
    "precompact",
    "notification",
    // Audit / mise prefixes
    "audit",
    // Common generic suffixes
    "guard",
    "patterns",
    "lib",
    "helper",
    "helpers",
    "checker",
    "validator",
    "task",
    "tasks",
    // Plumbing / marketplace meta-words
    "marketplace",
    "wide",
    "canonical",
    "registry",
    "cross",
    "plugin",
    "mise",
    "hooks",
    "hook",
    // File-extension fragments (after extension-strip, these would be
    // re-introduced if the basename had a double-dotted extension like
    // .test.ts; keep them in the stoplist defensively)
    "ts",
    "sh",
    "mjs",
    "js",
    "tsx",
    "jsx",
    // Boilerplate joiners
    "and",
    "or",
    "for",
    "to",
    "of",
    "the",
    "is",
    "in",
    "on",
    "by",
    "with",
    "from",
    "no",
  ]);

// Iteration-suffix tokens like "iter71", "iter106", "iter114" label the
// iteration that authored the file, not discriminating content. Match
// `iter` followed by ≥1 digits.
export const ITERATION_SUFFIX_TOKEN_REGEX_PATTERN_TO_DROP_FROM_BASENAME_SEGMENTS =
  /^iter\d+$/;

// Minimum segment length to keep — single-character segments are noise.
export const MINIMUM_KEPT_SEGMENT_CHARACTER_COUNT_TO_FILTER_OUT_SINGLE_CHAR_NOISE = 2;

/**
 * Extract discriminating hyphen-segments from a marker name token. Drops
 * the universal suffix tokens (OK/SKIP/WRAP) since every marker has one.
 */
export function extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix(
  markerNameTokenIncludingSuffix: string,
): ReadonlyArray<string> {
  return markerNameTokenIncludingSuffix
    .toLowerCase()
    .split("-")
    .filter(
      (segment) =>
        !NON_DISCRIMINATING_MARKER_SUFFIX_TOKENS_SHARED_ACROSS_ALL_REGISTRY_ENTRIES.has(
          segment,
        ),
    )
    .filter(
      (segment) =>
        segment.length >=
        MINIMUM_KEPT_SEGMENT_CHARACTER_COUNT_TO_FILTER_OUT_SINGLE_CHAR_NOISE,
    );
}

/**
 * Extract discriminating hyphen-segments from the basename of a consumer
 * source-file relative path. Strips the final extension, splits by '-',
 * drops generic-prefix segments and iteration-suffix tokens.
 */
export function extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename(
  consumerSourceFileRelativePath: string,
): ReadonlyArray<string> {
  const finalSlashIndex = consumerSourceFileRelativePath.lastIndexOf("/");
  const basenameWithExtension =
    finalSlashIndex === -1
      ? consumerSourceFileRelativePath
      : consumerSourceFileRelativePath.slice(finalSlashIndex + 1);
  const finalDotIndex = basenameWithExtension.lastIndexOf(".");
  const basenameWithoutExtension =
    finalDotIndex === -1
      ? basenameWithExtension
      : basenameWithExtension.slice(0, finalDotIndex);
  return basenameWithoutExtension
    .toLowerCase()
    .split("-")
    .filter(
      (segment) =>
        !NON_DISCRIMINATING_BASENAME_PREFIX_AND_GENERIC_SEGMENTS.has(segment),
    )
    .filter(
      (segment) =>
        !ITERATION_SUFFIX_TOKEN_REGEX_PATTERN_TO_DROP_FROM_BASENAME_SEGMENTS.test(
          segment,
        ),
    )
    .filter(
      (segment) =>
        segment.length >=
        MINIMUM_KEPT_SEGMENT_CHARACTER_COUNT_TO_FILTER_OUT_SINGLE_CHAR_NOISE,
    );
}

/**
 * Build the candidate-substring set the description must contain AT
 * LEAST ONE of. Includes both raw segments AND adjacent-pair kebab-case
 * joins. Only ADJACENT pairs (not all C(n,2) combinations) to keep the
 * candidate set linear in segment count.
 */
export function buildCandidateSubstringSetWithSegmentsAndAdjacentPairKebabCaseJoins(
  discriminatingSegments: ReadonlyArray<string>,
): ReadonlyArray<string> {
  const candidates: string[] = [...discriminatingSegments];
  for (
    let segmentIndex = 0;
    segmentIndex < discriminatingSegments.length - 1;
    segmentIndex += 1
  ) {
    candidates.push(
      `${discriminatingSegments[segmentIndex]}-${discriminatingSegments[segmentIndex + 1]}`,
    );
  }
  return candidates;
}

/**
 * Top-level predicate: does the description reference at least one
 * discriminating hyphen-segment from the marker name OR the consumer-
 * path basename? Returns the candidate substring that matched (for
 * debugging output) or null when NONE matched.
 */
export function findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename(
  markerNameTokenIncludingSuffix: string,
  consumerSourceFileRelativePath: string,
  humanReadableDescription: string,
): string | null {
  const markerSegments =
    extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix(
      markerNameTokenIncludingSuffix,
    );
  const basenameSegments =
    extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename(
      consumerSourceFileRelativePath,
    );
  const candidateSubstringsToMatchInDescription = [
    ...buildCandidateSubstringSetWithSegmentsAndAdjacentPairKebabCaseJoins(
      markerSegments,
    ),
    ...buildCandidateSubstringSetWithSegmentsAndAdjacentPairKebabCaseJoins(
      basenameSegments,
    ),
  ];
  const descriptionLowercased = humanReadableDescription.toLowerCase();
  for (const candidateSubstring of candidateSubstringsToMatchInDescription) {
    if (descriptionLowercased.includes(candidateSubstring)) {
      return candidateSubstring;
    }
  }
  return null;
}
