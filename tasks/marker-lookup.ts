#!/usr/bin/env bun
/**
 * marker-lookup — escape-hatch marker lookups across the iter-111 runtime-hook
 * and iter-114 audit-task registries: forward (marker → consumer, iter-122),
 * reverse (consumer path → markers, iter-116), or auto (iter-123 classifier).
 * The query is passed to the libraries as a value, never spliced into source.
 */
import {
  findAllRegisteredConsumerSourceFilePathsWhoseBasenameContainsQueryStringCaseInsensitively as findConsumersByBasename,
  isLevenshteinDistanceCloseEnoughToConsiderItOperatorTypoUsingOneThirdOfQueryLengthAsThreshold as isPlausibleTypo,
  listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically as listAllConsumerPaths,
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries as lookupByConsumerPath,
  rankAllRegisteredConsumerSourceFilePathsByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches as rankConsumerPaths,
  renderSingleReverseSearchHitAsHumanReadableTerminalBlock as renderReverseHit,
} from "../plugins/itp-hooks/hooks/lib/marker-reverse-search-accessor-iter116.ts";
import {
  findAllRegisteredMarkerNameTokensWhoseTokenContainsQueryStringCaseInsensitively as findMarkersBySubstring,
  listAllDistinctMarkerNameTokensAcrossBothRegistriesSortedAlphabetically as listAllMarkerTokens,
  lookupAllCanonicalRegistryEntriesByMarkerNameTokenCaseInsensitivelySpanningBothRegistries as lookupByMarkerCaseInsensitive,
  lookupAllCanonicalRegistryEntriesByMarkerNameTokenSpanningBothRegistries as lookupByMarker,
  rankAllRegisteredMarkerNameTokensByLevenshteinDistanceFromOperatorSuppliedQueryAndReturnTopKClosestMatches as rankMarkerTokens,
  renderSingleForwardSearchHitAsHumanReadableTerminalBlock as renderForwardHit,
  type EscapeHatchMarkerForwardSearchHitWithRegistryProvenanceTag as ForwardHit,
} from "../plugins/itp-hooks/hooks/lib/marker-forward-search-accessor-iter122.ts";
import { classifyOperatorQueryShapeForUnifiedLookupDispatchRouting as classifyQuery } from "../plugins/itp-hooks/hooks/lib/iter123-marker-lookup-direction-router.ts";

const EXIT_FOUND = 0;
const EXIT_USAGE = 1;
const EXIT_NOT_FOUND = 2;
const DID_YOU_MEAN_COUNT = 3;
const RUNTIME_REGISTRY = "plugins/itp-hooks/hooks/lib/escape-hatch-marker-registry-iter111.ts";
const AUDIT_REGISTRY = "plugins/itp-hooks/hooks/lib/audit-task-marker-registry-iter114.ts";

const USAGE = `Usage: tasks/marker-lookup.ts [--json] [--direction=forward|reverse|auto] <query>

  Look up escape-hatch markers in the iter-111 (runtime-hook) and iter-114
  (audit-task) canonical registries. <query> is a marker token (FILE-SIZE-OK)
  or a consumer path (plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts);
  basename fragments, marker substrings, lowercase and typos also resolve.

Flags:
  --direction=auto     (default) '/' → reverse; UPPER-KEBAB-CASE marker → forward;
                       anything else → forward, then reverse if forward finds nothing.
  --direction=forward  marker → consumer + explanation.
  --direction=reverse  consumer path → markers that opt out of it.
  --json               One JSON document on stdout, nothing on stderr:
                       {iter123UnifiedLookupEnvelope, dispatchedBackendResponse}. The
                       response's matchType is exact | basename-substring (reverse)
                       or exact | exact-case-insensitive | marker-substring (forward).
  -h, --help           Show this help.

Examples:
  tasks/marker-lookup.ts FILE-SIZE-OK
  tasks/marker-lookup.ts --direction=reverse file-size-guard
  tasks/marker-lookup.ts --json FILE-SIZE-OK | jq '.dispatchedBackendResponse.matchingMarkers[0]'

Exit codes:
  0 : found (at any fallback layer)
  1 : usage error (missing arg, --help, bad --direction value, unknown flag)
  2 : not found (the dispatched search, or both in the ambiguous case)`;

