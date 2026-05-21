/**
 * Marketplace-wide canonical registry of every escape-hatch marker token
 * a producer (any plugin's source file) may write to opt out of a specific
 * consumer hook's enforcement.
 *
 * # Why a registry exists (iter-111 rationale)
 *
 * Pre-iter-111, the marketplace had ~12 production escape-hatch markers
 * (`PROCESS-STORM-OK`, `FILE-SIZE-OK`, `BASH-LAUNCHD-OK`, `SSoT-OK`,
 * `INLINE-IGNORE-OK`, `CARGO-TTY-SKIP`/`CARGO-TTY-WRAP`,
 * `LAYER3-STRIPPED-PATH-OK`, `CWD-DELETE-OK`, `INIT-MONOLITH-OK`,
 * `PUEUE-LOCAL-OK`, etc.) scattered across producer files in 7+ plugins
 * (gmail-commander, calcom-commander, autoloop, quality-tools,
 * statusline-tools, itp-hooks, agent-reach) with NO single document
 * answering the new-contributor's question:
 *
 *   "If I write `# FOO-OK` at the top of my file, will any hook
 *    actually recognize it — or will it silently fail to suppress?"
 *
 * The pre-iter-111 failure mode was particularly insidious: a typo like
 * `# PROCSS-STORM-OK` (missing the first `E`) would silently fail —
 * the consumer hook wouldn't see the marker, would block the operation,
 * and the operator would be confused why their "escape hatch" didn't work.
 * There was no static check catching the typo.
 *
 * # What this registry encodes
 *
 * Every PRODUCTION marker (i.e., a marker that a hook source file actually
 * reads via the iter-107 canonical helper) is declared here with:
 *
 *   - `markerNameTokenIncludingSuffix`: exact spelling (UPPER-KEBAB-CASE
 *     by convention, except `SSoT-OK` which is grandfathered mixed-case)
 *   - `consumerHookSourceFileRelativePath`: which hook recognizes it
 *   - `caseSensitivityModeDeclaredAtConsumerCallSite`: CASE_SENSITIVE or
 *     CASE_INSENSITIVE — must match the configuration object passed to
 *     `hasFileWideEscapeHatchMarkerInContent` / `detectEscapeHatchMarkerCoveringTargetSourceLine`
 *     in the consumer hook
 *   - `windowSemanticsModeDeclaredAtConsumerCallSite`: SAME_LINE_ONLY |
 *     SAME_LINE_OR_PRECEDING_N_LINES | FILE_WIDE
 *   - `minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional`:
 *     0 if bare marker accepted, else the minimum char count enforced
 *     (e.g., LAYER3-STRIPPED-PATH-OK requires ≥10-char reason)
 *   - `humanReadableEscapeHatchDescriptionForOperatorDocumentation`:
 *     plain-English explanation an operator can read
 *
 * # What this registry intentionally does NOT cover
 *
 * - **Audit markers** (e.g., `WILDCARD-MATCHER-OK`,
 *   `STOP-HOOK-ADDITIONAL-CONTEXT-OK`, `HOOK-OUTPUT-SIZE-CAP-OK`,
 *   `MATCHER-NO-MULTIEDIT-OK`, `POSTTOOLUSE-RAW-STDOUT-OK`,
 *   `SPAWN-SYNC-OK`, `TRUNCATION-OK`, `ORDERING-OK`,
 *   `ESCAPE-HATCH-AUDIT-OK`, `FAST-PATH-OK`): these are read by `.mise/`
 *   audit tasks (not hooks) via bash/grep — they're a different lifecycle
 *   layer. Iter-112+ may extend this registry to cover them.
 * - **Test-fixture markers** (e.g., `FOO-OK`, `BAR-OK`, `BAZ-OK`,
 *   `QUX-OK`, `FOO-TTY-SKIP`, `FOO-TTY-WRAP`): synthetic strings used
 *   only by the iter-107/iter-108/iter-110 probe scripts. The iter-111
 *   typo audit ignores test files entirely.
 *
 * # How the iter-111 typo audit uses this
 *
 * The audit task
 * `.mise/tasks/audit-marketplace-wide-producer-escape-hatch-marker-typo-detection-against-canonical-iter111-registry.sh`
 * greps the marketplace for `[A-Z][A-Z0-9-]+-(OK|SKIP|WRAP)` tokens in
 * **producer files** (anything not in `plugins/itp-hooks/hooks/` and not
 * in `.mise/`) and verifies each appears in this registry. Unknown tokens
 * are reported as potential typos — the operator can either fix the typo
 * or register a new legitimate marker here.
 *
 * # When adding a new escape-hatch marker
 *
 * 1. Add the consumer-side detection call in the hook source file using
 *    `hasFileWideEscapeHatchMarkerInContent(...)` or
 *    `detectEscapeHatchMarkerCoveringTargetSourceLine(...)` from
 *    `./shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts`.
 * 2. Add an entry to `MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY`
 *    below with all fields populated.
 * 3. Add the consumer hook to the iter-110 canonical-cohort array in
 *    `.mise/tasks/audit-marketplace-wide-escape-hatch-marker-detection-inventory-...`.
 * 4. Document the marker in `docs/HOOKS.md` under the relevant hook's section.
 *
 * # When removing a marker (deprecation)
 *
 * 1. Remove the consumer-side detection call.
 * 2. Remove the entry here.
 * 3. Remove from the iter-110 canonical-cohort array.
 * 4. Sweep the marketplace for stale producer comments that reference the
 *    removed marker (the iter-111 audit catches this automatically).
 */

