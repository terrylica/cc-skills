#!/usr/bin/env bash
#MISE description="Iter-114 regression test for the audit-task escape-hatch marker registry. Verifies (1) iter-114 audit-task registry TypeScript file exists with all documented exports (entry interface + registry array + lookup + list-all helpers); (2) registry contains all 8 iter-114 baseline audit markers (ESCAPE-HATCH-AUDIT-OK, HOOK-OUTPUT-SIZE-CAP-OK, MATCHER-NO-MULTIEDIT-OK, ORDERING-OK, POSTTOOLUSE-RAW-STDOUT-OK, SPAWN-SYNC-OK, STOP-HOOK-ADDITIONAL-CONTEXT-OK, WILDCARD-MATCHER-OK); (3) every registered audit marker references an EXISTING .mise/tasks/audit-*.sh consumer task file; (4) iter-113 doc generator renders audit-task section alongside runtime section in operator-facing reference doc with all 8 baseline audit markers; (5) lookup-by-name helper resolves known + returns undefined for unknown; (6) generator idempotency invariant still holds with the two-registry input."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-mise-task-iter114.ts"
ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH="$REPO_ROOT/docs/marketplace-escape-hatch-marker-reference.md"
ITER113_DOC_GENERATOR_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry.sh"

ITER114_BASELINE_AUDIT_MARKER_TOKENS=(
    "ESCAPE-HATCH-AUDIT-OK"
    "HOOK-OUTPUT-SIZE-CAP-OK"
    "MATCHER-NO-MULTIEDIT-OK"
    "ORDERING-OK"
    "POSTTOOLUSE-RAW-STDOUT-OK"
    "SPAWN-SYNC-OK"
    "STOP-HOOK-ADDITIONAL-CONTEXT-OK"
    "WILDCARD-MATCHER-OK"
)

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-114 audit-task escape-hatch-marker canonical registry regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: registry file exists with documented exports ────────────────
if [[ -f "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" ]] && \
   grep -qE "^export interface MarketplaceWideAuditTaskEscapeHatchMarkerCanonicalRegistryEntry" "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export const MARKETPLACE_WIDE_AUDIT_TASK_ESCAPE_HATCH_MARKER_CANONICAL_REGISTRY" "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function lookupAuditTaskCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent" "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function listAllAuditTaskCanonicalRegistryMarkerNameTokensSortedAlphabetically" "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-114 audit-task registry exists with all 4 documented exports (entry interface + registry array + lookup function + list-all function)"
else
    assert_fails "Case 1: iter-114 audit-task registry missing or missing required exports"
fi

# ─── Case 2: registry contains all 8 iter-114 baseline audit markers ─────
MISSING_BASELINE_AUDIT_MARKER_COUNT=0
for baseline_marker_token in "${ITER114_BASELINE_AUDIT_MARKER_TOKENS[@]}"; do
    if ! grep -q "markerNameTokenIncludingSuffix: \"$baseline_marker_token\"" "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH"; then
        MISSING_BASELINE_AUDIT_MARKER_COUNT=$((MISSING_BASELINE_AUDIT_MARKER_COUNT + 1))
        echo "    (missing baseline audit marker: $baseline_marker_token)"
    fi
done
if [[ "$MISSING_BASELINE_AUDIT_MARKER_COUNT" -eq 0 ]]; then
    assert_passes "Case 2: registry contains all 8 iter-114 baseline audit markers"
else
    assert_fails "Case 2: registry missing $MISSING_BASELINE_AUDIT_MARKER_COUNT baseline audit marker(s)"
fi

# ─── Case 3: every consumerAuditTaskSourceFileRelativePath exists ────────
MISSING_CONSUMER_TASK_COUNT=0
while IFS= read -r consumer_audit_task_relative_path; do
    [[ -z "$consumer_audit_task_relative_path" ]] && continue
    consumer_audit_task_absolute_path="$REPO_ROOT/$consumer_audit_task_relative_path"
    if [[ ! -f "$consumer_audit_task_absolute_path" ]]; then
        MISSING_CONSUMER_TASK_COUNT=$((MISSING_CONSUMER_TASK_COUNT + 1))
        echo "    (consumer task missing on disk: $consumer_audit_task_relative_path)"
    fi
done < <(grep -oE 'consumerAuditTaskSourceFileRelativePath:\s*"[^"]+"' "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" | sed -E 's/.*"([^"]+)".*/\1/')

if [[ "$MISSING_CONSUMER_TASK_COUNT" -eq 0 ]]; then
    assert_passes "Case 3: every registered audit-task consumer source file exists on disk"
else
    assert_fails "Case 3: $MISSING_CONSUMER_TASK_COUNT registered audit-task consumer source file(s) missing on disk"
fi

# ─── Case 4: iter-113 doc generator renders audit-task section ───────────
MISSING_AUDIT_SECTION_COUNT=0
for baseline_marker_token in "${ITER114_BASELINE_AUDIT_MARKER_TOKENS[@]}"; do
    if ! grep -qF "## \`$baseline_marker_token\` (audit-task)" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        MISSING_AUDIT_SECTION_COUNT=$((MISSING_AUDIT_SECTION_COUNT + 1))
        echo "    (missing audit-task section heading: $baseline_marker_token)"
    fi
