#!/usr/bin/env bash
#MISE description="Iter-113 generator: emits docs/marketplace-escape-hatch-marker-reference.md from the iter-111 canonical producer-marker registry. Single source of truth for 'how do I opt out of hook X' operator-facing documentation. The generator is idempotent — re-running on an unchanged registry produces a byte-identical doc. CI-friendly drift detection: run with --check to verify the on-disk doc matches what the generator would produce (exits non-zero on drift)."

# ────────────────────────────────────────────────────────────────────────
# Iter-113 full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Iter-111 introduced the canonical producer-marker registry (a TypeScript
# module declaring every legitimate escape-hatch marker token, its consumer
# hook, case-sensitivity mode, window-semantics mode, reason policy, and
# operator-readable description). The registry is the SSoT — but pre-iter-113
# there was no operator-facing rendering of it. Operators had to read the
# TypeScript source to learn what marker corresponds to what suppression.
#
# Iter-113 closes the operator-discoverability gap:
#
#   1. THIS generator script imports the registry via bun, walks the entries
#      sorted alphabetically by marker token, and emits a markdown doc with
#      one section per marker (token + frontmatter table + description +
#      example usage).
#
#   2. The on-disk artifact lives at docs/marketplace-escape-hatch-marker-
#      reference.md and is committed to git so it's discoverable via repo
#      browsing without requiring a build step.
#
#   3. The companion test
#      .mise/tasks/tests/test-iter113-marketplace-escape-hatch-marker-
#      reference-doc-is-in-sync-with-iter111-canonical-registry.sh runs the
#      generator and diffs the output against the on-disk doc. Drift is a
#      release blocker (informational in iter-113, strict-promoted in
#      iter-114+ alongside the AUDIT-marker family registry expansion).
#
# Operator workflow (post-iter-113):
#
#   Q: "I want to suppress the file-size-guard for this one file —
#       what marker do I write?"
#   A: Open docs/marketplace-escape-hatch-marker-reference.md, find the
#      `FILE-SIZE-OK` section, read the description + example usage.
#
#   Q: "I think a typo in my escape-hatch comment is being silently
#       ignored — what's the canonical spelling?"
#   A: Same doc. Every marker is listed with its exact canonical spelling
#      (including the SSoT-OK mixed-case grandfathered marker).
#
# Idempotency invariant: re-running the generator on an unchanged registry
# produces a byte-identical doc. This is what makes the iter-113 drift-
# detection test meaningful (a non-empty diff means someone edited the
# registry without regenerating the doc, OR edited the doc directly
# without updating the registry — either way, the SSoT is broken).
#
# Mode flags:
#   --check     : run generator + compare against on-disk doc, exit non-zero
#                 on drift. CI / preflight use case.
#   --write     : run generator + overwrite on-disk doc (default).
#   --stdout    : run generator + write to stdout (no on-disk side effects;
#                 useful for inspection / piping).

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Generator lives at .mise/tasks/<this-script>.sh; repo root is two levels up.
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER111_CANONICAL_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts"
OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH="$REPO_ROOT/docs/marketplace-escape-hatch-marker-reference.md"

INVOCATION_MODE="${1:-write}"
case "$INVOCATION_MODE" in
    --check) INVOCATION_MODE="check" ;;
    --write) INVOCATION_MODE="write" ;;
    --stdout) INVOCATION_MODE="stdout" ;;
    write|check|stdout) ;; # already normalized
    *)
        echo "Usage: $(basename "$0") [--check | --write | --stdout]"
        echo ""
        echo "  --check   Verify on-disk doc matches generator output (exits non-zero on drift)"
        echo "  --write   Regenerate on-disk doc (default)"
        echo "  --stdout  Write to stdout (no on-disk side effects)"
        exit 1
        ;;
esac

if [[ ! -f "$ITER111_CANONICAL_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" ]]; then
    echo "✗ iter-111 canonical registry not found:"
    echo "    $ITER111_CANONICAL_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH"
    exit 1
fi

# ════════════════════════════════════════════════════════════════════════
# The renderer is a small TypeScript program executed via bun. Writing it
# inline (heredoc) keeps the generator self-contained — no third file to
# maintain in sync with the registry.
# ════════════════════════════════════════════════════════════════════════

RENDERER_TEMP_SCRIPT_DIRECTORY=$(mktemp -d -t iter113-renderer-XXXXXX)
trap 'rm -rf "$RENDERER_TEMP_SCRIPT_DIRECTORY"' EXIT

