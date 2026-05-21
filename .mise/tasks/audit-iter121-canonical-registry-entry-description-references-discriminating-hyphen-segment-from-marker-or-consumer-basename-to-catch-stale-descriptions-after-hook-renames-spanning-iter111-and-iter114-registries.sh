#!/usr/bin/env bash
#MISE description="Iter-121 marketplace-wide STALE-DESCRIPTION audit: catches the operator-doc-drift class where a hook or audit-task is renamed (consumer-path field updated) but the human-readable operator-facing description still references the OLD name. Algorithm: for each entry in the iter-111 RUNTIME-HOOK registry AND the iter-114 AUDIT-TASK registry, extract the discriminating hyphen-segments from (a) the marker name token and (b) the consumer source-file basename, drop a stoplist of non-discriminating segments (pretooluse, posttooluse, audit, guard, ok, skip, wrap, iter<NNN>, file extensions, etc.), and verify the description contains AT LEAST ONE discriminating segment as a case-insensitive substring. An entry whose description references NEITHER the marker NOR the consumer basename in ANY surface form is reported as a stale-description candidate. Informational on iter-121; will be promoted to STRICT-BLOCK in iter-122+ once baseline-clean state is verified."

# ────────────────────────────────────────────────────────────────────────
# Iter-121 design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Pre-iter-121 failure mode (the bug class this audit was built to catch):
#
#   1. Operator renames a hook
#      pretooluse-file-size-guard.ts → pretooluse-file-size-and-line-count-guard.ts
#   2. Operator updates `consumerHookSourceFileRelativePath` in the
#      iter-111 registry entry for `FILE-SIZE-OK`.
#   3. Operator forgets to update
#      `humanReadableEscapeHatchDescriptionForOperatorDocumentation`
#      which still says "Allow a file to exceed file-size-guard's per-
#      extension warn/block thresholds..." (references the OLD name).
#   4. The iter-113 doc generator regenerates docs/escape-hatch-marker-
#      reference.md with the new consumer-path heading but the OLD
#      description body. Operators consulting the doc see a contradiction.
#
# No pre-iter-121 audit caught this — the iter-111 producer-typo audit only
# verifies marker spelling; the iter-115 doc-drift detector only verifies
# byte-identical regeneration. Neither cross-checks description ↔
# consumer-path consistency.
#
# # Algorithm — discriminating-hyphen-segment mention invariant
#
# For each entry (across BOTH the iter-111 and iter-114 registries):
#
#   1. Extract MARKER discriminating segments:
#      Split markerNameTokenIncludingSuffix by '-', drop suffix tokens
#      {OK, SKIP, WRAP}, lowercase. Example:
#        BASH-LAUNCHD-OK → ["bash", "launchd"]
#        SPAWN-SYNC-OK → ["spawn", "sync"]
#        LAYER3-STRIPPED-PATH-OK → ["layer3", "stripped", "path"]
#
#   2. Extract BASENAME discriminating segments:
#      basename(consumerPath) → strip extension (.ts/.sh/.mjs/.js/.tsx) →
#      split by '-' → drop stoplist {pretooluse, posttooluse, audit, guard,
#      patterns, lib, hooks, marketplace, wide, canonical, registry, iter<NNN>}
#      → lowercase. Example:
#        pretooluse-file-size-guard.ts → ["file", "size"]
#        audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks.sh
#          → ["no", "bun", "spawnsync", "in", "orchestrator", "subhooks"]
#
#   3. Build candidate-substrings set:
#      For each segment in (marker_segments ∪ basename_segments), add the
#      segment itself as a candidate. ALSO add the joined adjacent-pair
#      forms ("file-size", "spawn-sync", "bash-launchd") so the audit
#      passes when the description references the canonical kebab-case
#      pair instead of individual words.
#
#   4. Verify: description.toLowerCase() contains AT LEAST ONE candidate
#      as a substring. If NONE: report as stale-description hit.
#
# # Why "at least one segment" (not "all segments")?
#
# Descriptions are written for OPERATORS — they paraphrase, they explain
# context, they reference adjacent concepts. Requiring ALL segments would
# false-positive on legitimate descriptions that use synonyms or focus on
# the policy domain. Requiring EVEN ONE segment catches the unmoored case
# (description references neither the marker name nor the consumer path
# basename in any form) while allowing descriptive freedom.
#
# # Why drop the {OK, SKIP, WRAP} suffix tokens?
#
# Every registry entry's marker has one of these suffixes — so the suffix
# itself is non-discriminating. A description that contains just "OK" or
# "skip" or "wrap" doesn't prove the description is grounded in THIS
# specific entry.
#
# # Why the basename stoplist?
#
# Words like "pretooluse", "posttooluse", "audit", "guard", "patterns",
# "marketplace" appear in EVERY basename and don't discriminate between
# entries. The `iter<NNN>` suffix changes when an audit is re-iterated
# (e.g., iter-111 → iter-115 promoted-strict — same audit, new iteration
# tag) and shouldn't be required in operator descriptions.
#
# # Parallel to:
#
#   - iter-111 audit: producer-side marker typo detection vs registry
#   - iter-113 audit: registry-to-docs byte-identical drift detector
#   - iter-115: promoted iter-111 + iter-113 audits to STRICT-BLOCK
#   - iter-121 (THIS): description-text-content vs registry-entry-identity invariant

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

