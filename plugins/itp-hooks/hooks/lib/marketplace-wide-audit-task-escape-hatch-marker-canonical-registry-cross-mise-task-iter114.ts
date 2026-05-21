/**
 * Marketplace-wide canonical registry of every AUDIT-TASK escape-hatch
 * marker — a parallel registry to the iter-111 RUNTIME-HOOK marker
 * registry, covering markers that are consumed by `.mise/` preflight
 * audit tasks rather than by runtime PreToolUse/PostToolUse hooks.
 *
 * # Why a SECOND registry exists (iter-114 rationale)
 *
 * The iter-111 canonical registry tracks markers consumed by RUNTIME
 * hooks via the iter-107 shared helper. Those markers fire on EVERY
 * Write/Edit/Bash — they live in the hot path.
 *
 * The audit-task markers tracked here fire ONLY during release
 * preflight (or on-demand `mise run audit-...`). They opt operators out
 * of a release-blocking invariant check rather than a runtime guard.
 * The two layers have different:
 *
 *   - LIFECYCLE: runtime markers checked thousands of times per session;
 *                audit markers checked once per release.
 *   - CONSUMER: runtime markers consumed via the iter-107 helper
 *               (typed TypeScript API); audit markers consumed via
 *               bash grep in a `.mise/tasks/audit-*.sh` script.
 *   - SCOPE: runtime markers suppress a per-file enforcement;
 *           audit markers suppress a marketplace-wide invariant check
 *           on a specific cohort of files (Stop hooks, PostToolUse
 *           hooks, etc.).
 *   - REASON POLICY: runtime markers usually accept bare marker;
 *                    audit markers often require a ≥10-char reason
 *                    (legitimate exceptions to release-blocking
 *                    invariants demand justification).
 *
 * Keeping them in two separate registries preserves the type-safety
 * of each (the field name `consumerSourceFileRelativePath` can refer
 * unambiguously to a hook or an audit task without polymorphism).
 *
 * # What this registry encodes
 *
 * Every AUDIT-TASK marker is declared here with:
 *
 *   - `markerNameTokenIncludingSuffix`: exact spelling
 *   - `consumerAuditTaskSourceFileRelativePath`: which `.mise/` audit
 *     task recognizes it as an opt-out
 *   - `caseSensitivityModeDeclaredAtConsumerCallSite`: CASE_SENSITIVE
 *     (default for audit markers — bash grep -E is case-sensitive
 *     unless `-i` is explicitly passed)
 *   - `minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional`:
 *     usually ≥10 for audit markers because release-blocking invariants
 *     require justification
 *   - `releaseInvariantSuppressedDescriptionForOperatorDocumentation`:
 *     plain-English description of what release-blocking invariant
 *     the marker opts the file out of
 *
 * # How this registry is used
 *
 * 1. The iter-113 doc generator
 *    (`generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry.sh`)
 *    was extended in iter-114 to render a SECOND section in
 *    `docs/marketplace-escape-hatch-marker-reference.md` listing every
 *    audit-task marker alongside the runtime markers. Operators get a
 *    single artifact for marker discovery covering both lifecycle layers.
 *
 * 2. Future iters (115+) may extend the iter-111 producer-typo audit to
 *    also load this registry, enabling cross-layer typo detection in
 *    `.mise/` task source files.
 *
 * # When adding a new audit marker
 *
 * 1. Add the grep-based detection in the `.mise/tasks/audit-*.sh`
 *    file, typically of the form
 *    `grep -v "MARKER-NAME-OK"` or with a `-OK: reason` suffix gate.
 * 2. Add an entry to
 *    `MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY`
 *    below with all fields populated.
 * 3. Re-run the iter-113 doc generator
 *    (`mise run generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry`)
 *    to regenerate the operator-facing doc.
 */

export interface MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry {
  /**
   * Exact marker spelling INCLUDING the suffix (`-OK` for audit markers;
   * `-SKIP`/`-WRAP` suffixes are runtime-marker-only).
   */
  readonly markerNameTokenIncludingSuffix: string;

  /**
   * Repo-root-relative path to the `.mise/tasks/audit-*.sh` source file
   * that READS this marker via bash grep. The audit task's release-
   * blocking invariant is bypassed when the marker appears on the
   * relevant line(s).
   */
  readonly consumerAuditTaskSourceFileRelativePath: string;

