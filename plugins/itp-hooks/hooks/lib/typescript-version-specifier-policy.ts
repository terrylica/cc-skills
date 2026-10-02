/**
 * Shared policy evaluator: is a declared `typescript` version specifier
 * conformant with the "TypeScript 7 ONLY" doctrine?
 *
 * SSoT for the doctrine: ~/.claude/typescript-latest-CLAUDE.md
 * Hub row: ~/.claude/CLAUDE.md § "TypeScript 7 ONLY"
 *
 * Consumed by BOTH:
 *   - hooks/pretooluse-typescript-version-guard.ts        (Write|Edit on package.json)
 *   - hooks/pretooluse-typescript-legacy-install-command-guard.ts (Bash install commands)
 *
 * Factored into lib/ precisely so the two guards cannot drift on what
 * "legacy" means — a single evaluator, unit-tested once.
 *
 * Design note on why this is a verdict UNION rather than a boolean: three of
 * the five outcomes are NOT "block" but also NOT "clean", and conflating them
 * produces exactly the false positive an adversarial review would find. In
 * particular `npm:@typescript/typescript6@^6.0.2` contains the substring "6"
 * and would trip any naive major-version regex — yet it is the *sanctioned*
 * TS7 migration path (the compat alias that yields `tsc6` + the 6.0 API for
 * Volar / Angular / typescript-eslint / ts-morph, which TS 7.0 cannot serve
 * because 7.0 ships no programmatic API until 7.1). Denying it would block
 * the very escape route the policy prescribes.
 */

/** The doctrine's floor. Bump this, not scattered literals, when 8.0 lands. */
export const MINIMUM_ALLOWED_TYPESCRIPT_MAJOR_VERSION = 7;

/** npm dist-tags that always resolve to the newest published release. */
const ALWAYS_CURRENT_NPM_DIST_TAG_SPECIFIERS: ReadonlySet<string> = new Set([
  "latest",
  "next",
  "beta",
  "rc",
  "canary",
  "insiders",
  "dev",
  "*",
  "x",
  "",
]);

/**
 * Specifier protocols whose resolved version cannot be known from the
 * specifier text alone. Fail OPEN — a guard that blocks what it cannot
 * evaluate is a guard operators disable.
 */
const UNRESOLVABLE_SPECIFIER_PROTOCOL_PREFIXES: readonly string[] = [
  "workspace:",
  "catalog:",
  "file:",
  "link:",
  "portal:",
  "git+",
  "git:",
  "github:",
  "http://",
  "https://",
  "patch:",
];

/** The sanctioned TS-6.0 compat alias (provides `tsc6` + the 6.0 API). */
const SANCTIONED_TYPESCRIPT_SIX_COMPAT_ALIAS_PACKAGE_NAME = "@typescript/typescript6";

/** The frozen/deprecated preview channel that shipped the `tsgo` binary. */
const DEPRECATED_NATIVE_PREVIEW_PACKAGE_NAME = "@typescript/native-preview";

export type TypeScriptVersionSpecifierVerdict =
  | { kind: "conformant"; rationale: string }
  | { kind: "sanctioned-compat-alias"; rationale: string }
  | { kind: "unresolvable"; rationale: string }
  | { kind: "legacy"; detectedMajorVersion: number; rationale: string }
  | { kind: "deprecated-native-preview"; rationale: string };

/** Verdict kinds a guard must BLOCK on. Everything else is allowed. */
export function isBlockingTypeScriptVersionSpecifierVerdict(
  verdict: TypeScriptVersionSpecifierVerdict,
): boolean {
  return verdict.kind === "legacy" || verdict.kind === "deprecated-native-preview";
}

/**
 * Extract the version-range portion from an `npm:`-protocol alias specifier.
 * `npm:typescript@5.9.3` -> `5.9.3`; `npm:@scope/pkg@^6.0.2` -> `^6.0.2`.
 * Returns null when the alias carries no explicit range.
 */
function extractVersionRangeFromNpmProtocolAliasSpecifier(specifierAfterNpmPrefix: string): string | null {
  // A leading `@` belongs to the scope, so start the search past index 0.
  const lastAtSignIndex = specifierAfterNpmPrefix.lastIndexOf("@");
  if (lastAtSignIndex <= 0) return null;
  return specifierAfterNpmPrefix.slice(lastAtSignIndex + 1).trim();
}

/**
 * Parse the leading major version out of a single (non-union) semver range.
 * Tolerates the range operators npm accepts: ^ ~ >= <= > < = and a `v` prefix.
 * Returns null when no leading integer is present (e.g. a bare dist-tag).
 */
function parseLeadingMajorVersionFromSingleSemverRange(singleRange: string): number | null {
  const strippedOfRangeOperatorsAndVeePrefix = singleRange.replace(/^[\s^~>=<=]*v?/i, "").trim();
  const leadingIntegerMatch = /^(\d+)/.exec(strippedOfRangeOperatorsAndVeePrefix);
  if (!leadingIntegerMatch?.[1]) return null;
  return Number.parseInt(leadingIntegerMatch[1], 10);
}