ITER121_AUDIT_SCRIPT_DIRECTORY_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER121_AUDIT_REPO_ROOT_ABSOLUTE="$(cd "$ITER121_AUDIT_SCRIPT_DIRECTORY_ABSOLUTE/../.." && pwd)"
ITER111_RUNTIME_HOOK_REGISTRY_TYPESCRIPT_RELATIVE_PATH="plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts"
ITER114_AUDIT_TASK_REGISTRY_TYPESCRIPT_RELATIVE_PATH="plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "  Iter-121 marketplace-wide canonical-registry stale-description audit"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Theory: when a hook/audit-task is renamed, operators commonly update"
echo "          the registry's consumer-path field but FORGET to update the"
echo "          human-readable description. This leaves the operator-facing"
echo "          doc with a stale name. Pre-iter-121, no audit caught this."
echo ""
echo "  This audit: for every entry in the iter-111 + iter-114 registries,"
echo "              verifies the description contains AT LEAST ONE discriminating"
echo "              hyphen-segment from the marker name OR consumer basename."
echo ""

# ════════════════════════════════════════════════════════════════════════════
#  Step 1 — Verify both canonical registries exist
# ════════════════════════════════════════════════════════════════════════════

if [[ ! -f "$ITER121_AUDIT_REPO_ROOT_ABSOLUTE/$ITER111_RUNTIME_HOOK_REGISTRY_TYPESCRIPT_RELATIVE_PATH" ]]; then
    echo "  ✗ AUDIT FAILED — iter-111 runtime-hook registry not found:"
    echo "      $ITER111_RUNTIME_HOOK_REGISTRY_TYPESCRIPT_RELATIVE_PATH"
    exit 1
fi
if [[ ! -f "$ITER121_AUDIT_REPO_ROOT_ABSOLUTE/$ITER114_AUDIT_TASK_REGISTRY_TYPESCRIPT_RELATIVE_PATH" ]]; then
    echo "  ✗ AUDIT FAILED — iter-114 audit-task registry not found:"
    echo "      $ITER114_AUDIT_TASK_REGISTRY_TYPESCRIPT_RELATIVE_PATH"
    exit 1
fi
echo "  ✓ Step 1: both canonical registries exist"

# ════════════════════════════════════════════════════════════════════════════
#  Step 2 — Run the iter-121 discriminating-segment-mention checker via bun
# ════════════════════════════════════════════════════════════════════════════
#
# The checker runs as an inline TypeScript program executed via bun so it can
# import both canonical registries directly (typed access) rather than parsing
# the .ts source files with brittle bash regex.

ITER121_CHECKER_TEMPORARY_SCRIPT_DIRECTORY=$(mktemp -d -t iter121-stale-desc-audit-XXXXXX)
trap 'rm -rf "$ITER121_CHECKER_TEMPORARY_SCRIPT_DIRECTORY"' EXIT