  /**
   * Audit markers are CASE_SENSITIVE by default — bash `grep -E`
   * pattern matching is case-sensitive unless the audit task
   * explicitly passes `-i`. As of iter-114 all 8 audit markers in the
   * marketplace use CASE_SENSITIVE matching; the field is included
   * here for future extension and for parity with the iter-111 runtime
   * registry's field shape.
   */
  readonly caseSensitivityModeDeclaredAtConsumerCallSite:
    | "CASE_SENSITIVE"
    | "CASE_INSENSITIVE";

  /**
   * Minimum reason character count required after a colon. Audit
   * markers commonly require ≥10 chars (legitimate exceptions to
   * release-blocking invariants demand justification). 0 means a
   * bare marker without a reason is accepted.
   */
  readonly minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: number;

  /**
   * Plain-English description of which release-blocking invariant the
   * marker opts the file out of. Used by the iter-113 doc generator
   * and by future operator-facing documentation generators.
   */
  readonly releaseInvariantSuppressedDescriptionForOperatorDocumentation: string;
}

/**
 * Canonical registry — single source of truth for every marketplace
 * AUDIT-TASK escape-hatch marker.
 *
 * Iter-114 baseline: 8 entries. Maps 1:1 to the marketplace's release-
 * preflight audit task family that was built up across iters 65-110:
 *
 *   - iter-65 audit: wildcard-matcher (Pre/PostToolUse)
 *   - iter-67/68/69 audit: Stop-hook additionalContext silent-drop pentad
 *   - iter-94 audit: no-Bun.spawnSync in PostToolUse orchestrator subhooks
 *   - iter-99 audit: no-raw-stdout-emission in PostToolUse TypeScript hooks
 *   - iter-101 audit: matcher-hygiene (Write|Edit|MultiEdit coverage)
 *   - iter-105 audit: unbounded-emission truncation-helper invariant
 *   - iter-61 audit: pueue-wrap-guard last-entry ordering invariant
 *   - iter-110 audit: marketplace-wide escape-hatch-marker detection invariant
 */