type RegistryHit = {
  originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111" | "AUDIT_TASK_ITER114";
  matchedRegistryEntry: object;
};

/** What one search produced: a JSON payload plus how to print it for humans. */
interface SearchResult {
  found: boolean;
  payload: Record<string, unknown>;
  print: () => void;
}

const plural = (count: number, suffix = "s") => (count === 1 ? "" : suffix);

function flattenHits(hits: ReadonlyArray<RegistryHit>) {
  return hits.map((hit) => ({
    lifecycleLayer: hit.originatingRegistryLifecycleLayerTag === "RUNTIME_HOOK_ITER111" ? "runtime-hook" : "audit-task",
    registryProvenanceTag: hit.originatingRegistryLifecycleLayerTag,
    ...hit.matchedRegistryEntry,
  }));
}

function foundResult(payload: Record<string, unknown>, headerLines: string[], blocks: string[]): SearchResult {
  return {
    found: true,
    payload: { status: "found", ...payload },
    print: () => console.log([...headerLines, blocks.join("\n\n")].join("\n")),
  };
}

/** Wording and JSON keys that differ between the two directions' not-found output. */
const NOT_FOUND_VOCABULARY = {
  reverse: {
    headline: "No registered escape-hatch markers target this consumer path",
    queryKey: "consumerSourceFileRelativePath",
    candidateKey: "consumerSourceFileRelativePath",
    listKey: "allRegisteredConsumerSourceFilePaths",
    kind: "consumer", hintNoun: "path", listLabel: "consumer paths", subject: "your consumer", spelling: "path",
  },
  forward: {
    headline: "No canonical registry entry matches the marker token",
    queryKey: "operatorSuppliedQuery",
    candidateKey: "markerNameTokenIncludingSuffix",
    listKey: "allRegisteredMarkerNameTokens",
    kind: "marker", hintNoun: "marker", listLabel: "marker tokens", subject: "the marker", spelling: "token",
  },
} as const;

/** Not-found: a Levenshtein did-you-mean when the top match is a plausible typo, else the full list. */
function notFoundResult(
  direction: keyof typeof NOT_FOUND_VOCABULARY,
  query: string,
  ranked: ReadonlyArray<{ name: string; distance: number }>,
  allNames: ReadonlyArray<string>,
): SearchResult {
  const words = NOT_FOUND_VOCABULARY[direction];
  const closeEnough = ranked.length > 0 && isPlausibleTypo(ranked[0].distance, query.length);
  const print = () => {
    console.error(`✗ ${words.headline}:\n    ${query}\n`);
    if (closeEnough) {
      console.error(`  Did you mean (top-${ranked.length} closest match${plural(ranked.length, "es")} by Levenshtein edit distance)?\n`);
      for (const { name, distance } of ranked) console.error(`    [${distance} edit${plural(distance)}] ${name}`);
      console.error(
        `\n  If none of these match, the ${words.kind} may not yet be registered. Add an entry to:\n    - Runtime hooks: ${RUNTIME_REGISTRY}\n    - Audit tasks:  ${AUDIT_REGISTRY}`,
      );
      return;
    }
    const topMatch = ranked.length > 0 ? `top match has ${ranked[0].distance} edit distance, ` : "";
    console.error(
      `  Hint: query is not close to any registered ${words.hintNoun} (${topMatch}threshold ⌊queryLen / 3⌋). Showing all ${allNames.length} registered ${words.listLabel}:\n`,
    );
    for (const name of allNames) console.error(`    - ${name}`);
    console.error(
      `\n  If ${words.subject} is genuinely registered but the ${words.spelling} differs significantly, check the\n  spelling against the list above. If the ${words.kind} is NOT yet registered, add an entry to\n  the appropriate canonical registry (see paths above).`,
    );
  };
  const didYouMean = ranked.map((c) => ({ [words.candidateKey]: c.name, levenshteinEditDistanceFromOperatorSuppliedQuery: c.distance }));
  return {
    found: false,
    payload: {
      status: "not-found",
      [words.queryKey]: query,
      didYouMean: closeEnough ? didYouMean : null,
      [words.listKey]: closeEnough ? null : allNames,
    },
    print,
  };
}