done
if [[ "$MISSING_AUDIT_SECTION_COUNT" -eq 0 ]] && \
   grep -qE '## Audit-task marker catalog' "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
    assert_passes "Case 4: iter-113 doc generator renders all 8 audit-task marker sections in the dedicated audit-task catalog (operators get one artifact for both marker families)"
else
    assert_fails "Case 4: $MISSING_AUDIT_SECTION_COUNT audit-task marker section(s) missing OR catalog preamble missing"
fi

# ─── Case 5: lookup-by-name helper resolves known + undefined for unknown ─
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter114-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import {
  lookupAuditTaskCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent,
  listAllAuditTaskCanonicalRegistryMarkerNameTokensSortedAlphabetically,
} from "$ITER114_AUDIT_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH";

let allTestsPassed = true;

// Probe 5a: lookup known audit marker returns full entry
const knownEntry = lookupAuditTaskCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent("WILDCARD-MATCHER-OK");
if (
  knownEntry !== undefined &&
  knownEntry.markerNameTokenIncludingSuffix === "WILDCARD-MATCHER-OK" &&
  knownEntry.consumerAuditTaskSourceFileRelativePath.includes("audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null") &&
  knownEntry.caseSensitivityModeDeclaredAtConsumerCallSite === "CASE_SENSITIVE" &&
  knownEntry.minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional === 10
) {
  console.log("PROBE-5A-PASS: lookup of known audit marker WILDCARD-MATCHER-OK returned fully-populated entry with all required fields");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-5A-FAIL: known-audit-marker lookup returned \${JSON.stringify(knownEntry)}\`);
}

// Probe 5b: lookup unknown audit marker returns undefined
const unknownEntry = lookupAuditTaskCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent("THIS-IS-NOT-A-REAL-AUDIT-MARKER-OK");
if (unknownEntry === undefined) {
  console.log("PROBE-5B-PASS: lookup of unknown audit marker returns undefined");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-5B-FAIL: unknown-audit-marker lookup returned \${JSON.stringify(unknownEntry)} (expected undefined)\`);
}

// Probe 5c: list-all returns 8 sorted audit markers
const sortedAuditMarkers = listAllAuditTaskCanonicalRegistryMarkerNameTokensSortedAlphabetically();
const sortedAlphabetically =
  sortedAuditMarkers.length === 8 &&
  sortedAuditMarkers.every((marker, index) => {
    if (index === 0) return true;
    return sortedAuditMarkers[index - 1].localeCompare(marker) <= 0;
  });
if (sortedAlphabetically) {
  console.log(\`PROBE-5C-PASS: list-all returns exactly \${sortedAuditMarkers.length} audit markers in alphabetical order\`);
} else {
  allTestsPassed = false;
  console.log(\`PROBE-5C-FAIL: list-all returned \${sortedAuditMarkers.length} audit markers, sort-check failed\`);
}

if (!allTestsPassed) process.exit(1);
EOF

set +e
probe_output=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
probe_exit_code=$?
set -e

if [[ "$probe_output" == *"PROBE-5A-PASS"* ]] && [[ "$probe_output" == *"PROBE-5B-PASS"* ]] && [[ "$probe_output" == *"PROBE-5C-PASS"* ]]; then
    assert_passes "Case 5: audit-task registry lookup + list-all helpers work correctly (known marker resolves with full field set, unknown returns undefined, list-all returns sorted 8-element array)"
else
    assert_fails "Case 5: audit-task registry helper probes failed (exit=$probe_exit_code, output=$probe_output)"
fi

# ─── Case 6: generator --check passes (idempotency invariant intact) ─────
set +e
check_mode_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
check_mode_exit_code=$?
set -e
if [[ "$check_mode_exit_code" == "0" ]] && [[ "$check_mode_output" == *"no drift"* ]]; then
    assert_passes "Case 6: iter-113 doc-generator idempotency invariant still holds with two-registry input (on-disk doc matches registry-derived output, no drift)"
else
    assert_fails "Case 6: generator --check reports drift (exit=$check_mode_exit_code) — likely an iter-114 regeneration was not committed"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-114 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-114 audit-task escape-hatch-marker canonical registry"
echo "     established. Marketplace now has TWO parallel registries:"
echo "     - iter-111 RUNTIME-HOOK markers (12 entries; consumed by"
echo "       Pre/PostToolUse hooks via the iter-107 helper on every"
echo "       Write/Edit/Bash invocation — hot path)"
echo "     - iter-114 AUDIT-TASK markers (8 entries; consumed by .mise/"
echo "       audit tasks via bash grep at release-preflight time — cold"
echo "       path, runs once per release)"
echo "  🚀 iter-113 doc generator extended: operator-facing reference doc"
echo "     now renders BOTH catalogs (20 total markers) in alphabetical"
echo "     order with distinct sections — single artifact for marker"
echo "     discovery across both lifecycle layers."
echo "  🚀 Iter-115+ candidates:"
echo "     - Promote iter-111 audit Check 4t + iter-113 drift Check 4u"
echo "       from informational to STRICT-BLOCK now that both marker"
echo "       families are registered"
echo "     - Add reverse-search accessor"
echo "       lookupCanonicalRegistryEntryByConsumerHookSourceFileRelativePath"
echo "       (suppression-target → marker) across BOTH registries"