export const MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY: ReadonlyArray<MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry> =
  [
    {
      markerNameTokenIncludingSuffix: "ESCAPE-HATCH-AUDIT-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-marketplace-wide-escape-hatch-marker-detection-inventory-with-recommendation-to-migrate-hand-rolled-patterns-to-iter107-canonical-shared-helper.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-110 STRICT-BLOCK escape-hatch-marker detection invariant for a specific hook source file. This invariant enforces that every consumer hook in the canonical cohort routes its marker detection through the iter-107 shared helper. Use this opt-out ONLY for a documented architectural exception (e.g., a future hook that must use bash-grep detection rather than the helper for performance-critical reasons in a verified hot path). Requires ≥10-character justification after the colon.",
    },
    {
      markerNameTokenIncludingSuffix: "HOOK-OUTPUT-SIZE-CAP-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-pretooluse-and-posttooluse-hook-classifiers-for-unbounded-reason-emission-not-wrapped-in-canonical-truncation-helper-against-claude-file-spillover-threshold-iter105-marketplace-scale-of-iter104-single-hook-fix.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-105 marketplace-wide unbounded-emission truncation-helper invariant for a specific PreToolUse or PostToolUse hook classifier. The invariant enforces that every classifier wraps its decision-reason output through the iter-106 canonical truncation helper to stay below Claude's 10,000-character hook-output file-spillover threshold. Use this opt-out for classifiers whose reason emission is provably bounded by a smaller invariant (e.g., a 500-char fixed-format message). Requires ≥10-character justification.",
    },
    {
      markerNameTokenIncludingSuffix: "MATCHER-NO-MULTIEDIT-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-pretooluse-and-posttooluse-hook-matchers-for-write-or-edit-without-multiedit-coverage-gap-surfaced-by-iter100-postooluse-orchestrator-matcher-broadening-scaled-to-marketplace-invariant.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-101 matcher-hygiene invariant for a specific hook entry. The invariant enforces that any hook matcher containing `Write|Edit` also includes `MultiEdit` (because MultiEdit is a distinct tool name in the Claude Code tool schema — pre-iter-100 hooks that matched `Write|Edit` silently skipped MultiEdit invocations). Use this opt-out for the rare hook that deliberately ignores MultiEdit (e.g., a hook that only operates on single-file Write operations and has no semantic for batch edits). Requires ≥10-character justification.",
    },
    {
      markerNameTokenIncludingSuffix: "ORDERING-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-pretooluse-pueue-wrap-guard-is-last-pretooluse-entry-in-hooks-json-to-mitigate-github-15897-multi-hook-updatedInput-aggregation-last-writer-wins-bug.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-61 pueue-wrap-guard last-entry ordering invariant for a specific hook entry. The invariant enforces that `pretooluse-pueue-wrap-guard.ts` is the LAST PreToolUse Bash-matcher entry in any `hooks.json`, mitigating GitHub anthropics/claude-code#15897 (multi-hook updatedInput aggregation last-writer-wins bug). Use this opt-out only when a downstream PreToolUse hook MUST run after pueue-wrap-guard (rare). Requires ≥10-character justification.",
    },
    {
      markerNameTokenIncludingSuffix: "POSTTOOLUSE-RAW-STDOUT-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-no-raw-stdout-emission-in-posttooluse-typescript-hooks-because-anthropic-schema-routes-non-json-stdout-to-operator-transcript-only-and-silently-drops-it-from-claude-context.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-99 raw-stdout-emission invariant for a specific PostToolUse TypeScript hook. The invariant enforces that PostToolUse hooks emit ONLY decision-JSON to stdout (per the official Anthropic schema, non-JSON stdout from PostToolUse is silently dropped from Claude's context and only reaches operator transcripts). Use this opt-out for hooks that emit raw stdout INTENTIONALLY as transcript-only debug output (e.g., the iter-66 Stop-orchestrator stderr-aggregation path). Requires ≥10-character justification.",
    },
    {
      markerNameTokenIncludingSuffix: "SPAWN-SYNC-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-94 no-Bun.spawnSync invariant for a specific PostToolUse orchestrator subhook. The invariant enforces that classifiers inlined into the iter-93 PostToolUse multi-aggregation orchestrator use `Bun.spawn` (async) rather than `Bun.spawnSync` — the latter halts the JS event loop and defeats `Promise.all` parallelism (per Bun docs + 2026 community guidance). Use this opt-out for subhooks where a verified architectural constraint requires synchronous semantics. Requires ≥10-character justification.",
    },
    {
      markerNameTokenIncludingSuffix: "STOP-HOOK-ADDITIONAL-CONTEXT-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-stop-hooks-for-additionalContext-emission-which-claude-code-silently-drops-per-official-anthropic-schema-only-decision-and-reason-fields-are-read-from-stop-hook-stdout-json.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-67 / iter-68 / iter-69 Stop/SubagentStop/SessionEnd/PreCompact/Notification additionalContext-emission silent-drop pentad invariant for a specific hook source file. The invariant enforces that the five lifecycle-tail event types emit ONLY {decision, reason} per the official Anthropic schema (additionalContext from these events is silently read by NO consumer and dropped from Claude's context). Use this opt-out for hooks that emit additionalContext INTENTIONALLY to make iter-66-style stderr-route output explicit. Requires ≥10-character justification.",
    },
    {
      markerNameTokenIncludingSuffix: "WILDCARD-MATCHER-OK",
      consumerAuditTaskSourceFileRelativePath:
        ".mise/tasks/audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null-which-cold-starts-bun-on-every-tool-call-causing-12-17ms-cpu-or-latency-waste-per-non-meaningful-invocation.sh",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      releaseInvariantSuppressedDescriptionForOperatorDocumentation:
        "Opt out of the iter-65 wildcard-matcher invariant for a specific Pre/PostToolUse hook entry. The invariant enforces that no hook matcher is `*` or null (because wildcard matchers cold-start bun on every tool call, costing ~12-17ms CPU/latency per non-meaningful invocation — measured by the iter-80 bun-startup-floor profiler). Use this opt-out for hooks that legitimately need to fire on every tool call regardless of tool name (rare; usually a more specific matcher exists). Requires ≥10-character justification.",
    },
  ] as const;

/**
 * Convenience accessor: O(N) lookup by marker name (N = 8 — small).
 */
export function lookupAuditTaskCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent(
  markerNameTokenIncludingSuffix: string,
): MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry | undefined {
  return MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY.find(
    (entry) =>
      entry.markerNameTokenIncludingSuffix === markerNameTokenIncludingSuffix,
  );
}

/**
 * Convenience accessor: returns a sorted list of every known audit-task
 * marker token (for audit output, documentation generation, etc.).
 */
export function listAllAuditTaskCanonicalRegistryMarkerNameTokensSortedAlphabetically(): ReadonlyArray<string> {
  return MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY.map(
    (entry) => entry.markerNameTokenIncludingSuffix,
  ).toSorted();
}