/** consumer path → markers: exact path, then basename substring (only without '/'), then Levenshtein. */
function reverseSearch(query: string): SearchResult {
  const exactHits = lookupByConsumerPath(query);
  if (exactHits.length > 0) {
    return foundResult(
      { matchType: "exact", consumerSourceFileRelativePath: query, markers: flattenHits(exactHits) },
      [`✓ Found ${exactHits.length} escape-hatch marker${plural(exactHits.length)} for consumer:\n    ${query}\n`],
      exactHits.map(renderReverseHit),
    );
  }
  const basenameMatches = query.includes("/") ? [] : findConsumersByBasename(query);
  if (basenameMatches.length > 0) {
    const hits = basenameMatches.flatMap((path) => lookupByConsumerPath(path));
    return foundResult(
      { matchType: "basename-substring", operatorSuppliedQueryString: query, matchingConsumerSourceFilePaths: basenameMatches, markers: flattenHits(hits) },
      [
        `✓ No exact path match for "${query}", but found ${basenameMatches.length} consumer${plural(basenameMatches.length)} whose basename contains your query (case-insensitive):\n`,
        ...basenameMatches.map((path) => `  ${path}`),
        "",
      ],
      hits.map(renderReverseHit),
    );
  }
  const ranked = rankConsumerPaths(query, DID_YOU_MEAN_COUNT).map((candidate) => ({
    name: candidate.consumerSourceFileRelativePath,
    distance: candidate.levenshteinEditDistanceFromOperatorSuppliedQuery,
  }));
  return notFoundResult("reverse", query, ranked, listAllConsumerPaths());
}

/** marker → consumer: exact, case-insensitive exact, substring, then Levenshtein / full list. */
function forwardSearch(query: string): SearchResult {
  const found = (matchType: string, hits: ReadonlyArray<ForwardHit>, headerLines: string[], extra = {}) =>
    foundResult(
      { matchType, operatorSuppliedQuery: query, ...extra, matchingMarkers: flattenHits(hits) },
      headerLines,
      hits.map(renderForwardHit),
    );

  const exactHits = lookupByMarker(query);
  if (exactHits.length > 0) {
    return found("exact", exactHits, [`✓ Found ${exactHits.length} canonical registry entry/entries for marker:\n    ${query}\n`]);
  }
  const caseInsensitiveHits = lookupByMarkerCaseInsensitive(query);
  if (caseInsensitiveHits.length > 0) {
    const canonical = caseInsensitiveHits[0].matchedRegistryEntry.markerNameTokenIncludingSuffix;
    return found("exact-case-insensitive", caseInsensitiveHits, [`✓ Marker "${query}" matches canonical "${canonical}" (case-insensitive):\n`]);
  }
  const substringTokens = findMarkersBySubstring(query);
  if (substringTokens.length > 0) {
    return found(
      "marker-substring",
      substringTokens.flatMap((token) => lookupByMarker(token)),
      [
        `✓ No exact match for "${query}", but found ${substringTokens.length} marker${plural(substringTokens.length)} whose token contains your query (case-insensitive):\n`,
        ...substringTokens.map((token) => `  ${token}`),
        "",
      ],
      { matchingMarkerNameTokens: substringTokens },
    );
  }
  const ranked = rankMarkerTokens(query, DID_YOU_MEAN_COUNT).map((candidate) => ({
    name: candidate.markerNameTokenIncludingSuffix,
    distance: candidate.levenshteinEditDistanceFromOperatorSuppliedQuery,
  }));
  return notFoundResult("forward", query, ranked, listAllMarkerTokens());
}

function usageError(message?: string): never {
  if (message) console.error(`ERROR: ${message}`);
  console.log(USAGE);
  process.exit(EXIT_USAGE);
}