import type {
  EscapeHatchMarkerCaseSensitivityMode,
  EscapeHatchMarkerWindowSemanticsMode,
} from "./shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

export interface MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry {
  /**
   * Exact marker spelling INCLUDING the suffix (`-OK`, `-SKIP`, or `-WRAP`).
   * Must match the `markerNameTokenIncludingSuffix` passed to the helper
   * at the consumer call site.
   */
  readonly markerNameTokenIncludingSuffix: string;

  /**
   * Repo-root-relative path to the hook source file that READS this marker
   * via the iter-107 canonical helper. The iter-111 audit can use this to
   * verify the consumer actually imports the helper.
   */
  readonly consumerHookSourceFileRelativePath: string;

  /**
   * Must match the `caseSensitivityMode` field on the configuration object
   * passed to the helper at the consumer call site. Operators relying on
   * lowercase markers (e.g., legacy `# process-storm-ok`) need this set to
   * `"CASE_INSENSITIVE"`; UPPER-KEBAB-CASE convention markers should be
   * `"CASE_SENSITIVE"` (the helper's default).
   */
  readonly caseSensitivityModeDeclaredAtConsumerCallSite: EscapeHatchMarkerCaseSensitivityMode;

  /**
   * Must match the `windowSemanticsMode` field on the configuration object
   * passed to the helper at the consumer call site.
   */
  readonly windowSemanticsModeDeclaredAtConsumerCallSite: EscapeHatchMarkerWindowSemanticsMode;

  /**
   * For markers that require a justification reason after a colon
   * (e.g., `LAYER3-STRIPPED-PATH-OK: deliberate cache bypass for X reason`),
   * the minimum number of characters required after the colon. 0 means
   * bare marker is accepted (no reason needed).
   */
  readonly minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: number;

  /**
   * Plain-English description an operator can read to understand what
   * the marker opts them out of. Used by the iter-111 audit's helpful-
   * error output and by future operator documentation generators.
   */
  readonly humanReadableEscapeHatchDescriptionForOperatorDocumentation: string;
}