cat > "$ITER121_CHECKER_TEMPORARY_SCRIPT_DIRECTORY/iter121-stale-description-checker.ts" <<EOF
/**
 * Iter-121 stale-description checker. Loads both canonical registries
 * (iter-111 runtime-hook + iter-114 audit-task), uses the iter-121
 * shared library to extract discriminating hyphen-segments from each
 * entry, and verifies the description mentions at least one. Reports
 * findings as plain stdout for the parent shell.
 *
 * The extraction algorithm lives in a dedicated typed library so the
 * regression test can exercise it independently against synthetic
 * fixtures (instead of needing to monkey-patch the canonical registry).
 */
import {
  MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY,
} from "$ITER121_AUDIT_REPO_ROOT_ABSOLUTE/$ITER111_RUNTIME_HOOK_REGISTRY_TYPESCRIPT_RELATIVE_PATH";
import {
  MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY,
} from "$ITER121_AUDIT_REPO_ROOT_ABSOLUTE/$ITER114_AUDIT_TASK_REGISTRY_TYPESCRIPT_RELATIVE_PATH";
import {
  findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename,
  extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix,
  extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename,
} from "$ITER121_AUDIT_REPO_ROOT_ABSOLUTE/plugins/itp-hooks/hooks/lib/iter121-stale-description-audit-algorithm-discriminating-hyphen-segment-extraction-from-marker-or-consumer-source-file-basename.ts";

interface StaleDescriptionCandidateHit {
  readonly originatingRegistryLifecycleLayerTag:
    | "RUNTIME_HOOK_ITER111"
    | "AUDIT_TASK_ITER114";
  readonly markerNameTokenIncludingSuffix: string;
  readonly consumerSourceFileRelativePath: string;
  readonly humanReadableDescriptionExcerpt: string;
  readonly markerDiscriminatingSegments: ReadonlyArray<string>;
  readonly basenameDiscriminatingSegments: ReadonlyArray<string>;
}

const allStaleDescriptionCandidateHits: StaleDescriptionCandidateHit[] = [];
let totalEntriesAuditedAcrossBothRegistries = 0;

// ─── Runtime-hook registry pass ────────────────────────────────────────────
for (const runtimeHookEntry of MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY) {
  totalEntriesAuditedAcrossBothRegistries += 1;
  const matchedCandidateOrNull =
    findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename(
      runtimeHookEntry.markerNameTokenIncludingSuffix,
      runtimeHookEntry.consumerHookSourceFileRelativePath,
      runtimeHookEntry.humanReadableEscapeHatchDescriptionForOperatorDocumentation,
    );
  if (matchedCandidateOrNull === null) {
    allStaleDescriptionCandidateHits.push({
      originatingRegistryLifecycleLayerTag: "RUNTIME_HOOK_ITER111",
      markerNameTokenIncludingSuffix:
        runtimeHookEntry.markerNameTokenIncludingSuffix,
      consumerSourceFileRelativePath:
        runtimeHookEntry.consumerHookSourceFileRelativePath,
      humanReadableDescriptionExcerpt:
        runtimeHookEntry.humanReadableEscapeHatchDescriptionForOperatorDocumentation.slice(
          0,
          120,
        ),
      markerDiscriminatingSegments:
        extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix(
          runtimeHookEntry.markerNameTokenIncludingSuffix,
        ),
      basenameDiscriminatingSegments:
        extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename(
          runtimeHookEntry.consumerHookSourceFileRelativePath,
        ),
    });
  }
}

