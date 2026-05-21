#!/usr/bin/env bash
#MISE description="Iter-116 operator-facing reverse-search: 'I want to opt out of THIS hook/audit-task — what marker do I write?' Takes a consumer source file relative path argument (e.g., plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts OR .mise/tasks/audit-...-iter106.sh) and reports every registered escape-hatch marker token that opts the caller out of that consumer's enforcement, spanning both the iter-111 RUNTIME-HOOK canonical registry and the iter-114 AUDIT-TASK canonical registry. Exits 0 when ≥1 marker found, exits 2 when no markers target the path, exits 1 on usage error."

# ────────────────────────────────────────────────────────────────────────
# Iter-116 design rationale (operator-facing CLI side)
# ────────────────────────────────────────────────────────────────────────
#
# Pre-iter-116 operator workflow:
#
#   $ # I want to suppress file-size-guard for one file. What marker?
#   $ # Choice 1: Open docs/marketplace-escape-hatch-marker-reference.md
#   $ #           and table-scan 20 sections looking for "file-size-guard".
#   $ # Choice 2: grep the iter-111 registry for the hook path string.
#   $ # Choice 3: read the hook source to find the marker token passed
#   $ #           to the iter-107 helper.
#
# Post-iter-116 operator workflow:
#
#   $ mise run lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts
#   ✓ Found 1 escape-hatch marker for consumer:
#       plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts
#
#     Marker:                 FILE-SIZE-OK
#     Lifecycle layer:        RUNTIME-HOOK (iter-111; consumed at every …)
#     …
#
# Exit-code policy (designed for CI / scripted operator use):
#
#   0 : ≥1 marker found and printed
#   1 : usage error (missing arg, --help)
#   2 : path is well-formed but no markers target it. Operator sees a
#       compact "available consumers" hint listing every distinct
#       consumer path the registry knows about (sourced from the
#       iter-116 accessor's listAllDistinctConsumerSourceFileRelativePaths…
#       helper) so they can grep/fuzzy-match to find the closest match.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-marker-reverse-search-accessor-by-consumer-source-file-relative-path-spanning-iter111-runtime-hook-and-iter114-audit-task-canonical-registries-iter116.ts"

print_usage_and_exit_one() {
    echo "Usage: mise run $(basename "$0" .sh) <consumer-source-file-relative-path>"
    echo ""
    echo "  Reverse-search the iter-111 + iter-114 canonical escape-hatch-marker"
    echo "  registries by consumer source file relative path. Returns every"
    echo "  marker token that opts the caller out of that consumer's enforcement."
    echo ""
    echo "Arguments:"
    echo "  consumer-source-file-relative-path"
    echo "      Repo-root-relative path to a hook source file (under"
    echo "      plugins/itp-hooks/hooks/) OR an audit task source file (under"
    echo "      .mise/tasks/). Must match the registry-declared path exactly."
    echo ""
    echo "Examples:"
    echo "  mise run lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries \\"
    echo "      plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
    echo ""
    echo "  mise run lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries \\"
    echo "      .mise/tasks/audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null-iter65-iter101.sh"
    echo ""
    echo "Exit codes:"
    echo "  0 : ≥1 marker found and printed"
    echo "  1 : usage error (missing arg, --help)"
    echo "  2 : path is well-formed but no markers target it"
    exit 1
}

if [[ "$#" -ne 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    print_usage_and_exit_one
fi

OPERATOR_SUPPLIED_CONSUMER_SOURCE_FILE_RELATIVE_PATH="$1"

# ════════════════════════════════════════════════════════════════════════
# Renderer: small TypeScript program executed via bun. Inline (heredoc)
# rather than a separate file to keep the operator CLI self-contained.
# ════════════════════════════════════════════════════════════════════════

RENDERER_TEMP_SCRIPT_DIRECTORY=$(mktemp -d -t iter116-reverse-search-XXXXXX)
trap 'rm -rf "$RENDERER_TEMP_SCRIPT_DIRECTORY"' EXIT

cat > "$RENDERER_TEMP_SCRIPT_DIRECTORY/reverse-search-from-cli.ts" <<EOF
import {
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries,
  listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically,
  renderSingleReverseSearchHitAsHumanReadableTerminalBlock,
} from "$ITER116_REVERSE_SEARCH_ACCESSOR_TYPESCRIPT_ABSOLUTE_PATH";

const operatorSuppliedConsumerSourceFileRelativePath = "$OPERATOR_SUPPLIED_CONSUMER_SOURCE_FILE_RELATIVE_PATH";

const reverseSearchHits =
  lookupAllCanonicalRegistryEntriesByConsumerHookOrAuditTaskSourceFileRelativePathAcrossBothRegistries(
    operatorSuppliedConsumerSourceFileRelativePath,
  );

if (reverseSearchHits.length === 0) {
  console.error(
    \`✗ No registered escape-hatch markers target this consumer path:\\n    \${operatorSuppliedConsumerSourceFileRelativePath}\\n\`,
  );
  const distinctRegisteredConsumerPaths =
    listAllDistinctConsumerSourceFileRelativePathsAcrossBothRegistriesSortedAlphabetically();
  console.error(
    \`  Hint: \${distinctRegisteredConsumerPaths.length} distinct consumer paths are currently registered\\n  across the iter-111 + iter-114 canonical registries:\\n\`,
  );
  for (const distinctRegisteredConsumerPath of distinctRegisteredConsumerPaths) {
    console.error(\`    - \${distinctRegisteredConsumerPath}\`);
  }
  console.error(
    \`\\n  If your consumer is genuinely registered but the path differs (e.g., basename match\\n  but wrong directory), check spelling against the list above. If the consumer is NOT\\n  yet registered, add an entry to the appropriate canonical registry:\\n    - Runtime hooks: plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts\\n    - Audit tasks:  plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts\`,
  );
  process.exit(2);
}

console.log(
  \`✓ Found \${reverseSearchHits.length} escape-hatch marker\${reverseSearchHits.length === 1 ? "" : "s"} for consumer:\\n    \${operatorSuppliedConsumerSourceFileRelativePath}\\n\`,
);

for (let reverseSearchHitIndex = 0; reverseSearchHitIndex < reverseSearchHits.length; reverseSearchHitIndex++) {
  const reverseSearchHit = reverseSearchHits[reverseSearchHitIndex];
  console.log(renderSingleReverseSearchHitAsHumanReadableTerminalBlock(reverseSearchHit));
  if (reverseSearchHitIndex < reverseSearchHits.length - 1) {
    console.log("");
  }
}

process.exit(0);
EOF

set +e
(cd "$REPO_ROOT" && bun "$RENDERER_TEMP_SCRIPT_DIRECTORY/reverse-search-from-cli.ts")
RENDERER_EXIT_CODE=$?
set -e

exit "$RENDERER_EXIT_CODE"
