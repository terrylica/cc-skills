/**
 * Iter-123 unified-lookup query-shape auto-detection router. Inspects an
 * operator-supplied query string and decides whether it most likely
 * names a CONSUMER-SOURCE-FILE-RELATIVE-PATH (route to iter-116 reverse
 * search) or a MARKER-NAME-TOKEN (route to iter-122 forward search).
 * Eliminates the iter-116-vs-iter-122 dispatch decision from the
 * operator workflow.
 *
 * ────────────────────────────────────────────────────────────────────
 *  Iter-123 design rationale
 * ────────────────────────────────────────────────────────────────────
 *
 * Pre-iter-123 the marketplace shipped two operator-facing CLIs:
 *
 *   - iter-116 reverse: takes a consumer-path, returns marker(s)
 *   - iter-122 forward: takes a marker-token, returns consumer(s)
 *
 * Operators had to remember which task name corresponds to which
 * lookup direction. The two task names are >130 characters each and
 * differ only by the words "reverse-search-accessor" vs "forward-
 * search-accessor" plus the noun ordering — error-prone in shell
 * completion + tab-history.
 *
 * Iter-123 introduces a single unified CLI that classifies the query
 * shape and dispatches to the right backend. Three classification
 * rules, evaluated top-to-bottom:
 *
 *   1. Query contains a `/` separator
 *      → CONFIDENT path shape → iter-116 reverse search
 *
 *   2. Query matches strict canonical-marker regex
 *      `^[A-Z][A-Z0-9-]*-(OK|SKIP|WRAP)$`
 *      → CONFIDENT marker shape → iter-122 forward search
 *      (The `SSoT-OK` grandfathered mixed-case marker is handled
 *       via a separate `MIXED_CASE_GRANDFATHERED_MARKER_TOKENS` set
 *       so the regex stays strict.)
 *
 *   3. Otherwise — query is AMBIGUOUS (no slash, not all-uppercase,
 *      no canonical marker suffix). Likely operator typed a basename
 *      (e.g., `file-size-guard`) or a marker fragment (e.g., `TTY`)
 *      or a typo'd marker missing the `-OK` suffix (e.g., `FILE-SIZE`).
 *      → TRY forward search first (cheaper — substring + Levenshtein
 *      across 20 markers vs 20 paths); if forward returns no hits AND
 *      no plausible-typo Did-You-Mean, fall back to reverse search.
 *
 * The classification function returns a discriminated-union shape
 * encoding the decision PLUS a human-readable rationale string for
 * the operator's terminal output ("query contains `/` → routing to
 * reverse-search"). The rationale string makes the auto-detect
 * decision transparent rather than magic.
 *
 * # Operator override
 *
 * The iter-123 CLI accepts a `--direction=forward|reverse|auto` flag
 * (default `auto`). When set to `forward` or `reverse`, the classifier
 * is bypassed and the explicit direction is dispatched. This is the
 * escape hatch for operators who KNOW they want one direction but the
 * heuristic would have routed differently (e.g., a marker token that
 * happens to contain a `/` — unlikely but defensively supported).
 */

/**
 * Canonical-marker strict regex: UPPER-KEBAB-CASE token ending with
 * one of the three known marker suffixes. Anchored start-to-end so a
 * mixed-case string with embedded `-OK` doesn't match.
 *
 * NOTE: The single grandfathered mixed-case marker `SSoT-OK` does NOT
 * match this regex (the lowercase `o` in `SoT` violates the strict
 * UPPER-CASE requirement). It's handled separately below via an
 * explicit set rather than weakening the regex — a strict regex
 * minimizes false-positives for ambiguous tokens.
 */
export const CANONICAL_UPPER_KEBAB_CASE_MARKER_NAME_REGEX_INCLUDING_SUFFIX_FAMILY =
  /^[A-Z][A-Z0-9-]*-(OK|SKIP|WRAP)$/;