// ─── Audit-task registry pass ──────────────────────────────────────────────
for (const auditTaskEntry of MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY) {
  totalEntriesAuditedAcrossBothRegistries += 1;
  const matchedCandidateOrNull =
    findFirstDiscriminatingCandidateSubstringMatchedInDescriptionOrNullWhenDescriptionIsUnmooredFromBothMarkerAndConsumerBasename(
      auditTaskEntry.markerNameTokenIncludingSuffix,
      auditTaskEntry.consumerAuditTaskSourceFileRelativePath,
      auditTaskEntry.releaseInvariantSuppressedDescriptionForOperatorDocumentation,
    );
  if (matchedCandidateOrNull === null) {
    allStaleDescriptionCandidateHits.push({
      originatingRegistryLifecycleLayerTag: "AUDIT_TASK_ITER114",
      markerNameTokenIncludingSuffix:
        auditTaskEntry.markerNameTokenIncludingSuffix,
      consumerSourceFileRelativePath:
        auditTaskEntry.consumerAuditTaskSourceFileRelativePath,
      humanReadableDescriptionExcerpt:
        auditTaskEntry.releaseInvariantSuppressedDescriptionForOperatorDocumentation.slice(
          0,
          120,
        ),
      markerDiscriminatingSegments:
        extractDiscriminatingHyphenSegmentsFromMarkerNameTokenIncludingSuffix(
          auditTaskEntry.markerNameTokenIncludingSuffix,
        ),
      basenameDiscriminatingSegments:
        extractDiscriminatingHyphenSegmentsFromConsumerSourceFileRelativePathBasename(
          auditTaskEntry.consumerAuditTaskSourceFileRelativePath,
        ),
    });
  }
}