/**
 * Canonical registry — single source of truth for every marketplace
 * production escape-hatch marker.
 *
 * Iter-111 baseline: 11 entries (the consumer cohort from iter-110 plus
 * the cargo-tty-guard's two-marker opt-in/opt-out pair). Any new marker
 * MUST be registered here before its consumer hook can pass the iter-111
 * audit.
 */
export const MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY: ReadonlyArray<MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry> =
  [
    {
      markerNameTokenIncludingSuffix: "BASH-LAUNCHD-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-native-binary-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow a bash-shebang script OR a plist `/bin/bash` ProgramArguments reference in a macOS launchd file (~/.claude/automation/, ~/Library/LaunchAgents/, ~/Library/LaunchDaemons/) — the hook normally requires a compiled native binary so System Settings > Login Items shows the executable's actual name instead of generic 'bash'. Accepted in plist files as `<!-- BASH-LAUNCHD-OK -->`.",
    },
    {
      markerNameTokenIncludingSuffix: "CARGO-TTY-SKIP",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Opt OUT of cargo-tty-guard's automatic PUEUE-wrapping of `cargo bench/test/build` commands. Use when the operator has confirmed there is no TTY-suspension risk (e.g., cargo invocation already redirects stdin) — the guard will pass the command through unchanged instead of redirecting to PUEUE.",
    },
    {
      markerNameTokenIncludingSuffix: "CARGO-TTY-WRAP",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Opt IN to cargo-tty-guard's PUEUE-wrapping even when the heuristic doesn't trigger automatically. Used when the operator knows their cargo invocation will inherit a contested TTY and wants the daemon path explicitly.",
    },
    {
      markerNameTokenIncludingSuffix: "CWD-DELETE-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/cwd-deletion-patterns.mjs",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow a bash command that the cwd-deletion-guard would otherwise block as a CWD-deleting `rm -rf` (or equivalent). Used when the operator has verified the rm target is safe (e.g., target is a sibling, not the CWD itself, and the regex false-positives).",
    },
    {
      markerNameTokenIncludingSuffix: "FILE-SIZE-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow a file to exceed file-size-guard's per-extension warn/block thresholds. Default marker token; can be overridden per-project via `.claude/file-size-guard.json` `escapeComment` field — but the helper always runs in CASE_SENSITIVE mode (substring match on the literal token, regardless of marker spelling).",
    },
    {
      markerNameTokenIncludingSuffix: "INIT-MONOLITH-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-pyi-stub-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow top-level `class`/`def`/decorator definitions in a Python `__init__.py` or `__init__.pyi` file. The hook normally enforces PEP 561 + clean-package-structure (init files MUST be thin re-export layers); this opt-out covers legitimate cases like temporary scaffolding or libraries that genuinely require the monolith shape.",
    },
    {
      markerNameTokenIncludingSuffix: "INLINE-IGNORE-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-inline-ignore-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "SAME_LINE_ONLY",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        // Description intentionally paraphrases the four suppression
        // directive families WITHOUT spelling out their literal comment
        // syntax. Spelling them out would trip two separate hooks at the
        // same time: (1) biome-lint parses any literal "biome" + "ignore"
        // adjacency as a suppression-directive attempt and errors when the
        // category name doesn't validate, and (2) code-correctness-guard.sh
        // grep-scans for the literal directive substrings as a separate
        // audit pass with no awareness of the iter-107 SAME_LINE_ONLY
        // helper semantics. Operators consulting this description should
        // refer to the consumer hook's own docstring for exact syntax.
        "Allow a single inline lint-suppression comment (covering the four families: Python ruff suppressions, Python ty type-checker suppressions, ESLint per-line and per-block suppressions, and the Bun-ecosystem fast-linter suppressions) on the SAME LINE as this marker. Used when a tool/library limitation genuinely requires the suppression — config-file-level suppression in ruff/ty/oxlint/biome configuration files is still strongly preferred when possible.",
    },
    {
      markerNameTokenIncludingSuffix: "LAYER3-STRIPPED-PATH-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite:
        "SAME_LINE_OR_PRECEDING_N_LINES",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 10,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        // Backslash-escaped `\${...}` inside a template string prevents biome's
        // noTemplateCurlyInString lint from misreading the bash-style env-var
        // reference as an unintended interpolation placeholder.
        `Allow a \`\${CLAUDE_PLUGIN_ROOT}/<segment>/\` reference where \`<segment>\` is NOT in the iter-76 cache-populator allowlist (hooks, skills, commands, agents, plugin.json). REQUIRES a ≥10-character reason after the colon (e.g., \`LAYER3-STRIPPED-PATH-OK: deliberate scratch-dir reference for migration spike\`). Marker is honored on the same line OR within the preceding 3 lines.`,
    },
    {
      markerNameTokenIncludingSuffix: "PROCESS-STORM-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/process-storm-patterns.mjs",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow a bash command or file content that the process-storm-guard would otherwise block (fork-bomb pattern, gh-recursion subshell, mise-activate-in-zshenv, subprocess-in-while-true, etc.). Used pervasively in daemon entry points (gmail-commander bots, calcom-commander bots, autoloop heartbeat) where the pattern is intentional.",
    },
    {
      markerNameTokenIncludingSuffix: "PUEUE-LOCAL-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-pueue-local-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_INSENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow a `pueue` command that targets a remote daemon (the guard normally enforces local-only targeting to prevent accidentally queueing work on the wrong host). NOTE: pueue-local-guard is NOT YET migrated to the iter-107 helper (iter-112+ candidate); this registry entry is forward-looking and the audit treats this marker as known even before the migration lands.",
    },
    {
      markerNameTokenIncludingSuffix: "SETPROCTITLE-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/posttooluse-reminder.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Suppress the setproctitle-reminder PostToolUse hint, which fires when a Python service or daemon file is edited but does not import `setproctitle`. Used when the file is genuinely NOT a long-running service (e.g., a short-lived CLI invocation or a one-shot script that happens to share filename patterns with daemon code). NOTE: as of iter-111 this marker is detected by `posttooluse-reminder.ts` via a raw `.includes()` substring check, NOT yet via the iter-107 canonical helper. Iter-112+ candidate: migrate the consumer call site to `hasFileWideEscapeHatchMarkerInContent(...)` for behavioral consistency with the other 11 registry entries.",
    },
    {
      markerNameTokenIncludingSuffix: "SSoT-OK",
      consumerHookSourceFileRelativePath:
        "plugins/itp-hooks/hooks/pretooluse-version-guard.ts",
      caseSensitivityModeDeclaredAtConsumerCallSite: "CASE_SENSITIVE",
      windowSemanticsModeDeclaredAtConsumerCallSite: "FILE_WIDE",
      minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional: 0,
      humanReadableEscapeHatchDescriptionForOperatorDocumentation:
        "Allow a hardcoded version string (e.g., `v1.2.3`) in a markdown file that the version-guard would otherwise block as a single-source-of-truth violation. Mixed-case spelling `SSoT-OK` is grandfathered (NOT renamed to `SSOT-OK`) because operators have been using this exact spelling since the version-guard was first authored.",
    },
  ] as const;

/**
 * Convenience accessor: O(N) lookup by marker name (N is small — currently
 * 11 entries — so a Map isn't worth the construction cost).
 */
export function lookupCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent(
  markerNameTokenIncludingSuffix: string,
): MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry | undefined {
  return MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY.find(
    (entry) =>
      entry.markerNameTokenIncludingSuffix === markerNameTokenIncludingSuffix,
  );
}

/**
 * Convenience accessor: returns a sorted list of every known marker token
 * (for audit output, documentation generation, etc.).
 */
export function listAllCanonicalRegistryMarkerNameTokensSortedAlphabetically(): ReadonlyArray<string> {
  return MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY.map(
    (entry) => entry.markerNameTokenIncludingSuffix,
  ).toSorted();
}