/**
 * Grandfathered-mixed-case marker tokens that don't match the strict
 * UPPER-KEBAB-CASE regex but are nevertheless canonical markers (per
 * the iter-111 registry's grandfathering note). Iter-123 classifies
 * these as CONFIDENT marker shape just like the regex-matched tokens.
 *
 * Current set: `SSoT-OK` (the grandfathered mixed-case marker — the
 * lowercase `o` in `SoT` was historically chosen for stylistic
 * "Single Source of Truth" abbreviation rather than strict
 * UPPER-CASE compliance). Future grandfathered exceptions can be
 * added here without weakening the canonical regex.
 */
export const GRANDFATHERED_MIXED_CASE_MARKER_NAME_TOKENS_NOT_MATCHING_STRICT_UPPER_KEBAB_REGEX =
  new Set<string>(["SSoT-OK"]);

/**
 * Discriminated-union result encoding the classification decision and
 * a human-readable rationale string. The CLI prints the rationale so
 * the operator can see WHY the heuristic routed where it did.
 */
export type UnifiedLookupQueryShapeClassificationResult =
  | {
      readonly classifiedDispatchDirectionTag: "REVERSE_SEARCH_ITER116_CONFIDENT";
      readonly classifierRationaleForOperatorTerminalOutput: string;
    }
  | {
      readonly classifiedDispatchDirectionTag: "FORWARD_SEARCH_ITER122_CONFIDENT";
      readonly classifierRationaleForOperatorTerminalOutput: string;
    }
  | {
      readonly classifiedDispatchDirectionTag: "AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE";
      readonly classifierRationaleForOperatorTerminalOutput: string;
    };

/**
 * Classify an operator-supplied query string into one of three
 * dispatch directions. Pure function — no I/O, no registry access.
 *
 * Rules (top-to-bottom precedence):
 *
 *   1. `/` present                                  → REVERSE (confident)
 *   2. Strict UPPER-KEBAB-CASE marker regex match   → FORWARD (confident)
 *   3. Grandfathered mixed-case marker token        → FORWARD (confident)
 *   4. Anything else                                → AMBIGUOUS
 */
export function classifyOperatorQueryShapeForUnifiedLookupDispatchRouting(
  operatorSuppliedQueryString: string,
): UnifiedLookupQueryShapeClassificationResult {
  if (operatorSuppliedQueryString.includes("/")) {
    return {
      classifiedDispatchDirectionTag: "REVERSE_SEARCH_ITER116_CONFIDENT",
      classifierRationaleForOperatorTerminalOutput: `query contains '/' → CONFIDENT path-shape → routing to iter-116 reverse-search (consumer-path → marker)`,
    };
  }

  if (
    CANONICAL_UPPER_KEBAB_CASE_MARKER_NAME_REGEX_INCLUDING_SUFFIX_FAMILY.test(
      operatorSuppliedQueryString,
    )
  ) {
    return {
      classifiedDispatchDirectionTag: "FORWARD_SEARCH_ITER122_CONFIDENT",
      classifierRationaleForOperatorTerminalOutput: `query matches canonical UPPER-KEBAB-CASE-with-OK/SKIP/WRAP-suffix marker shape → CONFIDENT marker-shape → routing to iter-122 forward-search (marker → consumer-path)`,
    };
  }

  if (
    GRANDFATHERED_MIXED_CASE_MARKER_NAME_TOKENS_NOT_MATCHING_STRICT_UPPER_KEBAB_REGEX.has(
      operatorSuppliedQueryString,
    )
  ) {
    return {
      classifiedDispatchDirectionTag: "FORWARD_SEARCH_ITER122_CONFIDENT",
      classifierRationaleForOperatorTerminalOutput: `query "${operatorSuppliedQueryString}" is a grandfathered mixed-case marker token (registered exception to strict UPPER-KEBAB-CASE convention) → CONFIDENT marker-shape → routing to iter-122 forward-search`,
    };
  }

  return {
    classifiedDispatchDirectionTag:
      "AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE",
    classifierRationaleForOperatorTerminalOutput: `query has no '/' AND does not match strict canonical-marker shape → AMBIGUOUS → trying iter-122 forward-search first (marker substring/Levenshtein); falling back to iter-116 reverse-search (consumer basename-substring) if forward returns nothing`,
  };
}