// ─── Emit machine-parseable summary ────────────────────────────────────────
console.log(
  \`ITER121_AUDIT_TOTAL_ENTRIES_AUDITED_ACROSS_BOTH_REGISTRIES=\${totalEntriesAuditedAcrossBothRegistries}\`,
);
console.log(
  \`ITER121_AUDIT_STALE_DESCRIPTION_HIT_COUNT=\${allStaleDescriptionCandidateHits.length}\`,
);
for (const hit of allStaleDescriptionCandidateHits) {
  console.log(\`---ITER121_AUDIT_STALE_DESCRIPTION_HIT---\`);
  console.log(\`registryLayer: \${hit.originatingRegistryLifecycleLayerTag}\`);
  console.log(\`markerName: \${hit.markerNameTokenIncludingSuffix}\`);
  console.log(\`consumerPath: \${hit.consumerSourceFileRelativePath}\`);
  console.log(\`descExcerpt: \${hit.humanReadableDescriptionExcerpt}\`);
  console.log(\`markerSegs: \${JSON.stringify(hit.markerDiscriminatingSegments)}\`);
  console.log(\`basenameSegs: \${JSON.stringify(hit.basenameDiscriminatingSegments)}\`);
}

process.exit(allStaleDescriptionCandidateHits.length > 0 ? 1 : 0);
EOF

set +e
ITER121_CHECKER_OUTPUT=$(cd "$ITER121_AUDIT_REPO_ROOT_ABSOLUTE" && bun "$ITER121_CHECKER_TEMPORARY_SCRIPT_DIRECTORY/iter121-stale-description-checker.ts" 2>&1)
ITER121_CHECKER_EXIT_CODE=$?
set -e

# Sanity-guard: the checker is expected to exit 0 (clean) or 1 (≥1 stale-
# description hit reported via stdout). Any other exit code (2 = bun parse
# error, 137 = OOM, 130 = SIGINT, etc.) indicates the checker itself
# failed before it could enumerate registry entries — surface this as a
# distinct AUDIT INFRASTRUCTURE FAILURE rather than silently treating
# zero parsed hits as a clean run.
if [[ "$ITER121_CHECKER_EXIT_CODE" -ne 0 ]] && [[ "$ITER121_CHECKER_EXIT_CODE" -ne 1 ]]; then
    echo "  ✗ AUDIT INFRASTRUCTURE FAILURE — iter-121 checker exited with unexpected code $ITER121_CHECKER_EXIT_CODE"
    echo "    Checker output:"
    echo "$ITER121_CHECKER_OUTPUT" | awk '{print "      " $0}'
    exit 1
fi

# Parsing note: the variable names themselves contain "121" (e.g.,
# `ITER121_AUDIT_TOTAL_ENTRIES_AUDITED_...=20`), so the previous
# `grep -oE '[0-9]+'` pipeline matched the literal "121" inside the
# variable name before reaching the value after the `=`. Anchor on `=`
# via awk -F= to extract the actual count.
ITER121_TOTAL_ENTRIES_AUDITED=$(echo "$ITER121_CHECKER_OUTPUT" | awk -F= '/^ITER121_AUDIT_TOTAL_ENTRIES_AUDITED_ACROSS_BOTH_REGISTRIES=/ {print $2; exit}')
ITER121_STALE_DESCRIPTION_HIT_COUNT=$(echo "$ITER121_CHECKER_OUTPUT" | awk -F= '/^ITER121_AUDIT_STALE_DESCRIPTION_HIT_COUNT=/ {print $2; exit}')
ITER121_TOTAL_ENTRIES_AUDITED="${ITER121_TOTAL_ENTRIES_AUDITED:-0}"
ITER121_STALE_DESCRIPTION_HIT_COUNT="${ITER121_STALE_DESCRIPTION_HIT_COUNT:-0}"

echo "  ✓ Step 2: audited $ITER121_TOTAL_ENTRIES_AUDITED entries across both canonical registries (iter-111 runtime-hook + iter-114 audit-task; checker exit code $ITER121_CHECKER_EXIT_CODE = expected 0|1)"

# ════════════════════════════════════════════════════════════════════════════
#  Step 3 — Report
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ┌─ Iter-121 stale-description audit findings:"
if [[ "$ITER121_STALE_DESCRIPTION_HIT_COUNT" -eq 0 ]]; then
    echo "  │   (none — every description references ≥1 discriminating segment"
    echo "  │    from its marker name OR consumer basename)"
    echo "  └─"
    echo ""
    echo "  ✓ AUDIT PASSED — every registry entry's description is grounded in its marker or consumer-path identity"
    exit 0
fi

echo "  │   Found $ITER121_STALE_DESCRIPTION_HIT_COUNT entry/entries whose description references NEITHER"
echo "  │   the marker name NOR the consumer basename in any discriminating form:"
echo "  │"

# Parse the checker output to print each hit. Use awk to find blocks.
echo "$ITER121_CHECKER_OUTPUT" | awk '
    /^---ITER121_AUDIT_STALE_DESCRIPTION_HIT---$/ { in_hit=1; print "  │"; next }
    in_hit && /^registryLayer: / { print "  │   ⚠ " $0; next }
    in_hit && /^markerName: / { print "  │     " $0; next }
    in_hit && /^consumerPath: / { print "  │     " $0; next }
    in_hit && /^descExcerpt: / { print "  │     " $0 " ..."; next }
    in_hit && /^markerSegs: / { print "  │     " $0; next }
    in_hit && /^basenameSegs: / { print "  │     " $0; next }
'
echo "  └─"
echo ""

# ════════════════════════════════════════════════════════════════════════════
#  Step 4 — Exit policy
# ════════════════════════════════════════════════════════════════════════════
#
# Iter-121: INFORMATIONAL (does not block release). Reports findings so the
# operator can fix them before iter-122 promotes the audit to STRICT-BLOCK.
# The audit currently passes 20/20 entries (12 iter-111 runtime + 8 iter-114
# audit) on the baseline registry — any new entry that fails the
# discriminating-segment-mention invariant will be flagged here for
# remediation before strict promotion.

echo "  ⚠ ITER-121 INFORMATIONAL FINDING: $ITER121_STALE_DESCRIPTION_HIT_COUNT entry/entries have descriptions unmoored"
echo "    from both their marker name AND consumer basename. Resolution paths:"
echo ""
echo "    A. Description references the OLD hook/task name (most common):"
echo "       update the description to reference the current consumer-path basename."
echo "    B. Description is intentionally policy-domain-focused (no name reference):"
echo "       add at least one explicit mention of the marker name OR consumer basename"
echo "       (e.g., a 'see also pretooluse-FOO-guard.ts' parenthetical) so future"
echo "       renames have a textual anchor that the iter-121 audit can verify."
echo "    C. The audit's stoplist over-aggressively dropped a discriminating segment:"
echo "       file an issue to refine the stoplist in"
echo "       .mise/tasks/audit-iter121-canonical-registry-entry-description-..."
echo ""
echo "  ⓘ This audit is INFORMATIONAL on iter-121 and never blocks release. Will be"
echo "    promoted to STRICT-BLOCK in iter-122+ once baseline coverage is verified."

# Always exit 0 on iter-121 — the audit is informational. Iter-122 will
# remove this `exit 0` and let the checker's exit-1-on-violation propagate.
exit 0