cat > "$RENDERER_TEMP_SCRIPT_DIRECTORY/render-from-iter111-registry.ts" <<EOF
import {
  MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY,
  listAllCanonicalRegistryMarkerNameTokensSortedAlphabetically,
} from "$ITER111_CANONICAL_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH";

function emitMarkdownTableHeaderRowAndSeparatorRow(): string {
  return [
    "| Field | Value |",
    "| ----- | ----- |",
  ].join("\\n");
}

function emitMarkdownTableValueRowFromFieldNameAndFieldValue(
  fieldName: string,
  fieldValue: string | number,
): string {
  // Escape pipe characters inside the value so they don't break the table.
  const escapedValue = String(fieldValue).replace(/\\|/g, "\\\\|");
  return \`| **\${fieldName}** | \${escapedValue} |\`;
}

function renderSingleMarkerSection(markerNameTokenIncludingSuffix: string): string {
  const entry = MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY.find(
    (candidateEntry) =>
      candidateEntry.markerNameTokenIncludingSuffix === markerNameTokenIncludingSuffix,
  );
  if (entry === undefined) {
    throw new Error(\`registry lookup failed for marker token: \${markerNameTokenIncludingSuffix}\`);
  }

  const reasonPolicyHumanReadable =
    entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 0
      ? "Bare marker accepted (no reason required)"
      : \`Reason required after colon — minimum \${entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional} characters\`;

  const exampleCommentForm =
    entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 0
      ? \`# \${entry.markerNameTokenIncludingSuffix}\`
      : \`# \${entry.markerNameTokenIncludingSuffix}: explain the deliberate exception here in at least \${entry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional} characters\`;

  return [
    \`## \\\`\${entry.markerNameTokenIncludingSuffix}\\\`\`,
    "",
    emitMarkdownTableHeaderRowAndSeparatorRow(),
    emitMarkdownTableValueRowFromFieldNameAndFieldValue(
      "Consumer hook",
      \`\\\`\${entry.consumerHookSourceFileRelativePath}\\\`\`,
    ),
    emitMarkdownTableValueRowFromFieldNameAndFieldValue(
      "Case-sensitivity mode",
      \`\\\`\${entry.caseSensitivityModeDeclaredAtConsumerCallSite}\\\`\`,
    ),
    emitMarkdownTableValueRowFromFieldNameAndFieldValue(
      "Window-semantics mode",
      \`\\\`\${entry.windowSemanticsModeDeclaredAtConsumerCallSite}\\\`\`,
    ),
    emitMarkdownTableValueRowFromFieldNameAndFieldValue(
      "Reason policy",
      reasonPolicyHumanReadable,
    ),
    "",
    \`**What it does**: \${entry.humanReadableEscapeHatchDescriptionForOperatorDocumentation}\`,
    "",
    "**Example usage**:",
    "",
    "\\\`\\\`\\\`",
    exampleCommentForm,
    "\\\`\\\`\\\`",
    "",
  ].join("\\n");
}

function renderCompleteOperatorFacingMarkdownReferenceDocument(): string {
  const sortedMarkerTokens = listAllCanonicalRegistryMarkerNameTokensSortedAlphabetically();

  const documentPreamble = [
    "# Marketplace Escape-Hatch Marker Reference",
    "",
    "> **Auto-generated** from the iter-111 canonical producer-marker registry at",
    "> \\\`plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts\\\`.",
    "> Do NOT edit this file directly — edits will be overwritten by the iter-113 generator on next regeneration.",
    "> To add or modify a marker, edit the registry source and re-run:",
    ">",
    "> \\\`\\\`\\\`bash",
    "> mise run generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry",
    "> \\\`\\\`\\\`",
    "",
    "## Purpose",
    "",
    "Every consumer hook in the marketplace honors an escape-hatch marker comment that lets operators opt out of the hook's enforcement on a per-file (or per-line) basis. This document catalogs every legitimate marker token with its consumer hook, case-sensitivity policy, window-semantics policy, and operator-readable description.",
    "",
    "## How to use this reference",
    "",
    "1. Identify the hook whose enforcement you want to suppress (e.g., \\\`process-storm-guard\\\`, \\\`file-size-guard\\\`).",
    "2. Locate the corresponding marker section below.",
    "3. Write the marker into your source file using the example syntax.",
    "4. The hook will recognize the marker on next invocation and skip its check for that file.",
    "",
    "## Marketplace invariants (audit-enforced)",
    "",
    "- **iter-110 STRICT-BLOCK** (release preflight Check 4s): every consumer hook in the canonical cohort must route its marker detection through the iter-107 shared helper. Silent removal of a cohort member's helper import fails release.",
    "- **iter-111 informational** (release preflight Check 4t): every producer-side marker token written in any marketplace file must appear in the canonical registry. Unregistered tokens are flagged as POTENTIAL TYPOS.",
    "- **iter-113 informational** (release preflight Check 4u): the on-disk \\\`docs/marketplace-escape-hatch-marker-reference.md\\\` (this file) must be in sync with the canonical registry source. Drift is reported via the iter-113 doc-drift detector.",
    "",
    \`## Marker catalog (\${sortedMarkerTokens.length} registered markers)\`,
    "",
  ];

  const renderedMarkerSections = sortedMarkerTokens.map(renderSingleMarkerSection);

  const documentPostamble = [
    "## Marketplace UPPER-KEBAB-CASE convention",
    "",
    "All markers follow the UPPER-KEBAB-CASE-OK shape (except \\\`SSoT-OK\\\` which is grandfathered mixed-case). This convention was chosen because UPPER-KEBAB-CASE tokens never collide with code identifiers, so substring matching is safe across all comment styles (\\\`#\\\`, \\\`//\\\`, \\\`<!-- -->\\\`) and prefix variants (with or without leading prefix).",
    "",
    "## Adding a new marker",
    "",
    "1. Implement the consumer-side detection in the hook source file using \\\`hasFileWideEscapeHatchMarkerInContent(...)\\\` or \\\`detectEscapeHatchMarkerCoveringTargetSourceLine(...)\\\` from \\\`plugins/itp-hooks/hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts\\\`.",
    "2. Add an entry to the registry at \\\`plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts\\\`.",
    "3. Add the consumer hook to the iter-110 canonical-cohort array in \\\`.mise/tasks/audit-marketplace-wide-escape-hatch-marker-detection-inventory-...\\\`.",
    "4. Re-run \\\`mise run generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry\\\` to regenerate this document.",
    "5. Commit all four changes atomically.",
    "",
    "## Related documentation",
    "",
    "- [HOOKS.md — iter-107 → iter-113 escape-hatch consolidation arc](./HOOKS.md)",
    "- [iter-111 canonical registry source](../plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts)",
    "- [iter-107 shared helper source](../plugins/itp-hooks/hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts)",
    "",
  ];

  return [
    ...documentPreamble,
    ...renderedMarkerSections,
    ...documentPostamble,
  ].join("\\n");
}

process.stdout.write(renderCompleteOperatorFacingMarkdownReferenceDocument());
EOF

# Generate the doc to a temp file (so --check mode can diff without modifying state)
GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH=$(mktemp -t iter113-generated-doc-XXXXXX.md)
trap 'rm -rf "$RENDERER_TEMP_SCRIPT_DIRECTORY" "$GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH"' EXIT

if ! (cd "$REPO_ROOT" && bun "$RENDERER_TEMP_SCRIPT_DIRECTORY/render-from-iter111-registry.ts" > "$GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH" 2>/tmp/iter113-renderer-stderr.log); then
    echo "✗ Renderer failed — see /tmp/iter113-renderer-stderr.log"
    cat /tmp/iter113-renderer-stderr.log
    exit 1
fi

case "$INVOCATION_MODE" in
    stdout)
        cat "$GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH"
        ;;
    check)
        if [[ ! -f "$OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH" ]]; then
            echo "✗ DRIFT: on-disk doc does not exist:"
            echo "    $OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH"
            echo "  Fix: mise run generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry"
            exit 1
        fi
        if ! diff -q "$OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH" "$GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH" >/dev/null 2>&1; then
            echo "✗ DRIFT: on-disk doc is out of sync with iter-111 canonical registry"
            echo "  Diff (expected on-disk -- vs ++ generator output):"
            diff -u "$OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH" "$GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH" | head -50
            echo ""
            echo "  Fix: mise run generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry"
            exit 1
        fi
        echo "  ✓ On-disk doc matches iter-111 canonical registry (no drift)"
        ;;
    write)
        cp "$GENERATED_DOC_TEMP_FILE_ABSOLUTE_PATH" "$OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH"
        echo "  ✓ Regenerated $OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH"
        # Count rendered marker sections (each starts with `## \`...\``) directly
        # from the generated doc — avoids the false-positive that counting
        # `markerNameTokenIncludingSuffix:` in the registry source would
        # produce (interface field + Pick declarations would inflate the count).
        RENDERED_MARKER_SECTION_COUNT=$(grep -c '^## `' "$OPERATOR_FACING_MARKDOWN_REFERENCE_DOC_ABSOLUTE_PATH" || echo 0)
        echo "    ($RENDERED_MARKER_SECTION_COUNT markers rendered)"
        ;;
esac

exit 0