/**
 * Evaluate one declared `typescript` (or alias) version specifier.
 *
 * Union ranges (`^6 || ^7`) are evaluated conservatively: if ANY branch would
 * permit a pre-7 install, the whole specifier is `legacy`. A range that admits
 * TypeScript 6 *is* a range that installs TypeScript 6 on some machine.
 */
export function evaluateTypeScriptVersionSpecifier(
  rawSpecifier: string,
): TypeScriptVersionSpecifierVerdict {
  const specifier = (rawSpecifier ?? "").trim();
  const lowercased = specifier.toLowerCase();

  // Sanctioned compat alias FIRST — it contains a "6" and must never be
  // misread as a legacy pin. This ordering is the whole reason for the union.
  if (lowercased.includes(SANCTIONED_TYPESCRIPT_SIX_COMPAT_ALIAS_PACKAGE_NAME)) {
    return {
      kind: "sanctioned-compat-alias",
      rationale: `\`${specifier}\` is the sanctioned TypeScript 6.0 compat alias (yields \`tsc6\` + the 6.0 programmatic API for Volar / Angular / typescript-eslint / ts-morph). Allowed by policy.`,
    };
  }

  if (lowercased.includes(DEPRECATED_NATIVE_PREVIEW_PACKAGE_NAME)) {
    return {
      kind: "deprecated-native-preview",
      rationale: `\`${specifier}\` uses ${DEPRECATED_NATIVE_PREVIEW_PACKAGE_NAME}, which is FROZEN and deprecated now that TypeScript 7 ships the native compiler as \`tsc\` itself. Use \`typescript@latest\` (nightlies: \`typescript@next\`).`,
    };
  }

  if (ALWAYS_CURRENT_NPM_DIST_TAG_SPECIFIERS.has(lowercased)) {
    return {
      kind: "conformant",
      rationale: `\`${specifier || "(empty)"}\` resolves to the newest published release.`,
    };
  }

  if (UNRESOLVABLE_SPECIFIER_PROTOCOL_PREFIXES.some((prefix) => lowercased.startsWith(prefix))) {
    return {
      kind: "unresolvable",
      rationale: `\`${specifier}\` resolves outside the npm registry; its version cannot be judged from the specifier text. Allowed (fail-open).`,
    };
  }

  // `npm:` alias — judge the aliased range, not the alias syntax.
  const rangeToEvaluate = lowercased.startsWith("npm:")
    ? extractVersionRangeFromNpmProtocolAliasSpecifier(specifier.slice("npm:".length))
    : specifier;

  if (rangeToEvaluate === null || rangeToEvaluate === "") {
    return {
      kind: "unresolvable",
      rationale: `\`${specifier}\` carries no explicit version range. Allowed (fail-open).`,
    };
  }

  if (ALWAYS_CURRENT_NPM_DIST_TAG_SPECIFIERS.has(rangeToEvaluate.toLowerCase().trim())) {
    return {
      kind: "conformant",
      rationale: `\`${specifier}\` resolves to the newest published release.`,
    };
  }

  // Conservative union handling: the lowest admissible major decides.
  const unionBranches = rangeToEvaluate.split("||");
  let lowestAdmissibleMajorVersion: number | null = null;
  for (const branch of unionBranches) {
    const branchMajor = parseLeadingMajorVersionFromSingleSemverRange(branch);
    if (branchMajor === null) continue;
    if (lowestAdmissibleMajorVersion === null || branchMajor < lowestAdmissibleMajorVersion) {
      lowestAdmissibleMajorVersion = branchMajor;
    }
  }

  if (lowestAdmissibleMajorVersion === null) {
    return {
      kind: "unresolvable",
      rationale: `\`${specifier}\` has no parseable major version. Allowed (fail-open).`,
    };
  }

  if (lowestAdmissibleMajorVersion < MINIMUM_ALLOWED_TYPESCRIPT_MAJOR_VERSION) {
    return {
      kind: "legacy",
      detectedMajorVersion: lowestAdmissibleMajorVersion,
      rationale: `\`${specifier}\` admits TypeScript ${lowestAdmissibleMajorVersion}.x, below the required major ${MINIMUM_ALLOWED_TYPESCRIPT_MAJOR_VERSION}.`,
    };
  }

  return {
    kind: "conformant",
    rationale: `\`${specifier}\` requires TypeScript ${lowestAdmissibleMajorVersion}.x.`,
  };
}

/**
 * Locate every `typescript`-family dependency specifier in package.json text.
 *
 * Deliberately regex-based rather than JSON.parse: the PreToolUse `Edit`
 * payload carries only `new_string`, a FRAGMENT that is virtually never valid
 * JSON. A JSON-only implementation would silently pass every Edit — the most
 * common way a legacy pin actually gets introduced.
 */
export function findTypeScriptDependencySpecifiersInPackageJsonText(
  packageJsonText: string,
): { dependencyName: string; specifier: string }[] {
  const results: { dependencyName: string; specifier: string }[] = [];
  const dependencyEntryPattern =
    /"(typescript|@typescript\/native|@typescript\/native-preview)"\s*:\s*"([^"]*)"/g;
  for (const match of packageJsonText.matchAll(dependencyEntryPattern)) {
    const dependencyName = match[1];
    const specifier = match[2];
    if (dependencyName === undefined || specifier === undefined) continue;
    results.push({ dependencyName, specifier });
  }
  return results;
}