type Direction = "forward" | "reverse" | "auto";

function parseArguments(argv: string[]): { json: boolean; direction: Direction; query: string } {
  let json = false;
  let direction: Direction = "auto";
  let index = 0;
  for (; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--") {
      index++;
      break;
    }
    if (arg === "--json") json = true;
    else if (arg === "--help" || arg === "-h") usageError();
    else if (arg.startsWith("--direction=")) {
      const value = arg.slice("--direction=".length);
      if (value !== "forward" && value !== "reverse" && value !== "auto") {
        usageError(`invalid --direction value: ${value} (expected forward|reverse|auto)`);
      }
      direction = value;
    } else if (arg.startsWith("--")) usageError(`unknown flag: ${arg}`);
    else break;
  }
  const positional = argv.slice(index);
  if (positional.length !== 1) usageError();
  return { json, direction, query: positional[0] };
}

function main(): number {
  const { json, direction, query } = parseArguments(process.argv.slice(2));
  const classification = classifyQuery(query);
  const classifiedTag = classification.classifiedDispatchDirectionTag;
  const effectiveDirection =
    direction !== "auto" ? direction
    : classifiedTag === "REVERSE_SEARCH_ITER116_CONFIDENT" ? "reverse"
    : classifiedTag === "FORWARD_SEARCH_ITER122_CONFIDENT" ? "forward"
    : "ambiguous-forward-then-reverse";
  const routingRationale =
    direction === "auto"
      ? `auto-detect classifier: ${classification.classifierRationaleForOperatorTerminalOutput}`
      : `operator --direction=${direction} override (bypassing auto-detect; classifier would have suggested: ${classifiedTag})`;

  const emitJson = (result: SearchResult, dispatchedBackend: string, effectiveRoutingRationale: string) => {
    const iter123UnifiedLookupEnvelope = {
      operatorSuppliedQuery: query,
      classifiedDispatchDirectionTag: classifiedTag,
      classifierRationale: classification.classifierRationaleForOperatorTerminalOutput,
      effectiveDispatchDirection: effectiveDirection,
      effectiveRoutingRationale,
      dispatchedBackend,
    };
    console.log(JSON.stringify({ iter123UnifiedLookupEnvelope, dispatchedBackendResponse: result.payload }, null, 2));
  };
  const exitCodeFor = (result: SearchResult) => (result.found ? EXIT_FOUND : EXIT_NOT_FOUND);

  if (effectiveDirection !== "ambiguous-forward-then-reverse") {
    const result = effectiveDirection === "forward" ? forwardSearch(query) : reverseSearch(query);
    if (json) {
      emitJson(result, effectiveDirection === "forward" ? "iter122-forward-search" : "iter116-reverse-search", routingRationale);
    } else {
      console.log(`ⓘ Routing: ${routingRationale}\n`);
      result.print();
    }
    return exitCodeFor(result);
  }

  // Ambiguous: forward first; only when it finds nothing, fall back to reverse.
  const forwardResult = forwardSearch(query);
  if (json) {
    if (forwardResult.found) {
      emitJson(forwardResult, "iter122-forward-search", "ambiguous classification; forward search found a hit on first attempt (reverse fallback not exercised)");
      return EXIT_FOUND;
    }
    const reverseResult = reverseSearch(query);
    const backend = reverseResult.found ? "iter116-reverse-search" : "both-exhausted";
    emitJson(reverseResult, backend, "ambiguous classification; forward search returned no hits; fell back to reverse search");
    return exitCodeFor(reverseResult);
  }
  console.log(`ⓘ Routing: ${routingRationale}\n`);
  console.log("→ Attempting forward search first (iter-122) ...\n");
  forwardResult.print();
  if (forwardResult.found) return EXIT_FOUND;
  console.log("\nⓘ Forward search returned no hits; falling back to reverse search (iter-116) ...\n");
  const reverseResult = reverseSearch(query);
  reverseResult.print();
  return exitCodeFor(reverseResult);
}

process.exit(main());
